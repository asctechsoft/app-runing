import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../utils/l10n.dart';
import '../../../utils/logger.dart';
import '../../../controller/providers.dart';
import '../../../values/tokens.dart';
import '../../../utils/calc/geo.dart';
import '../../../models/data_models/activity.dart';
import '../../../controller/run/engine/run_sources.dart';
import '../../common_components/map_tiles.dart';

/// Vị trí hiện tại để vẽ chấm xanh + quầng sai số.
class RunMapCurrent {
  const RunMapCurrent({required this.lat, required this.lon, this.accuracyM, this.stale = false});
  final double lat;
  final double lon;
  final double? accuracyM;

  /// Vị trí cũ (mất GPS) — vẽ xám, không trình bày như hiện tại.
  final bool stale;
}

/// Mốc km/mi trên tuyến (cộng dồn trong từng segment, không tính qua gap).
List<(int, LatLng)> distanceMarkers(List<List<TrackPoint>> segments, double everyM) {
  final out = <(int, LatLng)>[];
  if (everyM <= 0) return out;
  var acc = 0.0;
  var next = everyM;
  for (final seg in segments) {
    for (var i = 1; i < seg.length; i++) {
      final a = seg[i - 1];
      final b = seg[i];
      final d = haversineM(a.lat, a.lon, b.lat, b.lon);
      while (acc + d >= next && d > 0) {
        final frac = (next - acc) / d;
        out.add((out.length + 1, LatLng(a.lat + (b.lat - a.lat) * frac, a.lon + (b.lon - a.lon) * frac)));
        next += everyM;
      }
      acc += d;
    }
  }
  return out;
}

/// Bản đồ phiên chạy dùng chung (prepare, live, results). Tile + attribution lấy từ env (attribution luôn hiển thị).
class RunMap extends ConsumerStatefulWidget {
  const RunMap({
    super.key,
    this.segments = const [],
    this.current,
    this.showFinish = false,
    this.follow = true,
    this.fitRoute = false,
    this.markerEveryM,
    this.interactive = true,
    this.showRecenter = true,
    this.initialZoom = 16,
  });

  final List<List<TrackPoint>> segments;
  final RunMapCurrent? current;

  /// Cờ đích chỉ vẽ ở results — không bao giờ khi đang ghi (G09).
  final bool showFinish;
  final bool follow;
  final bool fitRoute;
  final double? markerEveryM;
  final bool interactive;
  final bool showRecenter;
  final double initialZoom;

  @override
  ConsumerState<RunMap> createState() => _RunMapState();
}

class _RunMapState extends ConsumerState<RunMap> {
  final _mc = MapController();
  bool _ready = false;
  late bool _follow = widget.follow;

  LatLng? get _currentLatLng => widget.current == null ? null : LatLng(widget.current!.lat, widget.current!.lon);

  List<LatLng> get _allPoints => [
    for (final s in widget.segments)
      for (final p in s) LatLng(p.lat, p.lon),
  ];

  @override
  void didUpdateWidget(covariant RunMap old) {
    super.didUpdateWidget(old);
    final c = _currentLatLng;
    if (_ready && _follow && c != null && !widget.fitRoute) {
      try {
        _mc.move(c, _mc.camera.zoom);
      } catch (_) {}
    }
  }

  void _onReady() {
    _ready = true;
  }

