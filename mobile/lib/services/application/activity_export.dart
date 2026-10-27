import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/data_models/activity.dart';
import '../../utils/calc/gps_filter.dart';

/// Xuất dữ liệu một hoạt động (I07, F18). Chỉ dữ liệu của chính hoạt động đó, không thêm điểm giả.

String _iso(int utcMs) => DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).toIso8601String();

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

/// Hoạt động có tuyến GPS thật để xuất GPX hay không (không có → không hiện tùy chọn GPX).
bool canExportGpx(Activity a, List<TrackPoint> points) => a.hasGps && points.any((p) => p.accepted);

/// GPX 1.1: mỗi segment một `<trkseg>`, chỉ điểm accepted, thời gian ISO-8601 UTC.
/// Không nối hay lấp khoảng trống giữa các segment. Trả null nếu không có GPS.
String? buildGpx(Activity a, List<TrackPoint> points, {String title = ''}) {
  if (!canExportGpx(a, points)) return null;
  final segs = polylinesBySegment(points).where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final name = _xml(title.isNotEmpty ? title : a.title);
  final type = switch (a.type) {
    ActivityType.walk => 'walking',
    _ => 'running',
  };
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="STRIDE" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata>')
    ..writeln('    <name>$name</name>')
    ..writeln('    <time>${_iso(a.startedAt)}</time>')
    ..writeln('  </metadata>')
    ..writeln('  <trk>')
    ..writeln('    <name>$name</name>')
    ..writeln('    <type>$type</type>');
  for (final seg in segs) {
    b.writeln('    <trkseg>');
    for (final p in seg) {
      b.write('      <trkpt lat="${p.lat.toStringAsFixed(7)}" lon="${p.lon.toStringAsFixed(7)}">');
      if (p.altitudeM != null) b.write('<ele>${p.altitudeM!.toStringAsFixed(1)}</ele>');
      b.writeln('<time>${_iso(p.t)}</time></trkpt>');
    }
    b.writeln('    </trkseg>');
  }
  b
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}

/// Một ô CSV an toàn theo locale: số luôn dùng dấu '.', chuỗi có , " xuống dòng được bọc nháy kép.
/// Chuỗi bắt đầu bằng = + - @ được thêm ' để bảng tính không hiểu là công thức.
String csvField(Object? v) {
  if (v == null) return '';
  if (v is num) return v.toString();
  var s = v.toString();
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') || s.trim() != s;
  if (!needsQuote) return s;
  return '"${s.replaceAll('"', '""')}"';
}

const csvColumns = [
  'id',
  'title',
  'type',
  'started_at_utc',
  'tz_offset_min',
  'distance_m',
  'distance_source',
  'moving_s',
  'elapsed_s',
  'avg_pace_s_per_km',
  'steps',
  'calories_kcal_estimated',
  'feeling',
  'notes',
  'privacy',
];

String? _fixed(double? v, int digits) => v?.toStringAsFixed(digits);

/// CSV tổng quan (header + một dòng mỗi hoạt động), xuống dòng CRLF theo RFC 4180.
String buildActivityCsv(List<Activity> activities) {
  final lines = <String>[csvColumns.join(',')];
  for (final a in activities) {
    final row = <Object?>[
      a.id,
      a.title,
      a.type.name,
      _iso(a.startedAt),
      a.tzOffsetMin,
      // Chuỗi số đã cố định '.' để không bị locale đổi thành ','.
      _numCell(_fixed(a.distanceM, 1)),
      a.distanceSource.name,
      (a.movingMs / 1000).round(),
      (a.elapsedMs / 1000).round(),
      _numCell(_fixed(a.avgPaceSecPerKm, 1)),
      a.steps,
      _numCell(_fixed(a.caloriesKcal, 0)),
      a.feeling?.name,
      a.notes,
      a.privacy.name,
    ];
    lines.add(row.map(csvField).join(','));
  }
  return '${lines.join('\r\n')}\r\n';
}

/// Số đã làm tròn cố định; giữ kiểu num để csvField không coi số âm là công thức.
Object? _numCell(String? s) => s == null ? null : num.parse(s);

String exportFileStem(Activity a) {
  final d = DateTime.fromMillisecondsSinceEpoch(a.startedAt, isUtc: true).add(Duration(minutes: a.tzOffsetMin));
  String two(int v) => v.toString().padLeft(2, '0');
  return 'stride-${a.type.name}-${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
}

/// Ghi tệp tạm và mở bảng chia sẻ hệ thống. Trả trạng thái thật từ hệ thống (dismissed ≠ success).
Future<ShareResult> shareBytesAsFile({required Uint8List bytes, required String fileName, required String mime, String? subject}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$fileName');
  await f.writeAsBytes(bytes, flush: true);
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(f.path, mimeType: mime, name: fileName)],
      subject: subject,
    ),
  );
}
