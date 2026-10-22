import '../../models/data_models/activity.dart';
import 'geo.dart';

/// Khoảng đang ghi (moving interval) theo đồng hồ đơn điệu, tính từ chuỗi SessionEvent.
class MovingInterval {
  const MovingInterval(this.startMono, this.endMono, this.startT);
  final int startMono;

  /// null khi đang mở (đang ghi).
  final int? endMono;

  /// UTC ms tương ứng startMono (để map với timestamp điểm GPS).
  final int startT;
}

const _openers = {SessionEventType.start, SessionEventType.resume, SessionEventType.autoResume, SessionEventType.recovered};
const _closers = {SessionEventType.pause, SessionEventType.autoPause, SessionEventType.finish, SessionEventType.discard};

/// Dựng các khoảng đang ghi từ event (đã sort theo seq). Pause không cộng thời gian (G06).
List<MovingInterval> movingIntervals(List<SessionEvent> events) {
  final out = <MovingInterval>[];
  int? openMono;
  int? openT;
  int? lastMono;
  for (final e in events) {
    // Khôi phục sau sự cố: khoảng còn mở bị đóng tại checkpoint cuối (data.closeAtMono) hoặc event trước đó,
    // để thời gian app bị dừng không tính là moving time (G08).
    if (e.type == SessionEventType.recovered && openMono != null) {
      final closeAt = (e.data?['closeAtMono'] as num?)?.toInt() ?? lastMono ?? openMono;
      out.add(MovingInterval(openMono, closeAt < openMono ? openMono : closeAt, openT!));
      openMono = null;
      openT = null;
    }
    lastMono = e.monoMs;
    if (_openers.contains(e.type)) {
      if (openMono == null) {
        openMono = e.monoMs;
        openT = e.t;
      }
    } else if (_closers.contains(e.type)) {
      if (openMono != null) {
        out.add(MovingInterval(openMono, e.monoMs, openT!));
        openMono = null;
        openT = null;
      }
    }
  }
  if (openMono != null) out.add(MovingInterval(openMono, null, openT!));
  return out;
}

/// Moving time (ms). [nowMono] dùng cho khoảng còn mở.
int movingMsOf(List<SessionEvent> events, {int? nowMono}) {
  var total = 0;
  for (final i in movingIntervals(events)) {
    final end = i.endMono ?? nowMono ?? i.startMono;
    if (end > i.startMono) total += end - i.startMono;
  }
  return total;
}

/// Pace trung bình (giây/km) = moving time / distance. null nếu distance < 10 m → hiển thị "—".
double? avgPaceSecPerKm({required int movingMs, required double? distanceM}) {
  if (distanceM == null || distanceM < 10 || movingMs <= 0) return null;
  final pace = (movingMs / 1000) / (distanceM / 1000);
  if (pace.isNaN || pace.isInfinite) return null;
  return pace;
}

/// Pace hiện tại trên cửa sổ gần nhất (mặc định 30 s) của điểm accepted cùng segment.
double? currentPaceSecPerKm(List<TrackPoint> recentAccepted, {int windowMs = 30000}) {
  if (recentAccepted.length < 2) return null;
  final last = recentAccepted.last;
  var dist = 0.0;
  var startT = last.t;
  for (var i = recentAccepted.length - 1; i > 0; i--) {
    final a = recentAccepted[i - 1];
    final b = recentAccepted[i];
    if (a.segmentId != b.segmentId) break;
    if (last.t - a.t > windowMs) break;
    dist += haversineM(a.lat, a.lon, b.lat, b.lon);
    startT = a.t;
  }
  final dt = last.t - startT;
  if (dist < 15 || dt <= 0) return null;
  return (dt / 1000) / (dist / 1000);
}

/// Tính split mỗi [splitM] mét bằng nội suy tuyến tính trong đoạn hợp lệ (G04).
/// Thời gian dùng timestamp điểm nhưng chỉ cộng phần nằm trong cùng segment (pause/gap đã tách segment),
/// nên tổng movingMs các split ≈ moving time thực của phần có GPS.
List<Split> computeSplits(List<TrackPoint> points, {double splitM = 1000}) {
  final splits = <Split>[];
  var accDist = 0.0;
  var accMs = 0.0;
  TrackPoint? prev;
  for (final p in points) {
    if (!p.accepted) continue;
    if (prev == null || prev.segmentId != p.segmentId) {
      prev = p;
      continue;
    }
    var segD = haversineM(prev.lat, prev.lon, p.lat, p.lon);
    var segMs = (p.t - prev.t).toDouble();
    while (accDist + segD >= splitM && segD > 0) {
      final need = splitM - accDist;
      final frac = need / segD;
      final ms = segMs * frac;
      splits.add(Split(index: splits.length, distanceM: splitM, movingMs: (accMs + ms).round()));
      segD -= need;
      segMs -= ms;
      accDist = 0;
      accMs = 0;
    }
    accDist += segD;
    accMs += segMs;
    prev = p;
  }
  if (accDist >= 1) {
    splits.add(Split(index: splits.length, distanceM: accDist, movingMs: accMs.round()));
  }
  return splits;
}

/// Thời gian nhanh nhất (ms) để phủ đúng [targetM] mét liên tục trong cùng một segment, hoặc null.
/// Dùng cho record 1 km / 5 km — không bao giờ công nhận khi tổng < targetM (I05).
int? fastestEffortMs(List<TrackPoint> points, double targetM) {
  int? best;
  final segments = <List<TrackPoint>>[];
  String? cur;
  for (final p in points) {
    if (!p.accepted) continue;
    if (p.segmentId != cur) {
      segments.add([]);
      cur = p.segmentId;
    }
    segments.last.add(p);
  }
  for (final seg in segments) {
    if (seg.length < 2) continue;
    final cum = List<double>.filled(seg.length, 0);
    for (var i = 1; i < seg.length; i++) {
      cum[i] = cum[i - 1] + haversineM(seg[i - 1].lat, seg[i - 1].lon, seg[i].lat, seg[i].lon);
    }
    if (cum.last < targetM) continue;
    var j = 0;
    for (var i = 0; i < seg.length; i++) {
      while (j < seg.length && cum[j] - cum[i] < targetM) {
        j++;
      }
      if (j >= seg.length) break;
      // Nội suy thời điểm đạt đúng targetM giữa j-1 và j.
      final over = cum[j] - cum[i] - targetM;
      final segLen = cum[j] - cum[j - 1];
      final frac = segLen <= 0 ? 0.0 : 1 - over / segLen;
      final tAt = seg[j - 1].t + (seg[j].t - seg[j - 1].t) * frac;
      final ms = (tAt - seg[i].t).round();
      if (best == null || ms < best) best = ms;
    }
  }
  return best;
}
