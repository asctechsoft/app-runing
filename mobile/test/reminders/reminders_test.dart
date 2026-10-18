import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/permissions/permission_coordinator.dart';
import 'package:stride/core/providers.dart';
import 'package:stride/features/reminders/reminder_logic.dart';
import 'package:stride/features/reminders/reminder_repository.dart';
import 'package:stride/features/reminders/reminder_scheduler.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class _FakeScheduler implements ReminderScheduler {
  final applied = <ReminderKind, List<ReminderSlot>>{};
  @override
  Future<void> apply(Reminder r, List<ReminderSlot> slots) async => applied[r.kind] = slots;
}

void main() {
  sqfliteFfiInit();

  group('quiet hours', () {
    test('khoảng qua nửa đêm 22:00 → 07:00', () {
      const q = QuietHours(enabled: true, startMin: 22 * 60, endMin: 7 * 60);
      expect(isInQuietHours(23 * 60, q), isTrue);
      expect(isInQuietHours(3 * 60, q), isTrue);
      expect(isInQuietHours(7 * 60, q), isFalse, reason: 'end là mở');
      expect(isInQuietHours(22 * 60, q), isTrue);
      expect(isInQuietHours(12 * 60, q), isFalse);
    });

    test('khoảng trong ngày 13:00 → 14:00; tắt → không chặn', () {
      const q = QuietHours(enabled: true, startMin: 13 * 60, endMin: 14 * 60);
      expect(isInQuietHours(13 * 60 + 30, q), isTrue);
      expect(isInQuietHours(14 * 60, q), isFalse);
      expect(isInQuietHours(13 * 60 + 30, q.copyWith(enabled: false)), isFalse);
    });

    test('encode/decode và dữ liệu hỏng → mặc định', () {
      const q = QuietHours(enabled: true, startMin: 1320, endMin: 420);
      expect(QuietHours.decode(q.encode()), q);
      expect(QuietHours.decode('{bad'), QuietHours.defaults);
    });
  });

  group('lịch nhắc', () {
    const quietOff = QuietHours.defaults;
    // Chủ nhật 2026-10-18 10:00.
    final now = DateTime(2026, 10, 18, 10);

    test('next fire: hôm nay nếu giờ chưa qua, bỏ qua ngày không chọn', () {
      final r = Reminder.defaults(ReminderKind.dailySteps).copyWith(enabled: true, minuteOfDay: 18 * 60 + 30, weekdays: {DateTime.sunday});
      expect(nextReminderFire(r, quietOff, now), DateTime(2026, 10, 18, 18, 30));
      final weekday = r.copyWith(weekdays: {DateTime.monday, DateTime.wednesday});
      expect(nextReminderFire(weekday, quietOff, now), DateTime(2026, 10, 19, 18, 30));
    });

    test('giờ đã qua hôm nay → tuần sau cùng thứ', () {
      final r = Reminder.defaults(ReminderKind.run).copyWith(enabled: true, minuteOfDay: 7 * 60, weekdays: {DateTime.sunday});
      expect(nextReminderFire(r, quietOff, now), DateTime(2026, 10, 25, 7));
    });

    test('tắt, không có ngày, hoặc nằm trong quiet hours → không có lịch', () {
      final base = Reminder.defaults(ReminderKind.run).copyWith(minuteOfDay: 6 * 60, weekdays: {1, 2, 3});
      expect(reminderSlots(base, quietOff), isEmpty);
      expect(nextReminderFire(base, quietOff, now), isNull);
      expect(reminderSlots(base.copyWith(enabled: true, weekdays: {}), quietOff), isEmpty);
      const quiet = QuietHours(enabled: true, startMin: 22 * 60, endMin: 7 * 60);
      expect(reminderSlots(base.copyWith(enabled: true), quiet), isEmpty);
      expect(reminderSlots(base.copyWith(enabled: true, minuteOfDay: 8 * 60), quiet).length, 3);
    });

    test('slot id cố định theo loại + thứ, không trùng giữa hai loại', () {
      final a = reminderSlots(Reminder.defaults(ReminderKind.dailySteps).copyWith(enabled: true, weekdays: {1, 2, 3, 4, 5, 6, 7}), quietOff);
      final b = reminderSlots(Reminder.defaults(ReminderKind.run).copyWith(enabled: true, weekdays: {1, 2, 3, 4, 5, 6, 7}), quietOff);
      final ids = {...a.map((s) => s.notificationId), ...b.map((s) => s.notificationId)};
      expect(ids.length, 14);
    });

    test('nextSlotTime trả thời điểm đúng thứ, sau now', () {
      const s = ReminderSlot(notificationId: 1, weekday: DateTime.sunday, hour: 9, minute: 0);
      expect(nextSlotTime(s, now), DateTime(2026, 10, 25, 9));
      const s2 = ReminderSlot(notificationId: 2, weekday: DateTime.tuesday, hour: 9, minute: 15);
      expect(nextSlotTime(s2, now), DateTime(2026, 10, 20, 9, 15));
    });

    test('formatMinuteOfDay', () {
      expect(formatMinuteOfDay(0), '12:00 AM');
      expect(formatMinuteOfDay(18 * 60 + 30), '6:30 PM');
      expect(formatMinuteOfDay(12 * 60 + 5), '12:05 PM');
    });
  });

  test('resolveLocalLocation trả zone có cùng offset hiện tại', () {
    tzdata.initializeTimeZones();
    final now = DateTime.now();
    final loc = resolveLocalLocation(now: now);
    expect(loc.timeZone(now.toUtc().millisecondsSinceEpoch).offset, now.timeZoneOffset);
  });

  group('repository + sync', () {
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:r'});
    });
    tearDown(() => db.close());

    Future<(ProviderContainer, _FakeScheduler)> make(PermStatus notif) async {
      final prefs = await SharedPreferences.getInstance();
      final sched = _FakeScheduler();
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.notification: notif})),
          remindersSchedulerProvider.overrideWithValue(sched),
        ],
      );
      addTearDown(c.dispose);
      return (c, sched);
    }

    test('lưu/đọc lại bảng reminders; mặc định là tắt', () async {
      final (c, _) = await make(PermStatus.granted);
      final repo = c.read(remindersRepositoryProvider);
      final initial = await repo.load('guest:r');
      expect(initial.values.every((r) => !r.enabled), isTrue);
      final r = Reminder.defaults(ReminderKind.run).copyWith(enabled: true, minuteOfDay: 400, weekdays: {1, 7});
      await repo.save('guest:r', r);
      expect((await repo.load('guest:r'))[ReminderKind.run], r);
    });

    test('quyền notification bị từ chối → không lên lịch dù người dùng đã bật', () async {
      final (c, sched) = await make(PermStatus.denied);
      final repo = c.read(remindersRepositoryProvider);
      await repo.save('guest:r', Reminder.defaults(ReminderKind.dailySteps).copyWith(enabled: true));
      await c.read(remindersSyncProvider)();
      expect(sched.applied[ReminderKind.dailySteps], isEmpty);
    });

    test('có quyền → lên lịch; tắt → hủy (slots rỗng)', () async {
      final (c, sched) = await make(PermStatus.granted);
      final repo = c.read(remindersRepositoryProvider);
      final r = Reminder.defaults(ReminderKind.dailySteps).copyWith(enabled: true, weekdays: {1, 3, 5});
      await repo.save('guest:r', r);
      await c.read(remindersSyncProvider)();
      expect(sched.applied[ReminderKind.dailySteps]!.length, 3);
      expect(sched.applied[ReminderKind.run], isEmpty);
      await repo.save('guest:r', r.copyWith(enabled: false));
      await c.read(remindersSyncProvider)();
      expect(sched.applied[ReminderKind.dailySteps], isEmpty);
    });
  });
}
