import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../controller/explore/explore_logic.dart';
import '../../controller/home/home_providers.dart';
import '../../controller/providers.dart';
import '../../controller/reminders/reminder_logic.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../repository/reminder_repository.dart';
import '../../utils/date_locale.dart';
import '../../utils/l10n.dart';
import '../../utils/logger.dart';
import '../../values/routes.dart';
import '../native/permission_coordinator.dart';

/// Đăng ký/hủy lịch nhắc với OS. Bản giả dùng trong test.
abstract class ReminderScheduler {
  /// Hủy toàn bộ slot của [r.kind] rồi đặt lại theo [slots] (rỗng = chỉ hủy).
  Future<void> apply(Reminder r, List<ReminderSlot> slots);

  /// TM05: hủy mọi nhắc sự kiện rồi đặt lại theo [slots] (rỗng = chỉ hủy).
  Future<void> applyEvents(List<EventReminderSlot> slots);
}

/// Deep link của nhắc khi người dùng bấm thông báo.
String reminderDeepLink(ReminderKind k) => switch (k) {
  ReminderKind.dailySteps => Routes.home,
  ReminderKind.run => Routes.run,
  ReminderKind.streak => Routes.home,
};

/// Chọn Location cho tz.local. Flutter không cung cấp IANA id; thử timeZoneName trước (một số máy trả IANA),
/// sau đó tìm zone có cùng offset hiện tại (ưu tiên trùng viết tắt), cuối cùng là UTC.
/// Giới hạn: nếu nhiều zone trùng offset mà khác lịch DST, giờ nhắc có thể lệch 1 giờ quanh ngày đổi giờ
/// cho tới lần reschedule kế tiếp (app reschedule mỗi lần khởi động/resume).
tz.Location resolveLocalLocation({DateTime? now}) {
  final n = now ?? DateTime.now();
  // Chỉ nhận tên dạng IANA "Area/City"; viết tắt như "EST" là zone cố định, không có DST.
  if (n.timeZoneName.contains('/')) {
    try {
      return tz.getLocation(n.timeZoneName);
    } catch (_) {}
  }
  final offsetMs = n.timeZoneOffset.inMilliseconds;
  final utcMs = n.toUtc().millisecondsSinceEpoch;
  tz.Location? byOffset;
  for (final loc in tz.timeZoneDatabase.locations.values) {
    final zone = loc.timeZone(utcMs);
    if (zone.offset.inMilliseconds != offsetMs) continue;
    if (zone.abbreviation == n.timeZoneName) return loc;
    byOffset ??= loc;
  }
  return byOffset ?? tz.UTC;
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler({required this.onTapLink});

  /// Gọi khi người dùng bấm thông báo nhắc (payload = route nội bộ).
  final void Function(String link) onTapLink;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _ensureInit() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(resolveLocalLocation());
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Không xin quyền khi khởi tạo — chỉ xin khi người dùng bật nhắc (qua PermissionCoordinator).
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.startsWith('/')) onTapLink(p);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final p = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && p != null && p.startsWith('/')) onTapLink(p);
    _ready = true;
  }

  @override
  Future<void> apply(Reminder r, List<ReminderSlot> slots) async {
    await _ensureInit();
    // Mỗi lần áp dụng lấy lại múi giờ hiện tại (đổi timezone → reschedule).
    tz.setLocalLocation(resolveLocalLocation());
    for (var d = 1; d <= 7; d++) {
      await _plugin.cancel(id: reminderNotificationId(r.kind, d));
    }
    String title(ReminderSlot s) => switch (r.kind) {
      ReminderKind.dailySteps => 'notif_steps_title'.tr,
      ReminderKind.run => 'notif_run_title'.tr,
      ReminderKind.streak => 'notif_streak_title'.tr,
    };
    String body(ReminderSlot s) => switch (r.kind) {
      ReminderKind.dailySteps => 'notif_steps_body'.tr,
      ReminderKind.run => 'notif_run_body'.tr,
      ReminderKind.streak => 'notif_streak_body'.trPlural(hoursLeftInDay(s.at!), [hoursLeftInDay(s.at!)]),
    };
    final details = NotificationDetails(
      android: AndroidNotificationDetails('stride_reminders', 'notif_channel_name'.tr, channelDescription: 'notif_channel_desc'.tr),
      iOS: const DarwinNotificationDetails(),
    );
    final now = DateTime.now();
    for (final s in slots) {
      final next = s.at ?? nextSlotTime(s, now);
      await _plugin.zonedSchedule(
        id: s.notificationId,
        scheduledDate: tz.TZDateTime(tz.local, next.year, next.month, next.day, next.hour, next.minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title(s),
        body: body(s),
        payload: reminderDeepLink(r.kind),
        // Nhắc một lần (TM52) không lặp; nhắc thường lặp theo thứ + giờ.
        matchDateTimeComponents: s.at == null ? DateTimeComponents.dayOfWeekAndTime : null,
      );
    }
  }

  @override
  Future<void> applyEvents(List<EventReminderSlot> slots) async {
    await _ensureInit();
    tz.setLocalLocation(resolveLocalLocation());
    for (var i = 0; i < maxEventReminders; i++) {
      await _plugin.cancel(id: eventReminderIdBase + i);
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails('stride_events', 'notif_event_channel_name'.tr, channelDescription: 'notif_event_channel_desc'.tr),
      iOS: const DarwinNotificationDetails(),
    );
    for (final s in slots) {
      await _plugin.zonedSchedule(
        id: s.notificationId,
        scheduledDate: tz.TZDateTime.from(s.at, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: s.title,
        body: s.body,
        payload: s.link,
      );
    }
  }
}

/// Link bấm từ thông báo đang chờ điều hướng (HomeScreen nghe và điều hướng qua router để áp auth guard).
class RemindersPendingLink extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? link) => state = link;
}

