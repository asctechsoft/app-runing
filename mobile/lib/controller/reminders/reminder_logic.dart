import 'dart:convert';

import '../../utils/l10n.dart';

/// Loại nhắc (J02; [streak] = TM52 nhắc giữ chuỗi).
enum ReminderKind { dailySteps, run, streak }

/// Một lịch nhắc. [enabled] là ý định của người dùng; nhắc chỉ "active" khi đồng thời có quyền notification.
class Reminder {
  const Reminder({required this.kind, required this.enabled, required this.minuteOfDay, required this.weekdays, this.updatedAt = 0});

  final ReminderKind kind;
  final bool enabled;

  /// Phút trong ngày theo giờ địa phương (0..1439).
  final int minuteOfDay;

  /// DateTime.monday (1) … DateTime.sunday (7).
  final Set<int> weekdays;
  final int updatedAt;

  /// Mặc định khi chưa từng cấu hình (tắt — không tự bật nhắc).
  factory Reminder.defaults(ReminderKind kind) => switch (kind) {
    ReminderKind.dailySteps => const Reminder(kind: ReminderKind.dailySteps, enabled: false, minuteOfDay: 18 * 60 + 30, weekdays: {1, 2, 3, 4, 5}),
    ReminderKind.run => const Reminder(kind: ReminderKind.run, enabled: false, minuteOfDay: 7 * 60, weekdays: {2, 4, 6}),
    ReminderKind.streak => const Reminder(kind: ReminderKind.streak, enabled: false, minuteOfDay: 20 * 60, weekdays: {1, 2, 3, 4, 5, 6, 7}),
  };

