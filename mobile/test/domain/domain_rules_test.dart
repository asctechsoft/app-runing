import 'package:flutter_test/flutter_test.dart';
import 'package:stride/core/format/formatters.dart';
import 'package:stride/core/logging/logger.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/domain/calc/calories.dart';
import 'package:stride/domain/calc/records.dart';
import 'package:stride/domain/calc/step_aggregate.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/domain/models/profile.dart';
import 'package:stride/domain/models/steps.dart';
import 'package:stride/domain/session/session_state.dart';

void main() {
  group('session state machine (C05)', () {
    test('luồng chuẩn', () {
      var s = SessionPhase.idle;
      for (final a in [SessionAction.open, SessionAction.start, SessionAction.countdownDone, SessionAction.pause, SessionAction.resume, SessionAction.pause, SessionAction.finish, SessionAction.save]) {
        s = transition(s, a);
      }
      expect(s, SessionPhase.saved);
    });

    test('Start lặp khi đang countdown bị từ chối', () {
      final s = transition(transition(SessionPhase.idle, SessionAction.open), SessionAction.start);
      expect(() => transition(s, SessionAction.start), throwsA(isA<InvalidTransition>()));
    });

    test('không finish trực tiếp khi đang ghi (phải pause trước)', () {
      expect(canTransition(SessionPhase.recording, SessionAction.finish), isFalse);
    });

    test('cancel countdown về prepare', () {
      expect(transition(SessionPhase.countdown, SessionAction.cancel), SessionPhase.preparing);
    });

    test('đã lưu không tiếp tục phiên cũ', () {
      expect(canTransition(SessionPhase.saved, SessionAction.resume), isFalse);
    });
  });

  group('format (DS mục 02)', () {
    const km = StrideFormat();
    const mi = StrideFormat(distanceUnit: DistanceUnit.mi);

    test('distance theo đơn vị, dữ liệu gốc mét', () {
      expect(km.distance(5200), '5.20 km');
      expect(mi.distance(5200), '3.23 mi');
      expect(km.distance(null), missingValue);
    });

    test('pace', () {
      expect(km.pace(372), '6:12 /km');
      expect(mi.pace(372), '9:59 /mi');
      expect(km.pace(null), missingValue);
      expect(km.pace(double.nan), missingValue);
      expect(km.pace(double.infinity), missingValue);
    });

    test('duration', () {
      expect(formatDuration(32 * 60000 + 14000), '32:14');
      expect(formatDuration(3600000 + 24 * 60000 + 12000), '1:24:12');
      expect(formatDuration(0), '00:00');
    });

    test('steps có dấu nhóm số', () {
      expect(km.steps(6250), '6,250');
      expect(km.steps(null), missingValue);
    });
  });

  group('calories & step distance', () {
    test('không có cân nặng → null (không dùng cân nặng mẫu)', () {
      expect(estimateCalories(type: ActivityType.run, weightKg: null, movingMs: 1800000, distanceM: 5000), isNull);
    });

    test('có cân nặng → số dương', () {
      final k = estimateCalories(type: ActivityType.run, weightKg: 68, movingMs: 1934000, distanceM: 5200)!;
      expect(k, greaterThan(200));
      expect(k, lessThan(600));
    });

    test('không có chiều cao → không đoán quãng đường từ bước', () {
      expect(stepDistanceM(steps: 8000, heightCm: null), isNull);
      expect(stepDistanceM(steps: 1000, heightCm: 172), closeTo(713.8, 0.1));
    });
  });

  group('goal version (F06)', () {
    final versions = [
      const GoalVersion(id: '1', ownerId: 'o', type: GoalType.dailySteps, value: 8000, effectiveFrom: '2026-10-01', createdAt: 1),
      const GoalVersion(id: '2', ownerId: 'o', type: GoalType.dailySteps, value: 10000, effectiveFrom: '2026-10-15', createdAt: 2),
    ];

    test('ngày cũ giữ mục tiêu cũ', () {
      expect(goalForDate(versions, GoalType.dailySteps, '2026-10-14')!.value, 8000);
      expect(goalForDate(versions, GoalType.dailySteps, '2026-10-15')!.value, 10000);
      expect(goalForDate(versions, GoalType.dailySteps, '2026-09-30'), isNull);
    });
  });

  group('steps aggregation (F02, F03)', () {
    StepSample s(StepSource src, DateTime start, DateTime end, int steps) => StepSample(
      id: '$src${start.millisecondsSinceEpoch}',
      ownerId: 'o',
      source: src,
      startAt: start.toUtc().millisecondsSinceEpoch,
      endAt: end.toUtc().millisecondsSinceEpoch,
      steps: steps,
      tzId: 'UTC',
    );

    test('không quyền và không mẫu → noPermission, không 0', () {
      final d = aggregateDay(dateKey: '2026-10-17', samples: const [], offsetMin: 0, hasPermission: false);
      expect(d.status, StepDayStatus.noPermission);
      expect(d.steps, isNull);
    });

    test('có quyền, chưa có mẫu → noData', () {
      final d = aggregateDay(dateKey: '2026-10-17', samples: const [], offsetMin: 0, hasPermission: true);
      expect(d.status, StepDayStatus.noData);
      expect(d.steps, isNull);
    });

    test('nguồn xác nhận 0 → verifiedZero', () {
      final d = aggregateDay(dateKey: '2026-10-17', samples: const [], offsetMin: 0, hasPermission: true, sourceConfirmedZero: true);
      expect(d.status, StepDayStatus.verifiedZero);
      expect(d.steps, 0);
    });

    test('hai nguồn chồng khoảng không cộng cả hai', () {
      final day = DateTime.utc(2026, 10, 17, 8);
      final d = aggregateDay(
        dateKey: '2026-10-17',
        samples: [
          s(StepSource.phoneSensor, day, day.add(const Duration(hours: 1)), 1000),
          s(StepSource.healthConnect, day, day.add(const Duration(hours: 1)), 1100),
        ],
        offsetMin: 0,
        hasPermission: true,
      );
      expect(d.steps, 1100); // healthConnect ưu tiên hơn phone
      expect(d.sourceUsed, StepSource.healthConnect);
    });

    test('mẫu qua nửa đêm chia theo ngày, tổng giờ khớp ngày', () {
      final start = DateTime.utc(2026, 10, 17, 23, 30);
      final sample = s(StepSource.phoneSensor, start, start.add(const Duration(hours: 1)), 600);
      final d17 = aggregateDay(dateKey: '2026-10-17', samples: [sample], offsetMin: 0, hasPermission: true);
      final d18 = aggregateDay(dateKey: '2026-10-18', samples: [sample], offsetMin: 0, hasPermission: true);
      expect(d17.steps, 300);
      expect(d18.steps, 300);
      expect(d17.hourly![23], 300);
      expect(d17.hourly!.whereType<int>().fold<int>(0, (a, b) => a + b), d17.steps);
    });

    test('múi giờ +7 dời giờ địa phương', () {
      final start = DateTime.utc(2026, 10, 17, 1); // 08:00 giờ +7
      final d = aggregateDay(dateKey: '2026-10-17', samples: [s(StepSource.phoneSensor, start, start.add(const Duration(minutes: 30)), 500)], offsetMin: 420, hasPermission: true);
      expect(d.hourly![8], 500);
    });

    test('counter reboot không cộng tổng từ boot', () {
      expect(counterDelta(lastCounter: null, current: 52000), isNull);
      expect(counterDelta(lastCounter: 52000, current: 52100), 100);
      expect(counterDelta(lastCounter: 52100, current: 40), isNull);
    });
  });

  group('records (I05)', () {
    Activity run(String id, double d, int ms, {bool gps = true, ActivityType type = ActivityType.run, int? deletedAt}) => Activity(
      id: id,
      ownerId: 'o',
      type: type,
      status: ActivityStatus.saved,
      startedAt: 1,
      tzId: 'UTC',
      tzOffsetMin: 0,
      distanceM: d,
      movingMs: ms,
      hasGps: gps,
      deletedAt: deletedAt,
    );

    test('chỉ dùng hoạt động eligible; 5 km cần ≥ 5000 m', () {
      final recs = computeRecords(
        [run('a', 4900, 1700000), run('b', 12400, 5000000), run('c', 20000, 1, gps: false), run('d', 30000, 1, deletedAt: 5), run('w', 15000, 9000000, type: ActivityType.walk)],
        {
          'a': {1000: 300000, 5000: 1500000},
          'b': {1000: 320000, 5000: 1726000},
        },
      );
      final byKind = {for (final r in recs) r.kind: r};
      expect(byKind[RecordKind.longestRun]!.activityId, 'b');
      expect(byKind[RecordKind.fastest5k]!.activityId, 'b'); // 'a' chỉ 4.9 km
      expect(byKind[RecordKind.fastest1k]!.activityId, 'a');
    });
  });

  group('logger redaction (B04)', () {
    test('che token và tọa độ', () {
      final out = StrideLog.redact('Authorization: Bearer abc.def.ghi {"lat": 10.12345, "lon": 106.6789} password=secret 10.123456, 106.654321');
      expect(out, isNot(contains('abc.def.ghi')));
      expect(out, isNot(contains('10.12345')));
      expect(out, isNot(contains('secret')));
      expect(out, isNot(contains('106.654321')));
    });
  });

  group('clock (C04)', () {
    test('đổi giờ hệ thống không ảnh hưởng đồng hồ đơn điệu', () {
      final c = FakeClock();
      final m0 = c.monoMs();
      c.jumpWallClock(const Duration(hours: -1));
      c.advance(const Duration(seconds: 10));
      expect(c.monoMs() - m0, 10000);
    });

    test('đầu tuần theo cài đặt', () {
      final fri = DateTime(2026, 10, 16);
      expect(startOfWeek(fri, DateTime.monday), DateTime(2026, 10, 12));
      expect(startOfWeek(fri, DateTime.sunday), DateTime(2026, 10, 11));
    });
  });
}