final remindersPendingLinkProvider = NotifierProvider<RemindersPendingLink, String?>(RemindersPendingLink.new);

final remindersSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalReminderScheduler(onTapLink: (l) => ref.read(remindersPendingLinkProvider.notifier).set(l)),
);

bool isNotificationGranted(PermStatus s) => s == PermStatus.granted || s == PermStatus.limited;

/// Đồng bộ lịch OS với dữ liệu đã lưu: chỉ lên lịch khi người dùng bật VÀ có quyền notification;
/// ngược lại hủy. Gọi khi lưu, khi app khởi động/resume (bắt đổi timezone hoặc quyền bị thu hồi).
Future<void> remindersSyncSchedules(Ref ref) async {
  final owner = ref.read(ownerProvider).ownerId;
  final repo = ref.read(remindersRepositoryProvider);
  final perm = await ref.read(permissionsProvider).status(PermKind.notification);
  final reminders = await repo.load(owner);
  final quiet = await repo.loadQuietHours(owner);
  final scheduler = ref.read(remindersSchedulerProvider);
  for (final r in reminders.values) {
    var slots = isNotificationGranted(perm) ? reminderSlots(r, quiet) : const <ReminderSlot>[];
    if (r.kind == ReminderKind.streak && slots.isNotEmpty) slots = await _streakSlots(ref, r, quiet);
    try {
      await scheduler.apply(r, slots);
    } catch (e, st) {
      StrideLog.e('reminders', e, st);
    }
  }
  try {
    await _syncEventReminders(ref, isNotificationGranted(perm), quiet);
  } catch (e, st) {
    StrideLog.e('reminders', e, st);
  }
}

/// TM05 + TM34: nhắc cục bộ cho sự kiện đã đăng ký (1 ngày / 1 giờ trước) và thử thách đang tham gia (1 ngày trước khi bắt
/// đầu, 1 ngày trước khi kết thúc, lúc chốt kết quả) — gần nhất trước, bỏ mốc rơi vào giờ yên lặng. Chỉ khi có quyền
/// thông báo và đã đăng nhập. Lỗi đọc (offline) → giữ nguyên lịch cũ thay vì hủy.
Future<void> _syncEventReminders(Ref ref, bool granted, QuietHours quiet) async {
  final scheduler = ref.read(remindersSchedulerProvider);
  final flags = ref.read(flagsProvider);
  if (!granted || ref.read(ownerProvider).isGuest || !(flags.exploreClubs || flags.exploreChallenges)) {
    await scheduler.applyEvents(const []);
    return;
  }
  final repo = ref.read(exploreRepositoryProvider);
  final List<ClubEvent> events;
  final List<Challenge> challenges;
  try {
    events = flags.exploreClubs ? await repo.myUpcomingEvents() : const [];
    challenges = flags.exploreChallenges ? await repo.myOpenChallenges() : const [];
  } catch (e) {
    StrideLog.d('reminders', 'group reminders kept: $e');
    return;
  }
  final now = ref.read(clockProvider).nowLocal();
  final pending = <(DateTime, String, String, String)>[]; // (lúc, tiêu đề, nội dung, link)
  for (final e in events) {
    final start = DateTime.fromMillisecondsSinceEpoch(e.startAt);
    for (final at in eventReminderTimes(e.startAt, now)) {
      final dayBefore = start.difference(at) >= const Duration(days: 1);
      pending.add((
        at,
        e.title,
        dayBefore ? 'notif_event_tomorrow'.trArgs([AppDates.time(start)]) : 'notif_event_soon'.trArgs([AppDates.time(start)]),
        Routes.club(e.clubId),
      ));
    }
  }
  for (final c in challenges) {
    for (final (at, kind) in challengeReminderTimes(startsAt: c.startsAt, endsAt: c.endsAt, now: now)) {
      final body = switch (kind) {
        ChallengeReminderKind.startsSoon => 'notif_challenge_starts'.tr,
        ChallengeReminderKind.endsSoon => 'notif_challenge_ends'.tr,
        ChallengeReminderKind.results => 'notif_challenge_results'.tr,
      };
      pending.add((at, c.title, body, kind == ChallengeReminderKind.results ? Routes.challengeResults(c.id) : Routes.challenge(c.id)));
    }
  }
  pending.sort((a, b) => a.$1.compareTo(b.$1));
  final slots = <EventReminderSlot>[];
  for (final (at, title, body, link) in pending) {
    if (slots.length >= maxEventReminders || isInQuietHours(at.hour * 60 + at.minute, quiet)) continue;
    slots.add(EventReminderSlot(notificationId: eventReminderIdBase + slots.length, at: at, title: title, body: body, link: link));
  }
  await scheduler.applyEvents(slots);
}

/// TM52: một slot duy nhất theo tình trạng chuỗi hiện tại; lỗi tính chuỗi → không nhắc (không đoán).
Future<List<ReminderSlot>> _streakSlots(Ref ref, Reminder r, QuietHours quiet) async {
  try {
    final s = await ref.read(personalStreakProvider.future);
    final at = nextStreakReminder(r, quiet, ref.read(clockProvider).nowLocal(), hasStreak: s.current > 0, todayDone: s.todayAchieved);
    if (at == null) return const [];
    return [ReminderSlot(notificationId: reminderNotificationId(r.kind, at.weekday), weekday: at.weekday, hour: at.hour, minute: at.minute, at: at)];
  } catch (e, st) {
    StrideLog.e('reminders', e, st);
    return const [];
  }
}

/// Provider tiện để gọi sync từ widget (ref.read(remindersSyncProvider)()).
final remindersSyncProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => remindersSyncSchedules(ref),
);
