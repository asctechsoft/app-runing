import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/routes.dart';
import '../../core/logging/logger.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import 'reminder_logic.dart';
import 'reminder_repository.dart';

/// Đăng ký/hủy lịch nhắc với OS. Bản giả dùng trong test.
abstract class ReminderScheduler {
  /// Hủy toàn bộ slot của [r.kind] rồi đặt lại theo [slots] (rỗng = chỉ hủy).
  Future<void> apply(Reminder r, List<ReminderSlot> slots);
}

/// Deep link của nhắc khi người dùng bấm thông báo.
String reminderDeepLink(ReminderKind k) => switch (k) {
  ReminderKind.dailySteps => Routes.home,
  ReminderKind.run => Routes.run,
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
    final (title, body) = switch (r.kind) {
      ReminderKind.dailySteps => ('Time to move', 'A short walk helps you reach your daily step goal.'),
      ReminderKind.run => ('Ready for a run?', 'Your planned run time is here.'),
    };
    const details = NotificationDetails(
      android: AndroidNotificationDetails('stride_reminders', 'Move reminders', channelDescription: 'Step and run reminders you set in STRIDE'),
      iOS: DarwinNotificationDetails(),
    );
    final now = DateTime.now();
    for (final s in slots) {
      final next = nextSlotTime(s, now);
      await _plugin.zonedSchedule(
        id: s.notificationId,
        scheduledDate: tz.TZDateTime(tz.local, next.year, next.month, next.day, next.hour, next.minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: reminderDeepLink(r.kind),
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
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
    final slots = isNotificationGranted(perm) ? reminderSlots(r, quiet) : const <ReminderSlot>[];
    try {
      await scheduler.apply(r, slots);
    } catch (e, st) {
      StrideLog.e('reminders', e, st);
    }
  }
}

/// Provider tiện để gọi sync từ widget (ref.read(remindersSyncProvider)()).
final remindersSyncProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => remindersSyncSchedules(ref),
);
