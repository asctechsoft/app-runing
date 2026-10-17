import 'package:intl/intl.dart';

/// Đồng hồ tường + đồng hồ đơn điệu. Thay bằng [FakeClock] trong test (C04).
abstract class Clock {
  /// UTC epoch ms.
  int nowMs();

  /// Mili giây đơn điệu (không bị đổi giờ hệ thống). Chỉ so sánh trong cùng process.
  int monoMs();

  DateTime nowLocal() => DateTime.fromMillisecondsSinceEpoch(nowMs());
}

class SystemClock extends Clock {
  SystemClock() : _sw = Stopwatch()..start(), _base = DateTime.now().millisecondsSinceEpoch;
  final Stopwatch _sw;
  final int _base;

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Gốc tính từ lúc tạo clock: base + elapsed. Sau khi process chết, recovery dùng checkpoint thay vì mono.
  @override
  int monoMs() => _base + _sw.elapsedMilliseconds;
}

class FakeClock extends Clock {
  FakeClock([int start = 1760000000000]) : _now = start, _mono = 0;
  int _now;
  int _mono;

  @override
  int nowMs() => _now;
  @override
  int monoMs() => _mono;

  void advance(Duration d) {
    _now += d.inMilliseconds;
    _mono += d.inMilliseconds;
  }

  /// Mô phỏng đổi giờ hệ thống: chỉ đồng hồ tường thay đổi.
  void jumpWallClock(Duration d) => _now += d.inMilliseconds;
}

final _dateFmt = DateFormat('yyyy-MM-dd');

/// Ngày địa phương YYYY-MM-DD theo giờ máy.
String localDateKey(DateTime local) => _dateFmt.format(local);

/// Ngày địa phương của timestamp UTC với offset (phút) đã lưu cùng bản ghi.
String localDateKeyFor(int utcMs, int tzOffsetMin) =>
    _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).add(Duration(minutes: tzOffsetMin)));

DateTime parseDateKey(String key) => DateTime.parse(key);

/// Đầu tuần chứa [day] theo [weekStart] (DateTime.monday..sunday).
DateTime startOfWeek(DateTime day, int weekStart) {
  final d = DateTime(day.year, day.month, day.day);
  final diff = (d.weekday - weekStart + 7) % 7;
  return DateTime(d.year, d.month, d.day - diff);
}

/// Tên múi giờ hiện tại; Flutter không có IANA id trực tiếp, dùng timeZoneName + offset.
String currentTzId() => DateTime.now().timeZoneName;
int currentTzOffsetMin() => DateTime.now().timeZoneOffset.inMinutes;
