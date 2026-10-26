import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/repository/step_repository.dart';
import 'package:stride/utils/calc/step_aggregate.dart';
import 'package:stride/models/data_models/steps.dart';
import 'package:stride/controller/profile/profile_logic.dart' show parseStepSourcePriority, encodeStepSourcePriority;
import 'package:stride/services/application/step_tracking_service.dart';
import 'package:stride/controller/steps/steps_logic.dart';

StepSample _s(int start, int end, int steps, {StepSource source = StepSource.phoneSensor}) =>
    StepSample(id: '$start-$end-${source.name}', ownerId: 'o', source: source, startAt: start, endAt: end, steps: steps, tzId: 'UTC');

void main() {
  sqfliteFfiInit();

  group('StepRepository.ingestCounter (F01)', () {
    late AppDatabase db;
    late StepRepository repo;
    final t0 = DateTime(2026, 10, 18, 8).millisecondsSinceEpoch;

    setUp(() async {
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      repo = StepRepository(db, FakeClock(t0));
    });
    tearDown(() => db.close());

    Future<int> todaySteps() async => (await repo.day('o', DateTime(2026, 10, 18), hasPermission: true)).steps ?? -1;

    test('lần đọc đầu chỉ là baseline — không cộng tổng từ lúc boot', () async {
      expect(await repo.ingestCounter(ownerId: 'o', counter: 52000, atMs: t0), isNull);
      final d = await repo.day('o', DateTime(2026, 10, 18), hasPermission: true);
      // Đã có baseline sau nửa đêm nhưng chưa có bước → 0 thật, không phải 52000.
      expect(d.status, StepDayStatus.verifiedZero);
      expect(d.steps, 0);
    });

    test('delta giữa hai lần đọc được ghi; reboot (counter giảm) không tạo bước giả', () async {
      await repo.ingestCounter(ownerId: 'o', counter: 52000, atMs: t0);
      expect(await repo.ingestCounter(ownerId: 'o', counter: 52300, atMs: t0 + 600000), 300);
      expect(await todaySteps(), 300);
      // Reboot: counter về gần 0.
      expect(await repo.ingestCounter(ownerId: 'o', counter: 40, atMs: t0 + 1200000), isNull);
      expect(await todaySteps(), 300);
      // Sau reboot, delta tính từ baseline mới.
      expect(await repo.ingestCounter(ownerId: 'o', counter: 140, atMs: t0 + 1800000), 100);
      expect(await todaySteps(), 400);
    });
  });

  group('aggregateDay qua nửa đêm và múi giờ (F03)', () {
    test('mẫu vắt qua nửa đêm chia theo tỷ lệ thời gian, tổng giờ khớp ngày', () {
      // 23:30 → 00:30 UTC, 600 bước: 300 thuộc ngày 17, 300 thuộc ngày 18.
      final start = DateTime.utc(2026, 10, 17, 23, 30).millisecondsSinceEpoch;
      final end = DateTime.utc(2026, 10, 18, 0, 30).millisecondsSinceEpoch;
      final samples = [_s(start, end, 600)];
      final d17 = aggregateDay(dateKey: '2026-10-17', samples: samples, offsetMin: 0, hasPermission: true);
      final d18 = aggregateDay(dateKey: '2026-10-18', samples: samples, offsetMin: 0, hasPermission: true);
      expect(d17.steps, 300);
      expect(d17.hourly![23], 300);
      expect(d18.steps, 300);
      expect(d18.hourly![0], 300);
      expect(d18.hourly![1], isNull, reason: 'giờ không có mẫu là null, không phải 0');
      expect(d18.hourly!.fold<int>(0, (a, v) => a + (v ?? 0)), d18.steps);
    });

    test('cùng mẫu UTC rơi vào giờ địa phương khác theo offset (+7)', () {
      final start = DateTime.utc(2026, 10, 17, 17, 0).millisecondsSinceEpoch; // 00:00 ngày 18 tại UTC+7
      final end = DateTime.utc(2026, 10, 17, 18, 0).millisecondsSinceEpoch;
      final d = aggregateDay(dateKey: '2026-10-18', samples: [_s(start, end, 1000)], offsetMin: 420, hasPermission: true);
      expect(d.hourly![0], 1000);
      final dUtc = aggregateDay(dateKey: '2026-10-18', samples: [_s(start, end, 1000)], offsetMin: 0, hasPermission: true);
      expect(dUtc.status, StepDayStatus.noData);
    });

    test('hai nguồn trùng giờ không cộng cả hai — theo thứ tự ưu tiên', () {
      final start = DateTime.utc(2026, 10, 18, 9).millisecondsSinceEpoch;
      final end = DateTime.utc(2026, 10, 18, 10).millisecondsSinceEpoch;
      final samples = [_s(start, end, 1000), _s(start, end, 1200, source: StepSource.healthConnect)];
      final d = aggregateDay(dateKey: '2026-10-18', samples: samples, offsetMin: 0, hasPermission: true, priority: parseStepSourcePriority('phoneSensor'));
      expect(d.steps, 1000);
      expect(d.sourceUsed, StepSource.phoneSensor);
    });
  });

  group('step source priority (parser dùng chung với Data sources)', () {
    test('rỗng → mặc định; bỏ nguồn lạ; nối nguồn thiếu', () {
      expect(parseStepSourcePriority(null), defaultSourcePriority);
      final p = parseStepSourcePriority('phoneSensor, bogus,phoneSensor');
      expect(p.first, StepSource.phoneSensor);
      expect(p.toSet().length, StepSource.values.length);
      expect(parseStepSourcePriority(encodeStepSourcePriority(p)), p);
    });
  });

  group('activeMinutesFromSamples', () {
    final base = DateTime(2026, 10, 18, 9).millisecondsSinceEpoch;
    final from = DateTime(2026, 10, 18).millisecondsSinceEpoch;
    final to = DateTime(2026, 10, 19).millisecondsSinceEpoch;

    test('không có mẫu ngắn → null (không đủ căn cứ)', () {
      expect(activeMinutesFromSamples([_s(base, base + 3600000, 5000)], fromMs: from, toMs: to), isNull);
      expect(activeMinutesFromSamples(const [], fromMs: from, toMs: to), isNull);
    });

    test('chỉ tính mẫu có nhịp ≥ ngưỡng', () {
      final samples = [
        _s(base, base + 120000, 220), // 110 spm, 2 phút
        _s(base + 120000, base + 420000, 30), // 6 spm, không tính
        _s(base + 420000, base + 600000, 300), // 100 spm, 3 phút
      ];
      expect(activeMinutesFromSamples(samples, fromMs: from, toMs: to), 5);
    });
  });

  test('hourEntries: giờ tương lai rỗng, giờ thiếu là null', () {
    final hourly = List<int?>.filled(24, null)
      ..[8] = 500
      ..[9] = 0
      ..[15] = 999; // giá trị lạ ở giờ tương lai bị bỏ
    final e = hourEntries(
      StepDay(date: '2026-10-18', status: StepDayStatus.populated, steps: 500, hourly: hourly),
      todayKey: '2026-10-18',
      nowHour: 10,
    );
    expect(e[8].steps, 500);
    expect(e[9].steps, 0);
    expect(e[7].steps, isNull);
    expect(e[15].future, isTrue);
    expect(e[15].steps, isNull);
  });

  group('StepTrackingService', () {
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:t'});
    });
    tearDown(() => db.close());

    Future<ProviderContainer> make(PermStatus motion, StepCounterStreamFactory f) async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.motion: motion})),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 18, 9).millisecondsSinceEpoch)),
          stepTrackingServiceProvider.overrideWith((ref) => StepTrackingService(ref, streamFactory: f)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('không có quyền → không mở sensor', () async {
      var opened = false;
      final c = await make(PermStatus.denied, () {
        opened = true;
        return const Stream.empty();
      });
      expect(await c.read(stepTrackingServiceProvider).start(), StepTrackingStatus.idle);
      expect(opened, isFalse);
    });

    test('có quyền → ingest counter qua repository', () async {
      final ctrl = StreamController<StepCounterReading>();
      final c = await make(PermStatus.granted, () => ctrl.stream);
      final svc = c.read(stepTrackingServiceProvider);
      expect(await svc.start(), StepTrackingStatus.running);
      final t = DateTime(2026, 10, 18, 9).millisecondsSinceEpoch;
      ctrl.add((counter: 1000, atMs: t));
      ctrl.add((counter: 1250, atMs: t + 60000));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final day = await c.read(stepRepositoryProvider).day('guest:t', DateTime(2026, 10, 18), hasPermission: true);
      expect(day.steps, 250);
      await svc.stop();
      await ctrl.close();
    });

    test('sensor lỗi → unavailable', () async {
      final c = await make(PermStatus.granted, () => Stream.error(StateError('no sensor')));
      final svc = c.read(stepTrackingServiceProvider);
      await svc.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(svc.status.value, StepTrackingStatus.unavailable);
    });
  });
}
