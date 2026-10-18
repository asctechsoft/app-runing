import 'package:flutter_test/flutter_test.dart';
import 'package:stride/domain/calc/geo.dart';
import 'package:stride/domain/calc/gps_filter.dart';
import 'package:stride/domain/calc/run_metrics.dart';
import 'package:stride/domain/models/activity.dart';

/// Fixture: đi thẳng hướng bắc với tốc độ đều, mỗi 5 s một điểm.
List<TrackPoint> straightRun({
  required double meters,
  double speedMps = 3.0,
  int intervalMs = 5000,
  String segment = 's0',
  int t0 = 0,
  int seq0 = 0,
  double lat0 = 10.0,
  double lon0 = 106.0,
}) {
  final pts = <TrackPoint>[];
  final stepM = speedMps * intervalMs / 1000;
  final n = (meters / stepM).ceil();
  for (var i = 0; i <= n; i++) {
    final d = (i * stepM).clamp(0, meters).toDouble();
    final (lat, lon) = offsetPoint(lat0, lon0, d, 0);
    pts.add(TrackPoint(activityId: 'a', segmentId: segment, seq: seq0 + i, t: t0 + (d / speedMps * 1000).round(), lat: lat, lon: lon, accuracyM: 5));
  }
  return pts;
}

SessionEvent ev(int seq, SessionEventType type, int mono) => SessionEvent(id: '$seq', activityId: 'a', seq: seq, type: type, t: mono, monoMs: mono);

void main() {
  group('moving time', () {
    test('pause không cộng vào moving time', () {
      final events = [
        ev(0, SessionEventType.start, 0),
        ev(1, SessionEventType.pause, 60000),
        ev(2, SessionEventType.resume, 180000), // tạm dừng 2 phút
        ev(3, SessionEventType.finish, 240000),
      ];
      expect(movingMsOf(events), 120000);
    });

    test('khoảng đang mở dùng nowMono', () {
      final events = [ev(0, SessionEventType.start, 1000)];
      expect(movingMsOf(events, nowMono: 31000), 30000);
    });

    test('app chết khi đang ghi: thời gian chết không tính (G08)', () {
      final events = [
        ev(0, SessionEventType.start, 0),
        ev(1, SessionEventType.autoPause, 10000),
        ev(2, SessionEventType.autoResume, 15000),
        // app chết sau checkpoint cuối ở 20000; mở lại ở 500000 → khôi phục thành đoạn mới
        SessionEvent(id: 'r', activityId: 'a', seq: 3, type: SessionEventType.recovered, t: 500000, monoMs: 500000, data: const {'closeAtMono': 20000}),
        ev(4, SessionEventType.pause, 510000),
      ];
      expect(movingMsOf(events), 10000 + 5000 + 10000);
    });

    test('recovered không có checkpoint: đóng tại event trước, không cộng thời gian chết', () {
      final events = [ev(0, SessionEventType.start, 0), ev(1, SessionEventType.recovered, 900000), ev(2, SessionEventType.pause, 960000)];
      expect(movingMsOf(events), 60000);
    });
  });

  group('pace', () {
    test('distance 0 hoặc rất nhỏ → null, không NaN/vô cực', () {
      expect(avgPaceSecPerKm(movingMs: 60000, distanceM: 0), isNull);
      expect(avgPaceSecPerKm(movingMs: 60000, distanceM: null), isNull);
      expect(avgPaceSecPerKm(movingMs: 0, distanceM: 1000), isNull);
    });

    test('pace = moving time / distance', () {
      expect(avgPaceSecPerKm(movingMs: 372000, distanceM: 1000), closeTo(372, 0.001));
    });
  });

  group('gps', () {
    test('điểm nhảy xa bị loại, km không tăng đột biến', () {
      final pts = straightRun(meters: 300);
      final jump = TrackPoint(activityId: 'a', segmentId: 's0', seq: 999, t: pts.last.t + 1000, lat: pts.last.lat + 0.01, lon: pts.last.lon, accuracyM: 5);
      final d = evaluatePoint(candidate: jump, lastAccepted: pts.last);
      expect(d.accepted, isFalse);
      expect(d.reason, anyOf('speed', 'jump'));
    });

    test('accuracy kém bị loại', () {
      final p = TrackPoint(activityId: 'a', segmentId: 's0', seq: 0, t: 0, lat: 10, lon: 106, accuracyM: 80);
      expect(evaluatePoint(candidate: p).accepted, isFalse);
    });

    test('không nối quãng đường qua hai segment', () {
      final a = straightRun(meters: 500, segment: 's0');
      // segment thứ hai bắt đầu cách 2 km (vd. mất GPS) — khoảng trống không được cộng
      final (lat2, lon2) = offsetPoint(10.0, 106.0, 2500, 0);
      final b = straightRun(meters: 500, segment: 's1', t0: a.last.t + 600000, seq0: 1000, lat0: lat2, lon0: lon2);
      final total = distanceOfPoints([...a, ...b]);
      expect(total, closeTo(1000, 1.0));
      expect(polylinesBySegment([...a, ...b]).length, 2);
    });

    test('điểm rejected không tính', () {
      final a = straightRun(meters: 200);
      final mid = a[5].copyWith(accepted: false);
      final pts = [...a]..[5] = mid;
      expect(distanceOfPoints(pts), closeTo(200, 1.0));
    });
  });

  group('splits', () {
    test('split đầy đủ 1000 m và split cuối là độ dài lẻ thật', () {
      final pts = straightRun(meters: 2500, speedMps: 2.5);
      final splits = computeSplits(pts);
      expect(splits.length, 3);
      expect(splits[0].distanceM, 1000);
      expect(splits[1].distanceM, 1000);
      expect(splits[2].distanceM, closeTo(500, 1.0));
      // 2.5 m/s → 400 s mỗi km
      expect(splits[0].movingMs, closeTo(400000, 600));
      final sum = splits.fold<int>(0, (a, s) => a + s.movingMs);
      expect(sum, closeTo(pts.last.t - pts.first.t, 5));
    });

    test('không có điểm → không có split', () {
      expect(computeSplits(const []), isEmpty);
    });
  });

  group('best effort', () {
    test('4.9 km không được tính 5 km', () {
      final pts = straightRun(meters: 4900);
      expect(fastestEffortMs(pts, 5000), isNull);
      expect(fastestEffortMs(pts, 1000), isNotNull);
    });

    test('không ghép effort qua gap giữa segment', () {
      final a = straightRun(meters: 3000, segment: 's0');
      final (lat2, lon2) = offsetPoint(10.0, 106.0, 3000, 0);
      final b = straightRun(meters: 3000, segment: 's1', t0: a.last.t + 1000, seq0: 1000, lat0: lat2, lon0: lon2);
      expect(fastestEffortMs([...a, ...b], 5000), isNull);
    });

    test('effort 1 km ở tốc độ đều', () {
      final pts = straightRun(meters: 3000, speedMps: 4);
      expect(fastestEffortMs(pts, 1000), closeTo(250000, 1500));
    });
  });
}
