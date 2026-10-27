import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/presentation/common_components/map_tiles.dart';

/// MAP03: nền bản đồ không tải được (test không có mạng thật → mọi ô lỗi) → banner chữ trên bản đồ, không chỉ ô xám.
void main() {
  testWidgets('nhiều ô nền lỗi → hiện banner "Map background unavailable"', (tester) async {
    const env = EnvConfig(env: StrideEnv.dev, tileUrlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png', tileAttribution: '', flags: FeatureFlags());
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(21.03, 105.85), initialZoom: 14),
            children: [
              StrideTileLayer(
                env: env,
                tileProvider: NetworkTileProvider(cachingProvider: const DisabledMapCachingProvider()),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MapUnavailableBanner), findsNothing);
    for (var i = 0; i < 20 && find.byType(MapUnavailableBanner).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(MapUnavailableBanner), findsOneWidget);
    expect(find.text('Map background unavailable. Your route is still tracked and shown.'), findsOneWidget);
  });

  testWidgets('MAP04: TileLayer dùng maxNativeZoom của nhà cung cấp; tuyến < 20 m không phóng quá routeFitMaxZoom', (tester) async {
    const env = EnvConfig(
      env: StrideEnv.dev,
      tileUrlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png',
      tileAttribution: '',
      flags: FeatureFlags(),
      tileMaxNativeZoom: 18,
    );
    // Hai điểm cách ~10 m.
    const a = LatLng(21.0300, 105.8500);
    const b = LatLng(21.0300, 105.85009);
    late MapCamera camera;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(coordinates: const [a, b], maxZoom: routeFitMaxZoom),
              maxZoom: mapMaxZoom,
            ),
            children: [
              StrideTileLayer(
                env: env,
                tileProvider: NetworkTileProvider(cachingProvider: const DisabledMapCachingProvider()),
              ),
              Builder(
                builder: (context) {
                  camera = MapCamera.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect((layer.maxNativeZoom, layer.maxZoom), (18, mapMaxZoom));
    expect(camera.zoom, lessThanOrEqualTo(routeFitMaxZoom));
  });
}
