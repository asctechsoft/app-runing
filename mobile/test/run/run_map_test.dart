import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/run/engine/run_sources.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_run/components/run_map.dart';

/// X41: màn kết quả phải căn khớp lộ trình ngay từ camera đầu tiên (`initialCameraFit`), không gọi `fitCamera` trong
/// `onMapReady` — làm vậy lớp tile không tải ô nào cho tới khi người dùng chạm vào bản đồ (nền xám).
void main() {
  TrackPoint pt(int seq, double lat, double lon) => TrackPoint(activityId: 'a', segmentId: 's', seq: seq, t: seq * 1000, lat: lat, lon: lon);

  final route = [
    [pt(0, 40.7812, -73.9665), pt(1, 40.7822, -73.9665), pt(2, 40.7832, -73.9660)],
  ];

  Future<MapOptions> pumpMap(WidgetTester tester, {required bool fitRoute}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runMapTilesEnabledProvider.overrideWithValue(false),
          envProvider.overrideWithValue(const EnvConfig(env: StrideEnv.dev, tileUrlTemplate: '', tileAttribution: '', flags: FeatureFlags())),
        ],
        child: MaterialApp(
          home: SizedBox(
            height: 240,
            child: RunMap(segments: route, showFinish: true, fitRoute: fitRoute, follow: false, showRecenter: false),
          ),
        ),
      ),
    );
    return tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
  }

  testWidgets('fitRoute (màn kết quả) → initialCameraFit bao lộ trình', (tester) async {
    final options = await pumpMap(tester, fitRoute: true);
    expect(options.initialCameraFit, isNotNull);
  });

  testWidgets('không fitRoute (màn ghi chạy) → không đặt initialCameraFit, camera đi theo vị trí', (tester) async {
    final options = await pumpMap(tester, fitRoute: false);
    expect(options.initialCameraFit, isNull);
  });
}
