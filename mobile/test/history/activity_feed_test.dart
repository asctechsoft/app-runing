import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/activity_repository.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/history/activity_feed_controller.dart';

import '../activity/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late ActivityRepository repo;
  final oct = DateTime(2026, 10);
  final nov = DateTime(2026, 11);

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    repo = ActivityRepository(db, FakeClock(DateTime(2026, 10, 18, 9).millisecondsSinceEpoch));
  });
  tearDown(() => db.close());

  ActivityFilter filter({Set<ActivityType>? types}) =>
      ActivityFilter(ownerId: 'o', types: types, fromMs: oct.millisecondsSinceEpoch, toMs: nov.millisecondsSinceEpoch);

  Future<void> seed() async {
    for (var i = 1; i <= 9; i++) {
      await saveFixtureActivity(
        repo,
        owner: 'o',
        start: DateTime(2026, 10, i, 7),
        distanceM: 1000.0 * i,
        movingMs: 300000 * i,
        type: i.isEven ? ActivityType.walk : ActivityType.run,
      );
    }
    // Ngoài tháng, owner khác, đã xóa, bản nháp: không được tính.
    await saveFixtureActivity(repo, owner: 'o', start: DateTime(2026, 9, 30, 7));
    await saveFixtureActivity(repo, owner: 'other', start: DateTime(2026, 10, 3, 7));
    final del = await saveFixtureActivity(repo, owner: 'o', start: DateTime(2026, 10, 4, 7));
    await repo.deleteActivity('o', del.id);
    await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
  }

  test('totals bằng tổng của list cùng bộ lọc (All / Run / Walk)', () async {
    await seed();
    for (final types in [
      null,
      {ActivityType.run},
      {ActivityType.walk},
    ]) {
      final c = ActivityFeedController(repo, pageSize: 3);
      await c.load(filter(types: types));
      while (c.hasMore) {
        await c.loadMore();
      }
      final t = c.totals!;
      expect(c.items.length, t.count, reason: 'types=$types');
      expect(c.items.fold<double>(0, (a, x) => a + (x.distanceM ?? 0)), t.distanceM);
      expect(c.items.fold<int>(0, (a, x) => a + x.movingMs), t.movingMs);
      c.dispose();
    }
  });

  test('phân trang keyset ổn định khi nhiều hoạt động cùng startedAt', () async {
    final same = DateTime(2026, 10, 10, 7);
    final ids = <String>{};
    for (var i = 0; i < 25; i++) {
      ids.add((await saveFixtureActivity(repo, owner: 'o', start: same)).id);
    }
    final c = ActivityFeedController(repo, pageSize: 7);
    await c.load(filter());
    var guard = 0;
    while (c.hasMore && guard++ < 10) {
      await c.loadMore();
    }
    final got = c.items.map((a) => a.id).toList();
    expect(got.length, 25);
    expect(got.toSet(), ids);
    // Thứ tự ổn định: (started_at DESC, id DESC).
    final sorted = [...got]..sort((a, b) => b.compareTo(a));
    expect(got, sorted);
    expect(c.totals!.count, 25);
    c.dispose();
  });

  test('ownerTotal phân biệt chưa có hoạt động với filter rỗng', () async {
    final c = ActivityFeedController(repo);
    await c.load(filter());
    expect(c.ownerTotal, 0);
    await saveFixtureActivity(repo, owner: 'o', start: DateTime(2026, 8, 1, 7));
    await c.load(filter());
    expect(c.items, isEmpty);
    expect(c.ownerTotal, 1);
    c.dispose();
  });

  test('ActivityFilter so sánh theo giá trị (set loại không phân biệt thứ tự)', () {
    final a = ActivityFilter(ownerId: 'o', types: {ActivityType.run, ActivityType.walk});
    final b = ActivityFilter(ownerId: 'o', types: {ActivityType.walk, ActivityType.run});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
