import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/models/ui_models/workout_models.dart';
import 'package:stride/repository/workout_repository.dart';

void main() {
  group('Tổng thời gian giáo án (K01)', () {
    test('5 min + 6 × (2 min run + 1 min walk) + 5 min = 28 min chính xác', () {
      final plan = WorkoutPlan.starter();
      expect(plan.totalMs, 28 * 60000);
      expect(plan.phases.length, 1 + 12 + 1);
      expect(plan.intervalCount, 6);
    });

    test('bỏ qua bước thời lượng 0; repeat 1 lần', () {
      final steps = [
        IntervalStep(kind: IntervalKind.warmup, durationMs: 0),
        IntervalStep(
          kind: IntervalKind.repeat,
          repeat: 1,
          children: [IntervalStep(kind: IntervalKind.run, durationMs: 90000)],
        ),
      ];
      expect(planTotalMs(steps), 90000);
      expect(flattenPlan(steps).single.label, 'Run 1 of 1');
    });

    test('JSON round-trip giữ cấu trúc', () {
      final p = WorkoutPlan.decode(WorkoutPlan.starter().copyWith(audioCues: false).encode());
      expect(p.totalMs, 28 * 60000);
      expect(p.audioCues, isFalse);
      expect(p.steps[1].children.map((c) => c.kind), [IntervalKind.run, IntervalKind.walk]);
    });
  });

  group('Pha theo moving time (K02)', () {
    final phases = WorkoutPlan.starter().phases;

    test('ranh giới pha', () {
      expect(phaseAt(phases, 0).index, 0);
      expect(phaseAt(phases, 5 * 60000 - 1).index, 0);
      expect(phaseAt(phases, 5 * 60000).index, 1);
      expect(phases[1].label, 'Run 1 of 6');
      expect(phaseAt(phases, 7 * 60000).index, 2);
      expect(phases[2].kind, IntervalKind.walk);
      expect(phaseAt(phases, 7 * 60000 + 30000).remainingMs, 30000);
      expect(phaseAt(phases, 28 * 60000).index, phases.length);
    });

    test('kết quả pha: dừng sớm → incomplete, tổng actual = moving time', () {
      final r = computePhaseResults(phases, movingMs: 9 * 60000, distanceAtStart: {0: 0, 1: 800, 2: 1300, 3: 1450}, totalDistanceM: 1600);
      expect(r[0].completed, isTrue);
      expect(r[0].distanceM, 800);
      expect(r[2].distanceM, 150);
      expect(r[3].actualMs, 60000);
      expect(r[3].completed, isFalse);
      expect(r[3].distanceM, 150);
      expect(r.fold<int>(0, (s, p) => s + p.actualMs), 9 * 60000);
      expect(r.any((p) => !p.completed), isTrue);
    });

    test('thiếu mốc quãng đường của pha đã qua → null, không đoán', () {
      final r = computePhaseResults(phases, movingMs: 9 * 60000, distanceAtStart: {0: 0, 2: 1300}, totalDistanceM: 1600);
      expect(r[0].distanceM, isNull);
    });
  });

  group('WorkoutRepository', () {
    late AppDatabase db;
    late WorkoutRepository repo;
    setUp(() async {
      sqfliteFfiInit();
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      repo = WorkoutRepository(db.db, FakeClock());
    });
    tearDown(() => db.close());

    test('lưu, cập nhật và xóa preset theo owner', () async {
      final saved = await repo.savePlan('o', WorkoutPlan.starter().copyWith(name: 'Tempo'));
      expect(saved.id, isNotNull);
      await repo.savePlan('o', saved.copyWith(name: 'Tempo 2'));
      final list = await repo.listPlans('o');
      expect(list.single.name, 'Tempo 2');
      expect(list.single.totalMs, 28 * 60000);
      expect(await repo.listPlans('other'), isEmpty);
      expect(await repo.plan('other', saved.id!), isNull);
      await repo.deletePlan('o', saved.id!);
      expect(await repo.listPlans('o'), isEmpty);
    });
  });
}
