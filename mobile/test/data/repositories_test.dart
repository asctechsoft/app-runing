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

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late FakeClock clock;
  late ActivityRepository repo;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
    repo = ActivityRepository(db, clock);
  });

  tearDown(() => db.close());

  Future<Activity> recordAndSave(String owner, {double distance = 5200}) async {
    final (a, _) = await repo.createSession(
      ownerId: owner,
      type: ActivityType.run,
      goal: const RunGoal.free(),
      monoMs: clock.monoMs(),
      tzId: 'UTC',
      tzOffsetMin: 0,
    );
    clock.advance(const Duration(minutes: 30));
    await repo.appendEvent(activityId: a.id, type: SessionEventType.pause, monoMs: clock.monoMs(), newStatus: ActivityStatus.paused);
    await repo.appendEvent(activityId: a.id, type: SessionEventType.finish, monoMs: clock.monoMs());
    final summary = a.copyWith(distanceM: distance, movingMs: 1800000, elapsedMs: 1800000, endedAt: clock.nowMs(), title: 'Morning run', hasGps: true);
    await repo.finalizeSummary(summary);
    return repo.saveActivity(summary);
  }

  group('ActivityRepository (C03, G10)', () {
    test('không tạo hai phiên mở cùng lúc', () async {
      await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      expect(
        () => repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('save lặp không tạo bản thứ hai và chỉ một outbox op', () async {
      final saved = await recordAndSave('o');
      await repo.saveActivity(saved);
      expect(await repo.countSaved('o'), 1);
      final ops = await db.db.query('sync_outbox');
      expect(ops.length, 1);
    });

    test('save giữ nguyên track/event/segment (không cascade xóa)', () async {
      final (a, seg) = await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      await repo.insertPoints([
        for (var i = 0; i < 5; i++) TrackPoint(activityId: a.id, segmentId: seg.id, seq: i, t: i * 1000, lat: 10 + i * 0.0001, lon: 106),
      ]);
      await repo.addAttachment(activityId: a.id, ownerId: 'o', localPath: '/x.jpg', mime: 'image/jpeg', bytes: 10);
      await repo.saveActivity(a.copyWith(distanceM: 50));
      expect((await repo.points(a.id)).length, 5);
      expect((await repo.events(a.id)).length, 1);
      expect((await repo.segments(a.id)).length, 1);
      expect((await repo.attachments(a.id)).length, 1);
    });

    test('bản nháp không nằm trong list/totals', () async {
      await recordAndSave('o');
      await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      final list = await repo.list(const ActivityQuery(ownerId: 'o'));
      final totals = await repo.totals(const ActivityQuery(ownerId: 'o'));
      expect(list.length, 1);
      expect(totals.count, 1);
      expect(totals.distanceM, 5200);
    });

    test('owner khác không đọc được hoạt động', () async {
      final a = await recordAndSave('userA');
      expect(await repo.byId('userB', a.id), isNull);
      expect(await repo.list(const ActivityQuery(ownerId: 'userB')), isEmpty);
      await repo.deleteActivity('userB', a.id);
      expect(await repo.byId('userA', a.id), isNotNull);
    });

    test('delete tạo tombstone, ẩn khỏi list, outbox delete', () async {
      final a = await recordAndSave('o');
      await repo.deleteActivity('o', a.id);
      expect(await repo.byId('o', a.id), isNull);
      final ops = await db.db.query('sync_outbox');
      expect(ops.single['op'], 'delete');
    });

    test('dữ liệu còn sau khi mở lại DB file', () async {
      final path = '${await databaseFactoryFfi.getDatabasesPath()}/persist_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      final db1 = await AppDatabase.open(name: 'persist_test.db', factory: databaseFactoryFfi);
      final r1 = ActivityRepository(db1, clock);
      final (a, _) = await r1.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      await r1.saveActivity(a.copyWith(distanceM: 1000));
      await db1.close();
      final db2 = await AppDatabase.open(name: 'persist_test.db', factory: databaseFactoryFfi);
      expect(await ActivityRepository(db2, clock).countSaved('o'), 1);
      await db2.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('phiên đang ghi khi app chết → recoveryNeeded', () async {
      await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      final r = await repo.detectUnclosedSession('o');
      expect(r!.status, ActivityStatus.recoveryNeeded);
    });

    test('resume mở segment mới', () async {
      final (a, seg0) = await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
      await repo.appendEvent(activityId: a.id, type: SessionEventType.pause, monoMs: 1000, newStatus: ActivityStatus.paused);
      await repo.appendEvent(
        activityId: a.id,
        type: SessionEventType.resume,
        monoMs: 5000,
        newStatus: ActivityStatus.recording,
        openSegment: SegmentReason.resume,
      );
      final segs = await repo.segments(a.id);
      expect(segs.length, 2);
      expect(segs.first.id, seg0.id);
      expect(segs.first.endedAt, isNotNull);
      expect(segs.last.reason, SegmentReason.resume);
    });

    test('chuyển dữ liệu khách idempotent', () async {
      await recordAndSave('guest:1');
      expect(await repo.transferOwnership(fromOwner: 'guest:1', toOwner: 'user:1'), 1);
      expect(await repo.transferOwnership(fromOwner: 'guest:1', toOwner: 'user:1'), 0);
      expect(await repo.countSaved('user:1'), 1);
      expect(await repo.countSaved('guest:1'), 0);
    });

    test('chuyển dữ liệu khách mang theo outbox, không để kẹt dưới owner khách', () async {
      await recordAndSave('guest:2');
      await repo.transferOwnership(fromOwner: 'guest:2', toOwner: 'user:2');
      final ops = await db.db.query('sync_outbox');
      expect(ops.length, 1);
      expect(ops.single['owner_id'], 'user:2');
    });

    test('keyset pagination ổn định khi trùng startedAt', () async {
      for (var i = 0; i < 5; i++) {
        final (a, _) = await repo.createSession(ownerId: 'o', type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
        await repo.saveActivity(a);
      }
      final p1 = await repo.list(const ActivityQuery(ownerId: 'o', limit: 2));
      final p2 = await repo.list(ActivityQuery(ownerId: 'o', limit: 2, beforeStartedAt: p1.last.startedAt, beforeId: p1.last.id));
      final p3 = await repo.list(ActivityQuery(ownerId: 'o', limit: 2, beforeStartedAt: p2.last.startedAt, beforeId: p2.last.id));
      final ids = [...p1, ...p2, ...p3].map((a) => a.id).toList();
      expect(ids.toSet().length, 5);
    });
  });

  group('SettingsRepository', () {
    test('mục tiêu mới không viết lại ngày cũ', () async {
      final s = SettingsRepository(db, clock);
      await s.setGoal('o', GoalType.dailySteps, 8000, effectiveFrom: '2026-10-01');
      await s.setGoal('o', GoalType.dailySteps, 10000);
      expect((await s.goalFor('o', GoalType.dailySteps, '2026-10-16'))!.value, 8000);
      expect((await s.goalFor('o', GoalType.dailySteps, '2026-10-17'))!.value, 10000);
    });

    test('settings mặc định không tự điền cân nặng', () async {
      final s = SettingsRepository(db, clock);
      final loaded = await s.load('o');
      expect(loaded.weightKg, isNull);
      expect(loaded.heightCm, isNull);
      await s.save(loaded.copyWith(distanceUnit: DistanceUnit.mi));
      expect((await s.load('o')).distanceUnit, DistanceUnit.mi);
    });
  });

  group('StepRepository (F01)', () {
    test('lần đọc counter đầu tiên không thành bước hôm nay; reboot reset baseline', () async {
      final steps = StepRepository(db, clock);
      final t0 = clock.nowMs();
      expect(await steps.ingestCounter(ownerId: 'o', counter: 52000, atMs: t0), isNull);
      expect(await steps.ingestCounter(ownerId: 'o', counter: 52300, atMs: t0 + 600000), 300);
      expect(await steps.ingestCounter(ownerId: 'o', counter: 10, atMs: t0 + 1200000), isNull); // reboot
      expect(await steps.ingestCounter(ownerId: 'o', counter: 60, atMs: t0 + 1800000), 50);
      final day = await steps.day('o', clock.nowLocal(), hasPermission: true);
      expect(day.status, StepDayStatus.populated);
      expect(day.steps, 350);
    });

    test('có quyền + đã có baseline hôm nay nhưng không bước → 0 thật', () async {
      final steps = StepRepository(db, clock);
      await steps.ingestCounter(ownerId: 'o', counter: 100, atMs: clock.nowMs());
      final day = await steps.day('o', clock.nowLocal(), hasPermission: true);
      expect(day.status, StepDayStatus.verifiedZero);
    });
  });
}
