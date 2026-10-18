import '../models/activity.dart';
import 'geo.dart';

/// Cấu hình lọc điểm GPS (G03). Ngưỡng cần hiệu chỉnh thực địa (Full_luong §18).
class GpsFilterConfig {
  const GpsFilterConfig({this.maxAccuracyM = 30, this.maxSpeedMps = 12, this.maxJumpM = 100, this.jumpWindowMs = 3000, this.gapMs = 20000});

  /// Cấu hình cho đi bộ: tốc độ tối đa thấp hơn.
  const GpsFilterConfig.walk() : this(maxSpeedMps: 4);

  final double maxAccuracyM;
  final double maxSpeedMps;
  final double maxJumpM;
  final int jumpWindowMs;

  /// Khoảng không có điểm hợp lệ lâu hơn ngưỡng này → segment mới (không nối tuyến qua gap).
  final int gapMs;

  static GpsFilterConfig forType(ActivityType type) => type == ActivityType.walk ? const GpsFilterConfig.walk() : const GpsFilterConfig();
}

class FilterDecision {
  const FilterDecision.accept() : accepted = true, reason = null;
  const FilterDecision.reject(this.reason) : accepted = false;

  final bool accepted;
  final String? reason;
}

/// Quyết định nhận/loại một điểm mới so với điểm hợp lệ trước đó trong cùng segment.
FilterDecision evaluatePoint({required TrackPoint candidate, TrackPoint? lastAccepted, GpsFilterConfig config = const GpsFilterConfig()}) {
  final acc = candidate.accuracyM;
  if (acc != null && acc > config.maxAccuracyM) return const FilterDecision.reject('accuracy');
  if (lastAccepted == null) return const FilterDecision.accept();
  final dt = candidate.t - lastAccepted.t;
  if (dt <= 0) return const FilterDecision.reject('time');
  final d = haversineM(lastAccepted.lat, lastAccepted.lon, candidate.lat, candidate.lon);
  if (d / (dt / 1000) > config.maxSpeedMps) return const FilterDecision.reject('speed');
  if (dt < config.jumpWindowMs && d > config.maxJumpM) return const FilterDecision.reject('jump');
  return const FilterDecision.accept();
}

/// Tổng quãng đường (mét) chỉ từ điểm accepted, cộng trong từng segment — không nối giữa các segment.
double distanceOfPoints(Iterable<TrackPoint> points) {
  var total = 0.0;
  TrackPoint? prev;
  for (final p in points) {
    if (!p.accepted) continue;
    if (prev != null && prev.segmentId == p.segmentId) {
      total += haversineM(prev.lat, prev.lon, p.lat, p.lon);
    }
    prev = p;
  }
  return total;
}

/// Nhóm điểm accepted theo segment để vẽ polyline tách rời.
List<List<TrackPoint>> polylinesBySegment(Iterable<TrackPoint> points) {
  final result = <List<TrackPoint>>[];
  String? current;
  for (final p in points) {
    if (!p.accepted) continue;
    if (p.segmentId != current) {
      result.add(<TrackPoint>[]);
      current = p.segmentId;
    }
    result.last.add(p);
  }
  return result;
}
