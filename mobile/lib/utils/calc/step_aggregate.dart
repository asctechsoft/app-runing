import '../../models/data_models/steps.dart';

/// Thứ tự ưu tiên nguồn mặc định; người dùng đổi được trong Data sources (F02).
const defaultSourcePriority = [StepSource.healthConnect, StepSource.healthKit, StepSource.device, StepSource.phoneSensor];

/// Phân bổ một mẫu [startAt,endAt) vào các giờ địa phương theo tỷ lệ thời gian.
/// [offsetMin] là offset múi giờ áp dụng cho mẫu. Trả map: dateKey → hour → steps (double).
Map<String, Map<int, double>> distributeSample(StepSample s, int offsetMin) {
  final out = <String, Map<int, double>>{};
  final dur = s.endAt - s.startAt;
  void add(DateTime localHourStart, double v) {
    final key =
        '${localHourStart.year.toString().padLeft(4, '0')}-${localHourStart.month.toString().padLeft(2, '0')}-${localHourStart.day.toString().padLeft(2, '0')}';
    final m = out.putIfAbsent(key, () => {});
    m[localHourStart.hour] = (m[localHourStart.hour] ?? 0) + v;
  }

  final off = Duration(minutes: offsetMin);
  if (dur <= 0) {
    final l = DateTime.fromMillisecondsSinceEpoch(s.startAt, isUtc: true).add(off);
    add(DateTime.utc(l.year, l.month, l.day, l.hour), s.steps.toDouble());
    return out;
  }
  var cursor = s.startAt;
  while (cursor < s.endAt) {
    final l = DateTime.fromMillisecondsSinceEpoch(cursor, isUtc: true).add(off);
    final hourStartLocal = DateTime.utc(l.year, l.month, l.day, l.hour);
    final nextHourUtcMs = hourStartLocal.add(const Duration(hours: 1)).subtract(off).millisecondsSinceEpoch;
    final end = nextHourUtcMs < s.endAt ? nextHourUtcMs : s.endAt;
    add(hourStartLocal, s.steps * (end - cursor) / dur);
    cursor = end;
  }
  return out;
}

/// Hợp nhất nhiều nguồn: với mỗi giờ, chỉ lấy nguồn ưu tiên cao nhất có dữ liệu ở giờ đó
/// (không cộng toàn bộ hai nguồn chồng khoảng — F02). Trả StepDay cho [dateKey].
StepDay aggregateDay({
  required String dateKey,
  required List<StepSample> samples,
  required int offsetMin,
  required bool hasPermission,
  List<StepSource> priority = defaultSourcePriority,
  bool sourceConfirmedZero = false,
}) {
  if (!hasPermission && samples.isEmpty) return StepDay(date: dateKey, status: StepDayStatus.noPermission);
  final perSource = <StepSource, Map<int, double>>{};
  int? lastAt;
  for (final s in samples) {
    final d = distributeSample(s, offsetMin)[dateKey];
    if (d == null) continue;
    final m = perSource.putIfAbsent(s.source, () => {});
    d.forEach((h, v) => m[h] = (m[h] ?? 0) + v);
    if (lastAt == null || s.endAt > lastAt) lastAt = s.endAt;
  }
  if (perSource.isEmpty) {
    return StepDay(date: dateKey, status: sourceConfirmedZero ? StepDayStatus.verifiedZero : StepDayStatus.noData, steps: sourceConfirmedZero ? 0 : null);
  }
  final hourly = List<int?>.filled(24, null);
  StepSource? used;
  for (var h = 0; h < 24; h++) {
    for (final src in priority) {
      final v = perSource[src]?[h];
      if (v != null) {
        hourly[h] = v.round();
        used ??= src;
        break;
      }
    }
  }
  final total = hourly.fold<int>(0, (a, v) => a + (v ?? 0));
  return StepDay(
    date: dateKey,
    status: total == 0 ? StepDayStatus.verifiedZero : StepDayStatus.populated,
    steps: total,
    hourly: hourly,
    lastSampleAt: lastAt,
    sourceUsed: used,
  );
}

/// Xử lý counter tích lũy kể từ boot (Android TYPE_STEP_COUNTER) (F01).
/// Trả delta hợp lệ hoặc null nếu là lần đọc đầu / counter reset (reboot) — không cộng tổng từ boot.
int? counterDelta({required int? lastCounter, required int current}) {
  if (lastCounter == null) return null;
  if (current < lastCounter) return null; // reboot: counter reset, chờ lần đọc sau để có baseline
  return current - lastCounter;
}
