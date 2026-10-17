import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/settings_repository.dart';
import 'package:stride/domain/models/profile.dart';
import 'package:stride/features/goals/goals_logic.dart';

void main() {
  sqfliteFfiInit();

  group('validation (F06)', () {
    test('daily steps 1,000–100,000', () {
      expect(validateDailySteps(999), isNotNull);
      expect(validateDailySteps(1000), isNull);
      expect(validateDailySteps(100000), isNull);
      expect(validateDailySteps(100001), isNotNull);
      expect(validateDailySteps(null), isNotNull);
    });

    test('weekly runs 1–14', () {
      expect(validateWeeklyRuns(0), isNotNull);
      expect(validateWeeklyRuns(1), isNull);
      expect(validateWeeklyRuns(14), isNull);
      expect(validateWeeklyRuns(15), isNotNull);
    });

    test('weekly distance 1–500 km, lưu mét; 1 mi hợp lệ', () {
      expect(validateWeeklyDistanceM(999), isNotNull);
      expect(validateWeeklyDistanceM(1000), isNull);
      expect(validateWeeklyDistanceM(1609.344), isNull);
      expect(validateWeeklyDistanceM(500000), isNull);
      expect(validateWeeklyDistanceM(500001), isNotNull);
    });

    test('clamp bước/runs không vượt giới hạn', () {
      expect(clampSteps(500), 1000);
      expect(clampSteps(200000), 100000);
      expect(clampRuns(0), 1);
      expect(clampRuns(20), 14);
    });
  });

  group('GoalDraft.changedFrom', () {
    test('chỉ trả mục tiêu thực sự đổi', () {
      const original = GoalDraft(dailySteps: 8000, weeklyRuns: 3, weeklyDistanceM: 20000);
      expect(original.changedFrom(original), isEmpty);
      final changed = original.copyWith(dailySteps: 10000, weeklyDistanceM: 20000.2).changedFrom(original);
      expect(changed, {GoalType.dailySteps: 10000});
    });

    test('mục tiêu chưa từng đặt được coi là thay đổi khi lưu', () {
      const original = GoalDraft();
      final changed = const GoalDraft(dailySteps: 8000, weeklyRuns: 3, weeklyDistanceM: 20000).changedFrom(original);
      expect(changed.keys.toSet(), GoalType.values.toSet());
    });
  });

  group('goal effective date (không viết lại ngày đã qua)', () {
    late AppDatabase db;
    late FakeClock clock;
    late SettingsRepository repo;

    setUp(() async {
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      clock = FakeClock(DateTime(2026, 10, 17, 10).millisecondsSinceEpoch);
      repo = SettingsRepository(db, clock);
    });
    tearDown(() => db.close());

    test('sửa mục tiêu hôm nay giữ nguyên mục tiêu của hôm qua', () async {
      await repo.setGoal('o', GoalType.dailySteps, 6000); // từ 2026-10-17
      clock.advance(const Duration(days: 1)); // 2026-10-18
      await repo.setGoal('o', GoalType.dailySteps, 10000);
      expect((await repo.goalFor('o', GoalType.dailySteps, '2026-10-17'))!.value, 6000);
      expect((await repo.goalFor('o', GoalType.dailySteps, '2026-10-18'))!.value, 10000);
      expect(await repo.goalFor('o', GoalType.dailySteps, '2026-10-16'), isNull);
    });

    test('sửa nhiều lần trong ngày → bản mới nhất thắng', () async {
      await repo.setGoal('o', GoalType.dailySteps, 6000);
      clock.advance(const Duration(minutes: 5));
      await repo.setGoal('o', GoalType.dailySteps, 7000);
      expect((await repo.goalFor('o', GoalType.dailySteps, '2026-10-17'))!.value, 7000);
    });
  });
}
