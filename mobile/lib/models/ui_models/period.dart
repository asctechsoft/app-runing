import 'package:intl/intl.dart';

import '../../utils/clock.dart';
import '../../utils/date_locale.dart';
import '../../utils/l10n.dart';

/// Kỳ thống kê (I04).
enum ProgressPeriod { week, month, year }

enum ProgressKind { steps, running }

ProgressPeriod parseProgressPeriod(String? s) => ProgressPeriod.values.firstWhere((p) => p.name == s, orElse: () => ProgressPeriod.week);

ProgressKind parseProgressKind(String? s) => ProgressKind.values.firstWhere((k) => k.name == s, orElse: () => ProgressKind.running);

/// Khoảng [start, end) theo ngày địa phương của máy. Dùng DateTime(y, m, d) để an toàn khi đổi giờ (DST).
class PeriodRange {
  const PeriodRange(this.period, this.start, this.end);

  final ProgressPeriod period;
  final DateTime start;
  final DateTime end;

  int get fromMs => start.millisecondsSinceEpoch;
  int get toMs => end.millisecondsSinceEpoch;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) => other is PeriodRange && other.period == period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(period, start, end);

  @override
  String toString() => 'PeriodRange($period, $start, $end)';
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Kỳ chứa [anchor]. Tuần bắt đầu theo [weekStart] (DateTime.monday..sunday) từ settings.
PeriodRange periodFor(ProgressPeriod p, DateTime anchor, int weekStart) {
  switch (p) {
    case ProgressPeriod.week:
      final s = startOfWeek(anchor, weekStart);
      return PeriodRange(p, s, DateTime(s.year, s.month, s.day + 7));
    case ProgressPeriod.month:
      return PeriodRange(p, DateTime(anchor.year, anchor.month), DateTime(anchor.year, anchor.month + 1));
    case ProgressPeriod.year:
      return PeriodRange(p, DateTime(anchor.year), DateTime(anchor.year + 1));
  }
}

/// Kỳ trước/sau [delta] kỳ.
PeriodRange shiftPeriod(PeriodRange r, int delta, int weekStart) {
  final s = r.start;
  final anchor = switch (r.period) {
    ProgressPeriod.week => DateTime(s.year, s.month, s.day + 7 * delta),
    ProgressPeriod.month => DateTime(s.year, s.month + delta),
    ProgressPeriod.year => DateTime(s.year + delta),
  };
  return periodFor(r.period, anchor, weekStart);
}

/// Cột biểu đồ: ngày (tuần/tháng) hoặc tháng (năm).
class PeriodBucket {
  const PeriodBucket(this.start, this.end);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

List<PeriodBucket> bucketsFor(PeriodRange r) {
  final out = <PeriodBucket>[];
  if (r.period == ProgressPeriod.year) {
    for (var m = 0; m < 12; m++) {
      out.add(PeriodBucket(DateTime(r.start.year, r.start.month + m), DateTime(r.start.year, r.start.month + m + 1)));
    }
  } else {
    for (var d = r.start; d.isBefore(r.end); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(PeriodBucket(d, DateTime(d.year, d.month, d.day + 1)));
    }
  }
  return out;
}

/// Chỉ số cột chứa thời điểm [t] (giờ máy), -1 nếu ngoài kỳ.
int bucketIndexOf(List<PeriodBucket> buckets, DateTime t) {
  for (var i = 0; i < buckets.length; i++) {
    if (buckets[i].contains(t)) return i;
  }
  return -1;
}

/// So sánh kỳ cùng độ phủ (F16): kỳ đang diễn ra chỉ so với cùng số ngày đầu của kỳ trước.
class Coverage {
  const Coverage({required this.currentEnd, required this.previous, required this.previousEnd, required this.ongoing});

  /// Kết thúc (exclusive) phần đã qua của kỳ hiện tại — hết hôm nay nếu kỳ đang diễn ra.
  final DateTime currentEnd;
  final PeriodRange previous;

  /// Kết thúc (exclusive) phần tương ứng của kỳ trước.
  final DateTime previousEnd;
  final bool ongoing;
}

Coverage comparableCoverage(PeriodRange current, DateTime now, int weekStart) {
  final prev = shiftPeriod(current, -1, weekStart);
  final today = dayOnly(now);
  if (!current.contains(today)) {
    return Coverage(currentEnd: current.end, previous: prev, previousEnd: prev.end, ongoing: false);
  }
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  DateTime prevEnd;
  switch (current.period) {
    case ProgressPeriod.week:
      final days =
          DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(current.start.year, current.start.month, current.start.day)).inDays + 1;
      prevEnd = DateTime(prev.start.year, prev.start.month, prev.start.day + days);
    case ProgressPeriod.month:
      final daysInPrev = DateTime(prev.start.year, prev.start.month + 1, 0).day;
      prevEnd = DateTime(prev.start.year, prev.start.month, (today.day < daysInPrev ? today.day : daysInPrev) + 1);
    case ProgressPeriod.year:
      final daysInPrevMonth = DateTime(prev.start.year, today.month + 1, 0).day;
      prevEnd = DateTime(prev.start.year, today.month, (today.day < daysInPrevMonth ? today.day : daysInPrevMonth) + 1);
  }
  if (prevEnd.isAfter(prev.end)) prevEnd = prev.end;
  return Coverage(currentEnd: tomorrow, previous: prev, previousEnd: prevEnd, ongoing: true);
}

/// "Oct 12 – 18, 2026" / "Sep 28 – Oct 4, 2026" / "Dec 29, 2025 – Jan 4, 2026" / "October 2026" / "2026".
String periodLabel(PeriodRange r) {
  switch (r.period) {
    case ProgressPeriod.week:
      final s = r.start;
      final e = DateTime(r.end.year, r.end.month, r.end.day - 1);
      if (s.year != e.year) return '${AppDates.monthDayYear(s)} – ${AppDates.monthDayYear(e)}';
      // Dạng gọn "Oct 12 – 18, 2026" chỉ đúng thứ tự trong tiếng Anh; ngôn ngữ khác ghi đủ hai đầu theo skeleton.
      if (s.month != e.month || !appDateLocale.startsWith('en')) return '${AppDates.monthDay(s)} – ${AppDates.monthDayYear(e)}';
      return '${AppDates.monthDay(s)} – ${e.day}, ${e.year}';
    case ProgressPeriod.month:
      return AppDates.monthYear(r.start);
    case ProgressPeriod.year:
      return '${r.start.year}';
  }
}

/// Nhãn ngắn cho trục cột.
String bucketLabel(ProgressPeriod p, PeriodBucket b) => switch (p) {
  ProgressPeriod.week => DateFormat.E(appDateLocale).format(b.start),
  ProgressPeriod.month => '${b.start.day}',
  ProgressPeriod.year => DateFormat.MMM(appDateLocale).format(b.start).substring(0, 1),
};

/// Nhãn đầy đủ cho tooltip / danh sách thay thế.
String bucketLongLabel(ProgressPeriod p, PeriodBucket b) => switch (p) {
  ProgressPeriod.year => AppDates.monthYear(b.start),
  _ => AppDates.shortWeekdayDate(b.start),
};

String periodNoun(ProgressPeriod p) => switch (p) {
  ProgressPeriod.week => 'model_period_week'.tr,
  ProgressPeriod.month => 'model_period_month'.tr,
  ProgressPeriod.year => 'model_period_year'.tr,
};
