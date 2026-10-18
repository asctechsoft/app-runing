import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/calc/geo.dart';
import '../../domain/calc/gps_filter.dart';
import '../../domain/models/activity.dart';

/// Toạ độ thuần (không phụ thuộc thư viện bản đồ) để cắt/vẽ tuyến.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// Tuyến = danh sách đoạn (segment) tách rời; không nối qua pause/gap.
typedef RouteLines = List<List<GeoPoint>>;

/// Dựng tuyến từ điểm accepted, mỗi segment một polyline.
RouteLines routeFromPoints(List<TrackPoint> points) => [
  for (final seg in polylinesBySegment(points))
    if (seg.isNotEmpty) [for (final p in seg) GeoPoint(p.lat, p.lon)],
];

double _dist(GeoPoint a, GeoPoint b) => haversineM(a.lat, a.lon, b.lat, b.lon);

/// Tổng chiều dài tuyến (mét), cộng trong từng đoạn.
double routeLengthM(RouteLines route) {
  var total = 0.0;
  for (final seg in route) {
    for (var i = 1; i < seg.length; i++) {
      total += _dist(seg[i - 1], seg[i]);
    }
  }
  return total;
}

GeoPoint _lerp(GeoPoint a, GeoPoint b, double t) => GeoPoint(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);

/// Chèn điểm nội suy để hai điểm liên tiếp cách nhau ≤ [maxStepM]: tránh một cạnh dài "xuyên" qua vùng ẩn.
List<GeoPoint> _densify(List<GeoPoint> seg, double maxStepM) {
  if (seg.length < 2) return [...seg];
  final out = <GeoPoint>[seg.first];
  for (var i = 1; i < seg.length; i++) {
    final a = seg[i - 1];
    final b = seg[i];
    final d = _dist(a, b);
    final n = (d / maxStepM).ceil();
    for (var k = 1; k < n; k++) {
      out.add(_lerp(a, b, k / n));
    }
    out.add(b);
  }
  return out;
}

/// Điểm ranh giới trên cạnh [visible]→[hidden]: điểm xa nhất về phía [hidden] mà vẫn nằm ngoài vùng ẩn.
GeoPoint _boundary(GeoPoint visible, GeoPoint hidden, bool Function(GeoPoint) isHidden) {
  var lo = 0.0; // luôn visible
  var hi = 1.0; // luôn hidden
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (isHidden(_lerp(visible, hidden, mid))) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return _lerp(visible, hidden, lo);
}

/// Ẩn vị trí đầu/cuối (I06, F17): trả **bản sao** tuyến đã bỏ mọi điểm nằm trong bán kính [radiusM]
/// quanh điểm bắt đầu và điểm kết thúc. Tuyến gốc không bị sửa. Đoạn còn < 2 điểm bị bỏ.
/// Vì khoảng cách đường chim bay ≤ quãng đường đi, ít nhất [radiusM] mét đầu và cuối luôn bị cắt.
RouteLines clipRouteEnds(RouteLines route, double radiusM) {
  final nonEmpty = [
    for (final s in route)
      if (s.isNotEmpty) s,
  ];
  if (nonEmpty.isEmpty) return [];
  if (radiusM <= 0) {
    return [
      for (final s in nonEmpty)
        if (s.length >= 2) [...s],
    ];
  }
  final start = nonEmpty.first.first;
  final end = nonEmpty.last.last;
  bool isHidden(GeoPoint p) => _dist(p, start) <= radiusM || _dist(p, end) <= radiusM;

  final out = <List<GeoPoint>>[];
  for (final raw in nonEmpty) {
    final seg = _densify(raw, math.max(1.0, radiusM / 4));
    var cur = <GeoPoint>[];
    void flush() {
      if (cur.length >= 2) out.add(cur);
      cur = <GeoPoint>[];
    }

    for (var i = 0; i < seg.length; i++) {
      final p = seg[i];
      final h = isHidden(p);
      if (i > 0) {
        final prev = seg[i - 1];
        final ph = isHidden(prev);
        if (ph && !h) {
          cur.add(_boundary(p, prev, isHidden));
        } else if (!ph && h) {
          cur.add(_boundary(prev, p, isHidden));
          flush();
        }
      }
      if (!h) cur.add(p);
    }
    flush();
  }
  return out;
}

