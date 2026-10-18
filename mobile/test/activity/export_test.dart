import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/activity/activity_charts_data.dart';
import 'package:stride/features/activity/activity_export.dart';

Activity _activity({bool gps = true, String title = 'Morning run', String? notes, double? distance = 5234.56}) => Activity(
  id: 'a1',
  ownerId: 'o',
  type: ActivityType.run,
  status: ActivityStatus.saved,
  startedAt: DateTime.utc(2026, 10, 15, 0, 20).millisecondsSinceEpoch,
  tzId: 'Asia/Ho_Chi_Minh',
  tzOffsetMin: 420,
  distanceM: distance,
  movingMs: 1934000,
  elapsedMs: 2046000,
  avgPaceSecPerKm: 369.47,
  caloriesKcal: 338.4,
  title: title,
  notes: notes,
  hasGps: gps,
);

TrackPoint _p(String seg, int seq, double lat, double lon, {bool accepted = true, double? alt}) => TrackPoint(
  activityId: 'a1',
  segmentId: seg,
  seq: seq,
  t: DateTime.utc(2026, 10, 15, 0, 20).millisecondsSinceEpoch + seq * 1000,
  lat: lat,
  lon: lon,
  altitudeM: alt,
  accepted: accepted,
);

void main() {
  group('GPX (I07)', () {
    final points = [
      _p('s1', 0, 21.0, 105.8, alt: 10),
      _p('s1', 1, 21.0001, 105.8),
      _p('s1', 2, 21.5, 106.0, accepted: false), // bị loại → không xuất
      _p('s2', 3, 21.001, 105.801),
      _p('s2', 4, 21.0011, 105.801),
    ];

    test('mỗi segment một trkseg, không nối, không có điểm bị loại', () {
      final gpx = buildGpx(_activity(), points)!;
      expect(RegExp('<trkseg>').allMatches(gpx).length, 2);
      expect(RegExp('<trkpt ').allMatches(gpx).length, 4);
      expect(gpx, isNot(contains('21.5000000')));
      expect(gpx, contains('<time>2026-10-15T00:20:00.000Z</time>'));
      expect(gpx, contains('<ele>10.0</ele>'));
      // Đoạn 1 kết thúc trước khi đoạn 2 bắt đầu — không có trkpt nào nằm giữa </trkseg> và <trkseg>.
      final between = gpx.substring(gpx.indexOf('</trkseg>'), gpx.lastIndexOf('<trkseg>'));
      expect(between, isNot(contains('<trkpt')));
    });

    test('không có GPS → không có GPX', () {
      expect(buildGpx(_activity(gps: false), points), isNull);
      expect(canExportGpx(_activity(), [_p('s1', 0, 1, 1, accepted: false)]), isFalse);
    });

    test('tên được escape XML', () {
      final gpx = buildGpx(_activity(title: 'Run <with> "friends" & co'), points, title: 'Run <with> "friends" & co')!;
      expect(gpx, contains('Run &lt;with&gt; &quot;friends&quot; &amp; co'));
    });
  });

  group('CSV (I07)', () {
    test('trích dẫn dấu phẩy, nháy kép, xuống dòng; chặn công thức', () {
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField('line1\nline2'), '"line1\nline2"');
      expect(csvField('=SUM(A1)'), "'=SUM(A1)");
      expect(csvField(null), '');
      expect(csvField(-1.5), '-1.5');
    });

    test('số luôn dùng dấu chấm kể cả khi locale dùng dấu phẩy', () {
      final prev = Intl.defaultLocale;
      Intl.defaultLocale = 'vi_VN';
      addTearDown(() => Intl.defaultLocale = prev);
      final csv = buildActivityCsv([_activity(title: 'Chạy sáng, Hồ Tây', notes: 'Trời "mát"')]);
      final lines = csv.split('\r\n');
      expect(lines.first, csvColumns.join(','));
      final row = lines[1];
      expect(row, contains('5234.6'));
      expect(row, contains('369.5'));
      expect(row, contains('"Chạy sáng, Hồ Tây"'));
      expect(row, contains('"Trời ""mát"""'));
      // Số cột không bị phá bởi dấu phẩy trong tiêu đề.
      expect(_splitCsv(row).length, csvColumns.length);
    });

    test('thiếu dữ liệu → ô rỗng, không 0 giả', () {
      final row = buildActivityCsv([_activity(distance: null)]).split('\r\n')[1];
      final cells = _splitCsv(row);
      expect(cells[csvColumns.indexOf('distance_m')], '');
    });
  });

  group('Chart series (I02)', () {
    test('ít điểm → không vẽ pace và có lý do', () {
      final s = paceSeries([_p('s1', 0, 21, 105), _p('s1', 1, 21.0001, 105)]);
      expect(s.available, isFalse);
      expect(s.reason, isNotEmpty);
    });

    test('không có altitude → không có biểu đồ độ cao; không có HR → không có biểu đồ nhịp tim', () {
      final pts = [for (var i = 0; i < 20; i++) _p('s1', i, 21 + i * 0.0001, 105)];
      expect(elevationSeries(pts).available, isFalse);
      expect(heartRateSeries(const [], 0).available, isFalse);
    });

    test('đủ GPS → có chuỗi pace hợp lý', () {
      // 2 km, 10 m mỗi 3 s → pace 300 s/km.
      final pts = [for (var i = 0; i <= 200; i++) _p('s1', i, 21 + i * 10 / 111195, 105)];
      final fixed = [for (final p in pts) TrackPoint(activityId: 'a1', segmentId: 's1', seq: p.seq, t: p.seq * 3000, lat: p.lat, lon: p.lon)];
      final s = paceSeries(fixed);
      expect(s.available, isTrue);
      for (final x in s.samples) {
        expect(x.y, closeTo(300, 5));
      }
    });
  });
}

/// Tách một dòng CSV theo RFC 4180 (đủ cho test).
List<String> _splitCsv(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQ = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQ) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        buf.write(c);
      }
    } else if (c == '"') {
      inQ = true;
    } else if (c == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}
