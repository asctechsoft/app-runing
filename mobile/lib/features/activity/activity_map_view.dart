import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import 'activity_providers.dart';
import 'route_geometry.dart';

/// Bản đồ tuyến: segment vẽ riêng (không nối qua pause/gap), marker start + cờ đích.
/// Khi tile tắt (test) hoặc tuyến rỗng → vẽ sơ đồ tĩnh bằng painter; offline tile lỗi thì polyline vẫn hiện.
class ActivityRouteMap extends ConsumerStatefulWidget {
  const ActivityRouteMap({super.key, required this.route, this.interactive = false, this.padding = const EdgeInsets.all(28)});

  final RouteLines route;
  final bool interactive;
  final EdgeInsets padding;

  @override
  ConsumerState<ActivityRouteMap> createState() => ActivityRouteMapState();
}

class ActivityRouteMapState extends ConsumerState<ActivityRouteMap> {
  final _controller = MapController();

  List<LatLng> get _all => [
    for (final s in widget.route)
      for (final p in s) LatLng(p.lat, p.lon),
  ];

  CameraFit get _fit => CameraFit.coordinates(coordinates: _all, padding: widget.padding, maxZoom: 17);

  /// Đưa camera về toàn tuyến (nút Re-center ở màn full map).
  void recenter() => _controller.fitCamera(_fit);

  @override
  Widget build(BuildContext context) {
    final tiles = ref.watch(activityMapTilesEnabledProvider);
    final env = ref.watch(envProvider);
    final route = widget.route;
    if (route.isEmpty) return const SizedBox.shrink();
    if (!tiles) {
      return ColoredBox(
        color: StrideColors.subtle,
        child: CustomPaint(
          painter: RoutePainter(route: route, strokeWidth: 4, padding: 24),
          child: const SizedBox.expand(),
        ),
      );
    }
    final nonEmpty = route.where((s) => s.isNotEmpty).toList();
    final start = nonEmpty.first.first;
    final end = nonEmpty.last.last;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: _fit,
        backgroundColor: StrideColors.subtle,
        interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: env.tileUrlTemplate, userAgentPackageName: 'com.asc.app_runing'),
        PolylineLayer(
          polylines: [
            for (final seg in route)
              if (seg.length >= 2)
                Polyline(
                  points: [for (final p in seg) LatLng(p.lat, p.lon)],
                  color: StrideColors.primary,
                  strokeWidth: 5,
                  borderColor: StrideColors.surface,
                  borderStrokeWidth: 1.5,
                ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(start.lat, start.lon),
              width: 22,
              height: 22,
              child: Semantics(
                label: 'Start',
                child: Container(
                  decoration: BoxDecoration(
                    color: StrideColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: StrideColors.surface, width: 3),
                  ),
                ),
              ),
            ),
            Marker(
              point: LatLng(end.lat, end.lon),
              width: 30,
              height: 30,
              child: Semantics(
                label: 'Finish',
                child: Container(
                  decoration: BoxDecoration(
                    color: StrideColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: StrideColors.iconNavy, width: 2),
                  ),
                  child: const Icon(Icons.sports_score, size: 18, color: StrideColors.iconNavy),
                ),
              ),
            ),
          ],
        ),
        SimpleAttributionWidget(source: Text(env.tileAttribution, style: StrideText.caption)),
      ],
    );
  }
}
