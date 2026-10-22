import '../../models/data_models/steps.dart';

/// Ngưỡng nhịp bước (bước/phút) để tính là "active" — xấp xỉ đi bộ có chủ đích.
const activeCadenceThresholdSpm = 60.0;

/// Mẫu dài hơn ngưỡng này không đủ chi tiết để biết thời gian vận động thật.
const maxActiveSampleMs = 10 * 60 * 1000;

/// Phút vận động trong khoảng [fromMs, toMs) suy từ mẫu bước.
/// Chỉ dùng mẫu ngắn (≤ 10 phút) có nhịp ≥ ngưỡng. Không có mẫu ngắn nào → null (không đủ căn cứ, hiển thị —).
/// [source] giới hạn ở nguồn được dùng cho ngày đó để không cộng hai nguồn chồng nhau.
int? activeMinutesFromSamples(List<StepSample> samples, {required int fromMs, required int toMs, StepSource? source}) {
  var usable = 0;
  var activeMs = 0;
  for (final s in samples) {
    if (source != null && s.source != source) continue;
    final dur = s.endAt - s.startAt;
    if (dur <= 0 || dur > maxActiveSampleMs) continue;
    usable++;
    final cadence = s.steps / (dur / 60000);
    if (cadence < activeCadenceThresholdSpm) continue;
    // Chỉ tính phần nằm trong ngày.
    final a = s.startAt < fromMs ? fromMs : s.startAt;
    final b = s.endAt > toMs ? toMs : s.endAt;
    if (b > a) activeMs += b - a;
  }
  if (usable == 0) return null;
  return activeMs ~/ 60000;
}

/// Một hàng giờ cho danh sách thay thế/tooltip: null = không có mẫu (khác 0), future = giờ chưa tới.
class HourEntry {
  const HourEntry({required this.hour, required this.steps, required this.future});
  final int hour;
  final int? steps;
  final bool future;
}

/// Ghép hourly với giờ hiện tại: giờ tương lai (trong hôm nay) luôn rỗng, kể cả khi có giá trị lạ.
List<HourEntry> hourEntries(StepDay day, {required String todayKey, required int nowHour}) {
  final isToday = day.date == todayKey;
  final isFutureDay = day.date.compareTo(todayKey) > 0;
  return [
    for (var h = 0; h < 24; h++)
      HourEntry(hour: h, future: isFutureDay || (isToday && h > nowHour), steps: (isFutureDay || (isToday && h > nowHour)) ? null : day.hourly?[h]),
  ];
}

String hourLabel(int h) {
  final suffix = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 $suffix';
}

String sourceLabel(StepSource? s) => switch (s) {
  StepSource.phoneSensor => 'This phone',
  StepSource.healthConnect => 'Health Connect',
  StepSource.healthKit => 'Apple Health',
  StepSource.device => 'Connected device',
  null => 'No source yet',
};