  /// Căn khớp lộ trình ngay từ camera đầu tiên (`initialCameraFit`). Không gọi `fitCamera` trong `onMapReady`: làm vậy lớp tile
  /// không tải ô nào cho tới khi người dùng chạm vào bản đồ (màn kết quả hiện nền xám).
  CameraFit? get _initialFit {
    if (!widget.fitRoute) return null;
    final pts = _allPoints;
    if (pts.length < 2) return null;
    return CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(40), maxZoom: 17);
  }

  void _recenter() {
    final c = _currentLatLng ?? (_allPoints.isEmpty ? null : _allPoints.last);
    if (c == null) return;
    setState(() => _follow = true);
    _mc.move(c, _mc.camera.zoom < 15 ? 16 : _mc.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(envProvider);
    final tiles = ref.watch(runMapTilesEnabledProvider);
    final pts = _allPoints;
    final center = _currentLatLng ?? (pts.isEmpty ? null : pts.last);
    if (center == null) {
      return Container(
        color: StrideColors.subtle,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_searching, color: StrideColors.primary, size: 32),
            const SizedBox(height: 8),
            Text('run_map_waiting'.tr, style: StrideText.bodySecondary),
          ],
        ),
      );
    }
    final start = pts.isEmpty ? null : pts.first;
    final finish = widget.showFinish && pts.isNotEmpty ? pts.last : null;
    final markers = widget.markerEveryM == null ? const <(int, LatLng)>[] : distanceMarkers(widget.segments, widget.markerEveryM!);
    final cur = widget.current;

    return Stack(
      children: [
        Semantics(
          label: 'run_map_semantic'.tr,
          child: FlutterMap(
            mapController: _mc,
            options: MapOptions(
              initialCenter: center,
              initialZoom: widget.initialZoom,
              initialCameraFit: _initialFit,
              onMapReady: _onReady,
              interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
              onPositionChanged: (camera, hasGesture) {
                // Người dùng kéo bản đồ → tắt follow camera.
                if (hasGesture && _follow) setState(() => _follow = false);
              },
            ),
            children: [
              if (tiles)
                // Ghi log khi nền bản đồ không tải được (mất mạng, bị chặn) để dễ chẩn đoán thay vì chỉ thấy khung trống.
                strideTileLayer(env, errorTileCallback: (tile, error, stackTrace) => StrideLog.d('map', 'tile ${tile.coordinates} failed: $error')),
              PolylineLayer(
                polylines: [
                  for (final s in widget.segments)
                    if (s.length >= 2)
                      Polyline(
                        points: [for (final p in s) LatLng(p.lat, p.lon)],
                        strokeWidth: 4,
                        color: StrideColors.primary,
                        borderStrokeWidth: 2,
                        borderColor: StrideColors.surface,
                      ),
                ],
              ),
              if (cur != null && cur.accuracyM != null && !cur.stale)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(cur.lat, cur.lon),
                      radius: cur.accuracyM!.clamp(3, 100).toDouble(),
                      useRadiusInMeter: true,
                      color: StrideColors.mapCurrent.withValues(alpha: 0.15),
                      borderColor: StrideColors.mapCurrent.withValues(alpha: 0.3),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (start != null)
                    Marker(
                      point: start,
                      width: 18,
                      height: 18,
                      child: Semantics(
                        label: 'run_map_start'.tr,
                        child: Container(
                          decoration: BoxDecoration(
                            color: StrideColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: StrideColors.surface, width: 3),
                          ),
                        ),
                      ),
                    ),
                  for (final (n, p) in markers)
                    Marker(
                      point: p,
                      width: 30,
                      height: 22,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: StrideColors.surface,
                          borderRadius: BorderRadius.circular(StrideRadius.pill),
                          border: Border.all(color: StrideColors.primary, width: 1.5),
                        ),
                        child: Text(
                          '$n',
                          style: StrideText.caption.copyWith(color: StrideColors.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (finish != null)
                    Marker(
                      point: finish,
                      width: 30,
                      height: 30,
                      child: Semantics(
                        label: 'run_map_finish'.tr,
                        child: Container(
                          decoration: BoxDecoration(
                            color: StrideColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: StrideColors.textPrimary, width: 2),
                          ),
                          child: const Icon(Icons.sports_score, size: 18, color: StrideColors.textPrimary),
                        ),
                      ),
                    ),
                  if (cur != null)
                    Marker(
                      point: LatLng(cur.lat, cur.lon),
                      width: 22,
                      height: 22,
                      child: Semantics(
                        label: cur.stale ? 'run_map_last_known'.tr : 'run_map_current'.tr,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cur.stale ? StrideColors.textMuted : StrideColors.mapCurrent,
                            shape: BoxShape.circle,
                            border: Border.all(color: StrideColors.surface, width: 3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Attribution luôn hiển thị (điều khoản tile provider); tự xuống dòng trên màn hẹp.
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  constraints: const BoxConstraints(maxWidth: 260),
                  decoration: BoxDecoration(color: StrideColors.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(StrideRadius.small)),
                  child: Text(env.tileAttribution, style: StrideText.caption.copyWith(fontSize: 11, color: StrideColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
        if (widget.showRecenter && widget.interactive)
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: StrideColors.surface,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'run_map_recenter'.tr,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(_follow ? Icons.my_location : Icons.location_searching, color: StrideColors.primary),
                onPressed: _recenter,
              ),
            ),
          ),
      ],
    );
  }
}