/// Phép chiếu equirectangular đơn giản cho thumbnail/ảnh chia sẻ (không phải bản đồ thật).
class RouteProjection {
  RouteProjection._(this._minX, this._minY, this._scale, this._offset, this._cosLat);

  final double _minX;
  final double _minY;
  final double _scale;
  final Offset _offset;
  final double _cosLat;

  static RouteProjection? fit(RouteLines route, Size size, {double padding = 12}) {
    final pts = route.expand((s) => s).toList();
    if (pts.isEmpty) return null;
    final meanLat = pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length;
    final cosLat = math.cos(meanLat * math.pi / 180).abs().clamp(0.01, 1.0);
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      final x = p.lon * cosLat;
      final y = -p.lat;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final w = math.max(maxX - minX, 1e-9);
    final h = math.max(maxY - minY, 1e-9);
    final availW = math.max(1.0, size.width - padding * 2);
    final availH = math.max(1.0, size.height - padding * 2);
    final scale = math.min(availW / w, availH / h);
    final offset = Offset((size.width - w * scale) / 2, (size.height - h * scale) / 2);
    return RouteProjection._(minX, minY, scale, offset, cosLat);
  }

  Offset project(GeoPoint p) => Offset((p.lon * _cosLat - _minX) * _scale + _offset.dx, (-p.lat - _minY) * _scale + _offset.dy);
}

/// Vẽ tuyến tĩnh: mỗi đoạn một path riêng, marker start/finish tùy chọn.
class RoutePainter extends CustomPainter {
  RoutePainter({required this.route, this.color = StrideColors.primary, this.strokeWidth = 3, this.showMarkers = true, this.fitRoute, this.padding = 12});

  final RouteLines route;
  final Color color;
  final double strokeWidth;
  final bool showMarkers;

  /// Tuyến dùng để tính khung (vd. tuyến gốc khi vẽ tuyến đã cắt, để không "phóng to" lộ vị trí).
  final RouteLines? fitRoute;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    final proj = RouteProjection.fit(fitRoute ?? route, size, padding: padding);
    if (proj == null) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final seg in route) {
      if (seg.length < 2) continue;
      final path = Path();
      final first = proj.project(seg.first);
      path.moveTo(first.dx, first.dy);
      for (final p in seg.skip(1)) {
        final o = proj.project(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
    if (!showMarkers) return;
    final nonEmpty = route.where((s) => s.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return;
    final s = proj.project(nonEmpty.first.first);
    final e = proj.project(nonEmpty.last.last);
    final r = strokeWidth * 1.8;
    // Start: chấm primary viền trắng.
    canvas.drawCircle(s, r + 2, Paint()..color = StrideColors.surface);
    canvas.drawCircle(s, r, Paint()..color = StrideColors.primary);
    // Finish: chấm navy có ô vuông trắng (gợi cờ đích).
    canvas.drawCircle(e, r + 2, Paint()..color = StrideColors.surface);
    canvas.drawCircle(e, r, Paint()..color = StrideColors.iconNavy);
    canvas.drawRect(Rect.fromCenter(center: e, width: r * 0.9, height: r * 0.9), Paint()..color = StrideColors.surface);
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) =>
      old.route != route || old.color != color || old.showMarkers != showMarkers || old.strokeWidth != strokeWidth || old.fitRoute != fitRoute;
}

/// Thumbnail tuyến tĩnh cho card (không phải bản đồ sống, không tải tile).
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail({super.key, required this.route, this.size = 88});
  final RouteLines? route;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = route;
    return ClipRRect(
      borderRadius: BorderRadius.circular(StrideRadius.control),
      child: Container(
        width: size,
        height: size,
        color: StrideColors.subtle,
        child: r == null || r.isEmpty
            ? const Icon(Icons.route_outlined, color: StrideColors.textMuted)
            : CustomPaint(painter: RoutePainter(route: r, strokeWidth: 2.5, padding: 10)),
      ),
    );
  }
}
