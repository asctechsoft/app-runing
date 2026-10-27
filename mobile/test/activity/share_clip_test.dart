import 'package:flutter_test/flutter_test.dart';
import 'package:stride/presentation/screens_activity/share_activity_screen.dart';
import 'package:stride/utils/calc/geo.dart';
import 'package:stride/utils/route_geometry.dart';

double _d(GeoPoint a, GeoPoint b) => haversineM(a.lat, a.lon, b.lat, b.lon);

RouteLines _line(double meters, {double stepM = 10, double bearing = 90, double lat = 21.0, double lon = 105.8}) {
  final n = (meters / stepM).round();
  return [
    [
      for (var i = 0; i <= n; i++)
        () {
          final (la, lo) = offsetPoint(lat, lon, i * stepM, bearing);
          return GeoPoint(la, lo);
        }(),
    ],
  ];
}

void main() {
  group('clipRouteEnds (I06 hide start & finish)', () {
    test('không còn điểm nào trong bán kính ẩn quanh start và finish', () {
      final route = _line(2000);
      final start = route.first.first;
      final end = route.last.last;
      final clipped = clipRouteEnds(route, 200);
      expect(clipped, isNotEmpty);
      for (final seg in clipped) {
        for (final p in seg) {
          expect(_d(p, start), greaterThan(200));
          expect(_d(p, end), greaterThan(200));
        }
      }
      // Phần còn lại ≈ 2000 - 2*200.
      expect(routeLengthM(clipped), closeTo(1600, 15));
    });

    test('tuyến gốc không bị sửa (bản sao)', () {
      final route = _line(1000);
      final before = route.first.length;
      final first = route.first.first;
      clipRouteEnds(route, 200);
      expect(route.first.length, before);
      expect(identical(route.first.first, first), isTrue);
    });

    test('tuyến vòng: đoạn quay lại gần điểm xuất phát cũng bị ẩn', () {
      // Đi 1 km về phía đông, rồi 1 km về phía tây quay lại gần start, rồi 600 m về phía bắc.
      final out = _line(1000).first;
      final back = _line(1000, bearing: 270, lat: out.last.lat, lon: out.last.lon).first;
      final north = _line(600, bearing: 0, lat: back.last.lat, lon: back.last.lon).first;
      final route = [
        [...out, ...back.skip(1), ...north.skip(1)],
      ];
      final start = route.first.first;
      final end = route.first.last;
      final clipped = clipRouteEnds(route, 200);
      for (final seg in clipped) {
        for (final p in seg) {
          expect(_d(p, start), greaterThan(200));
          expect(_d(p, end), greaterThan(200));
        }
      }
      // Đường bị cắt thành nhiều đoạn, không nối xuyên vùng ẩn.
      expect(clipped.length, greaterThanOrEqualTo(2));
    });

    test('cạnh dài thưa điểm đi xuyên vùng ẩn vẫn bị cắt (densify)', () {
      // Ba điểm cách nhau 1 km: cạnh start→giữa đi qua vùng 200 m quanh start.
      final route = _line(2000, stepM: 1000);
      final start = route.first.first;
      final clipped = clipRouteEnds(route, 200);
      for (final seg in clipped) {
        for (final p in seg) {
          expect(_d(p, start), greaterThan(200));
        }
      }
    });

    test('tuyến quá ngắn → không còn gì để vẽ', () {
      final clipped = clipRouteEnds(_line(300), 200);
      expect(routeLengthM(clipped), lessThan(minVisibleRouteM));
    });

    test('segment tách rời vẫn tách rời sau khi cắt', () {
      final a = _line(1000).first;
      final b = _line(1000, lat: 21.02, lon: 105.8).first;
      final clipped = clipRouteEnds([a, b], 200);
      expect(clipped.length, 2);
    });

    test('shareRouteFor tắt ẩn → giữ nguyên tuyến', () {
      final route = _line(1000);
      expect(shareRouteFor(route, const ShareConfig(hideEnds: false)), same(route));
      expect(routeLengthM(shareRouteFor(route, const ShareConfig())), lessThan(routeLengthM(route)));
    });
  });
}