  Reminder copyWith({bool? enabled, int? minuteOfDay, Set<int>? weekdays, int? updatedAt}) => Reminder(
    kind: kind,
    enabled: enabled ?? this.enabled,
    minuteOfDay: minuteOfDay ?? this.minuteOfDay,
    weekdays: weekdays ?? this.weekdays,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String get id => 'reminder:${kind.name}';

  Map<String, Object?> toRow(String ownerId) => {
    'id': '$ownerId:${kind.name}',
    'owner_id': ownerId,
    'kind': kind.name,
    'enabled': enabled ? 1 : 0,
    'minute_of_day': minuteOfDay,
    'weekdays': (weekdays.toList()..sort()).join(','),
    'updated_at': updatedAt,
  };

  static Reminder? fromRow(Map<String, Object?> r) {
    final kind = ReminderKind.values.where((k) => k.name == r['kind']).firstOrNull;
    if (kind == null) return null;
    final days = (r['weekdays'] as String? ?? '').split(',').map((s) => int.tryParse(s.trim())).whereType<int>().where((d) => d >= 1 && d <= 7).toSet();
    return Reminder(
      kind: kind,
      enabled: (r['enabled'] as int? ?? 0) == 1,
      minuteOfDay: ((r['minute_of_day'] as int?) ?? 0).clamp(0, 1439),
      weekdays: days,
      updatedAt: r['updated_at'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.kind == kind &&
      other.enabled == enabled &&
      other.minuteOfDay == minuteOfDay &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);
  @override
  int get hashCode => Object.hash(kind, enabled, minuteOfDay, Object.hashAllUnordered(weekdays));
}

/// Giờ yên lặng: không nhắc trong khoảng [startMin, endMin) — có thể qua nửa đêm (vd. 22:00 → 07:00).
class QuietHours {
  const QuietHours({required this.enabled, required this.startMin, required this.endMin});
  static const defaults = QuietHours(enabled: false, startMin: 22 * 60, endMin: 7 * 60);

  final bool enabled;
  final int startMin;
  final int endMin;

  QuietHours copyWith({bool? enabled, int? startMin, int? endMin}) =>
      QuietHours(enabled: enabled ?? this.enabled, startMin: startMin ?? this.startMin, endMin: endMin ?? this.endMin);

  String encode() => jsonEncode({'enabled': enabled, 'start': startMin, 'end': endMin});

  static QuietHours decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return QuietHours(
        enabled: j['enabled'] as bool? ?? false,
        startMin: ((j['start'] as num?)?.toInt() ?? defaults.startMin).clamp(0, 1439),
        endMin: ((j['end'] as num?)?.toInt() ?? defaults.endMin).clamp(0, 1439),
      );
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) => other is QuietHours && other.enabled == enabled && other.startMin == startMin && other.endMin == endMin;
  @override
  int get hashCode => Object.hash(enabled, startMin, endMin);
}

/// Phút [minuteOfDay] có nằm trong giờ yên lặng không.
bool isInQuietHours(int minuteOfDay, QuietHours q) {
  if (!q.enabled || q.startMin == q.endMin) return false;
  if (q.startMin < q.endMin) return minuteOfDay >= q.startMin && minuteOfDay < q.endMin;
  return minuteOfDay >= q.startMin || minuteOfDay < q.endMin; // qua nửa đêm
}

/// Một slot lặp hằng tuần cần đăng ký với OS.
class ReminderSlot {
  const ReminderSlot({required this.notificationId, required this.weekday, required this.hour, required this.minute, this.at});
  final int notificationId;
  final int weekday;
  final int hour;
  final int minute;

  /// Có giá trị = nhắc một lần đúng thời điểm này (giờ địa phương), không lặp hằng tuần (TM52).
  final DateTime? at;
}

/// ID notification cố định theo loại + thứ để hủy/đặt lại chính xác.
int reminderNotificationId(ReminderKind kind, int weekday) => 7100 + kind.index * 10 + weekday;

/// Các slot cần lên lịch. Tắt, không chọn ngày, hoặc giờ nằm trong quiet hours → rỗng (nhắc bị bỏ qua).
List<ReminderSlot> reminderSlots(Reminder r, QuietHours q) {
  if (!r.enabled || r.weekdays.isEmpty || isInQuietHours(r.minuteOfDay, q)) return const [];
  return [
    for (final d in (r.weekdays.toList()..sort()))
      ReminderSlot(notificationId: reminderNotificationId(r.kind, d), weekday: d, hour: r.minuteOfDay ~/ 60, minute: r.minuteOfDay % 60),
  ];
}

/// TM52: thời điểm nhắc giữ chuỗi kế tiếp — chỉ MỘT lần, lên lịch lại mỗi khi app đồng bộ lịch nhắc (khởi động, resume,
/// đạt mục tiêu trong app). Không có chuỗi đang giữ ([hasStreak] = false) → không nhắc (tránh tạo áp lực). Hôm nay đã đạt
/// hoặc giờ nhắc hôm nay đã qua → ngày được chọn kế tiếp. Ngày rơi vào giờ yên lặng → không nhắc.
DateTime? nextStreakReminder(Reminder r, QuietHours q, DateTime now, {required bool hasStreak, required bool todayDone}) {
  if (!hasStreak || reminderSlots(r, q).isEmpty) return null;
  for (var i = todayDone ? 1 : 0; i <= 7; i++) {
    final c = DateTime(now.year, now.month, now.day + i, r.minuteOfDay ~/ 60, r.minuteOfDay % 60);
    if (c.isAfter(now) && r.weekdays.contains(c.weekday)) return c;
  }
  return null;
}

/// Số giờ trọn còn lại từ [at] tới hết ngày địa phương (nội dung "còn X giờ để giữ chuỗi").
int hoursLeftInDay(DateTime at) => DateTime(at.year, at.month, at.day + 1).difference(at).inMinutes ~/ 60;

/// Lần nhắc kế tiếp (giờ địa phương) sau [now]; null nếu không có lịch hiệu lực.
DateTime? nextReminderFire(Reminder r, QuietHours q, DateTime now) {
  if (reminderSlots(r, q).isEmpty) return null;
  for (var i = 0; i <= 7; i++) {
    final c = DateTime(now.year, now.month, now.day + i, r.minuteOfDay ~/ 60, r.minuteOfDay % 60);
    if (c.isAfter(now) && r.weekdays.contains(c.weekday)) return c;
  }
  return null;
}

/// Thời điểm kế tiếp của một slot (thứ + giờ) sau [now] — dùng làm mốc đầu cho lịch lặp hằng tuần.
DateTime nextSlotTime(ReminderSlot s, DateTime now) {
  for (var i = 0; i <= 7; i++) {
    final c = DateTime(now.year, now.month, now.day + i, s.hour, s.minute);
    if (c.weekday == s.weekday && c.isAfter(now)) return c;
  }
  return DateTime(now.year, now.month, now.day + 7, s.hour, s.minute);
}

String formatMinuteOfDay(int m) {
  final h = m ~/ 60;
  final min = m % 60;
  final suffix = h < 12 ? 'reminders_am'.tr : 'reminders_pm'.tr;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${min.toString().padLeft(2, '0')} $suffix';
}

/// TM05: một lần nhắc sự kiện đã đăng ký (đặt một lần, không lặp).
class EventReminderSlot {
  const EventReminderSlot({required this.notificationId, required this.at, required this.title, required this.body, required this.link});
  final int notificationId;
  final DateTime at;
  final String title;
  final String body;
  final String link;
}

/// Dải id thông báo nhắc nhóm (sự kiện TM05 + thử thách TM34): tối đa [maxEventReminders] lần nhắc, gần nhất trước.
const eventReminderIdBase = 7400;
const maxEventReminders = 30;
