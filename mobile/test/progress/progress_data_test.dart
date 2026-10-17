import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/activity_repository.dart';
import 'package:stride/data/settings_repository.dart';
import 'package:stride/data/step_repository.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/domain/models/profile.dart';
import 'package:stride/domain/models/steps.dart';
import 'package:stride/features/progress/period.dart';
import 'package:stride/features/progress/progress_data.dart';

import '../activity/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late ActivityRepository acts;
  late SettingsRepository settings;
  late StepRepository steps;
  late FakeClock clock;
  final now = DateTime(2026, 10, 15, 18); // Thứ Năm

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(now.millisecondsSinceEpoch);
    acts = ActivityRepository(db, clock);
    settings = SettingsRepository(db, clock);
    steps = StepRepository(db, clock);
  });
  tearDown(() => db.close());

  Future<RunningSummary> running(ProgressPeriod p, {DateTime? anchor, int weekStart = DateTime.monday}) => loadRunningSummary(
    activities: acts,
    settings: settings,
    ownerId: 'o',
    range: periodFor(p, anchor ?? now, weekStart),
    now: now,
    types: runningTypes(indoor: true),
    weekStart: weekStart,
  );

  test('tổng tuần bằng tổng các cột, walk không tính, ngày tương lai không có cột', () async {
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 12, 7), distanceM: 5000);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 14, 7), distanceM: 3000);
    await saveFixtureActivity(
      acts,
      owner: 'o',
      start: DateTime(2026, 10, 14, 19),
      distanceM: 2000,
      type: ActivityType.indoorRun,
      hasGps: false,
      source: DistanceSource.steps,
    );
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 13, 7), distanceM: 9000, type: ActivityType.walk);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 11, 23, 30), distanceM: 7000); // Chủ nhật tuần trước

    final s = await running(ProgressPeriod.week);
    expect(s.totals.count, 3);
    expect(s.totals.distanceM, 10000);
    expect(s.buckets.map((b) => b.value ?? 0).fold<double>(0, (a, v) => a + v), s.totals.distanceM);
    expect(s.buckets[2].value, 5000); // Thứ Tư: 3000 + 2000
    expect(s.buckets[3].future, isFalse); // hôm nay (Thứ Năm)
    expect(s.buckets[4].future, isTrue);
    expect(s.buckets[4].value, isNull);

    // Tuần bắt đầu Chủ nhật: buổi tối Chủ nhật 11/10 nằm trong tuần này.
    final sun = await running(ProgressPeriod.week, weekStart: DateTime.sunday);
    expect(sun.totals.distanceM, 17000);
  });

  test('gom theo tháng và năm', () async {
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 1, 31, 23), distanceM: 1000);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 2, 1, 6), distanceM: 2000);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 1, 6), distanceM: 4000);
    final y = await running(ProgressPeriod.year);
    expect(y.buckets.length, 12);
    expect(y.buckets[0].value, 1000);
    expect(y.buckets[1].value, 2000);
    expect(y.buckets[9].value, 4000);
    expect(y.buckets[10].future, isTrue);
    expect(y.totals.distanceM, 7000);
    final feb = await running(ProgressPeriod.month, anchor: DateTime(2026, 2, 10));
    expect(feb.buckets.length, 28);
    expect(feb.totals.distanceM, 2000);
    expect(feb.buckets[0].value, 2000);
  });

  test('pace kỳ = tổng moving / tổng quãng đường GPS (không trung bình pace)', () async {
    // 10 km trong 50 phút (300 s/km) và 1 km trong 10 phút (600 s/km).
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 12, 7), distanceM: 10000, movingMs: 3000000, avgPace: 300);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 13, 7), distanceM: 1000, movingMs: 600000, avgPace: 600);
    // Chạy trong nhà (quãng đường ước tính từ bước) không vào pace kỳ.
    await saveFixtureActivity(
      acts,
      owner: 'o',
      start: DateTime(2026, 10, 14, 7),
      distanceM: 1000,
      movingMs: 1200000,
      type: ActivityType.indoorRun,
      hasGps: false,
      source: DistanceSource.steps,
    );
    final s = await running(ProgressPeriod.week);
    expect(s.paceSecPerKm, closeTo(3600 / 11, 0.01)); // ≈ 327 s/km, không phải (300+600)/2 = 450
  });

  test('so sánh cùng độ phủ: chỉ Mon..Thu của tuần trước', () async {
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 13, 7), distanceM: 5000);
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 6, 7), distanceM: 3000); // Thứ Ba tuần trước
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 10, 7), distanceM: 9000); // Thứ Bảy tuần trước: ngoài độ phủ
    final s = await running(ProgressPeriod.week);
    expect(s.comparison!.coverage.ongoing, isTrue);
    expect(s.comparison!.previous.distanceM, 3000);
    expect(s.comparison!.deltaDistanceM, 2000);
  });

  test('mục tiêu tuần quy đổi tháng/năm', () async {
    await settings.setGoal('o', GoalType.weeklyDistanceM, 20000, effectiveFrom: '2026-01-01');
    expect((await running(ProgressPeriod.week)).target, 20000);
    expect((await running(ProgressPeriod.month)).target, closeTo(20000 * weeksPerMonth, 0.001));
    expect((await running(ProgressPeriod.year)).target, 20000 * weeksPerYear);
  });

  test('steps: chỉ ngày có dữ liệu tính goal days và trung bình; ngày thiếu là null', () async {
    await settings.setGoal('o', GoalType.dailySteps, 8000, effectiveFrom: '2026-01-01');
    Future<void> day(int d, int n) => steps.addSample(
      ownerId: 'o',
      source: StepSource.phoneSensor,
      startAt: DateTime(2026, 10, d, 10).millisecondsSinceEpoch,
      endAt: DateTime(2026, 10, d, 10, 30).millisecondsSinceEpoch,
      steps: n,
    );
    await day(12, 9000);
    await day(13, 4000);
    await day(15, 8000);
    final s = await loadStepsSummary(
      steps: steps,
      settings: settings,
      ownerId: 'o',
      range: periodFor(ProgressPeriod.week, now, DateTime.monday),
      now: now,
      hasPermission: false,
    );
    expect(s.days.length, 4); // Mon..Thu (không có ngày tương lai)
    expect(s.totalSteps, 21000);
    expect(s.averagePerDay, 7000);
    expect(s.goalDaysMet, 2);
    expect(s.withData.length, 3);
    expect(s.buckets[2].value, isNull); // Thứ Tư không có dữ liệu → —
    expect(s.buckets[6].future, isTrue);
    expect(s.currentDailyGoal, 8000);

    // Năm: gom theo tháng từ cùng dữ liệu; tháng không có dữ liệu là null, tháng tương lai trống.
    final y = await loadStepsSummary(
      steps: steps,
      settings: settings,
      ownerId: 'o',
      range: periodFor(ProgressPeriod.year, now, DateTime.monday),
      now: now,
      hasPermission: true,
    );
    expect(y.buckets[9].value, 21000);
    expect(y.buckets[8].value, isNull);
    expect(y.buckets[11].future, isTrue);
    expect(y.totalSteps, 21000);
    expect(y.goalDaysMet, 2);
  });
}
