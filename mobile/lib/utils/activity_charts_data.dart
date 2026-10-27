import '../models/data_models/activity.dart';
import 'calc/geo.dart';
import 'calc/gps_filter.dart';

/// Điểm biểu đồ: x theo km (hoặc phút với nhịp tim), y theo đơn vị gốc của chuỗi.
class ChartSample {
  const ChartSample(this.x, this.y);
  final double x;
  final double y;
}

/// Kết quả chuỗi: có dữ liệu hoặc lý do không vẽ được (reason là KEY chuỗi, UI gọi `.tr`) (F15: ẩn biểu đồ không tính được và nêu nguyên nhân).
class ChartSeries {
  const ChartSeries.ok(this.samples) : reason = null;
  const ChartSeries.unavailable(this.reason) : samples = const [];

  final List<ChartSample> samples;
  final String? reason;
  bool get available => reason == null;
}

const int minPaceSamples = 5;
const int minElevationSamples = 10;
const int minHeartRateSamples = 5;

/// Pace (giây/km) theo quãng đường: cửa sổ trượt [windowM] trong cùng segment, lấy mẫu mỗi [stepM].
/// x = km tích lũy (các segment nối tiếp theo quãng đường, không nối thời gian qua pause/gap).
ChartSeries paceSeries(List<TrackPoint> points, {double windowM = 200, double stepM = 100}) {
  final out = <ChartSample>[];
  var offset = 0.0;
  for (final seg in polylinesBySegment(points)) {
    if (seg.length < 2) continue;
    final cum = List<double>.filled(seg.length, 0);
    for (var i = 1; i < seg.length; i++) {
      cum[i] = cum[i - 1] + haversineM(seg[i - 1].lat, seg[i - 1].lon, seg[i].lat, seg[i].lon);
    }
    var nextMark = windowM;
    var j = 0;
    for (var i = 1; i < seg.length; i++) {
      if (cum[i] < nextMark) continue;
      while (j < i && cum[i] - cum[j + 1] >= windowM) {
        j++;
      }
      final d = cum[i] - cum[j];
      final dt = (seg[i].t - seg[j].t) / 1000;
      if (d > 0 && dt > 0) {
        final pace = dt / (d / 1000);
        if (pace > 0 && pace < 3600) out.add(ChartSample((offset + cum[i]) / 1000, pace));
      }
      while (nextMark <= cum[i]) {
        nextMark += stepM;
      }
    }
    offset += cum.last;
  }
  if (out.length < minPaceSamples) {
    return const ChartSeries.unavailable('activity_chart_pace_insufficient');
  }
  return ChartSeries.ok(out);
}

/// Độ cao (mét) theo quãng đường; chỉ khi đa số điểm có altitude.
ChartSeries elevationSeries(List<TrackPoint> points) {
  final accepted = points.where((p) => p.accepted).toList();
  final withAlt = accepted.where((p) => p.altitudeM != null).length;
  if (withAlt < minElevationSamples || withAlt < accepted.length / 2) {
    return const ChartSeries.unavailable('activity_chart_elevation_unavailable');
  }
  final out = <ChartSample>[];
  var dist = 0.0;
  TrackPoint? prev;
  for (final p in accepted) {
    if (prev != null && prev.segmentId == p.segmentId) dist += haversineM(prev.lat, prev.lon, p.lat, p.lon);
    if (p.altitudeM != null) out.add(ChartSample(dist / 1000, p.altitudeM!));
    prev = p;
  }
  return ChartSeries.ok(out);
}

/// Nhịp tim (bpm) theo phút kể từ lúc bắt đầu; chỉ khi có heart_rate_samples thật.
ChartSeries heartRateSeries(List<(int t, int bpm)> samples, int startedAt) {
  if (samples.length < minHeartRateSamples) {
    return const ChartSeries.unavailable('activity_chart_hr_none');
  }
  return ChartSeries.ok([for (final (t, bpm) in samples) ChartSample((t - startedAt) / 60000, bpm.toDouble())]);
}
