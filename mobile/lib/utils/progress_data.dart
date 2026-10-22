import 'clock.dart';
import 'l10n.dart';
import '../repository/activity_repository.dart';
import '../repository/settings_repository.dart';
import '../repository/step_repository.dart';
import 'calc/run_metrics.dart';
import 'calc/step_aggregate.dart';
import '../models/data_models/activity.dart';
import '../models/data_models/profile.dart';
import '../models/data_models/steps.dart';
import '../models/ui_models/period.dart';

/// Nhãn Week/Month/Year cho phân đoạn chọn kỳ.
String periodSegmentLabel(ProgressPeriod p) => switch (p) {
  ProgressPeriod.week => 'progress_period_week'.tr,
  ProgressPeriod.month => 'progress_period_month'.tr,
  ProgressPeriod.year => 'progress_period_year'.tr,
};

/// Danh từ của kỳ (tuần/tháng/năm) để ghép vào câu có placeholder.
String periodNounText(ProgressPeriod p) => switch (p) {
  ProgressPeriod.week => 'progress_noun_week'.tr,
  ProgressPeriod.month => 'progress_noun_month'.tr,
  ProgressPeriod.year => 'progress_noun_year'.tr,
};

/// Chọn một trong ba key theo kỳ rồi dịch (kèm [args] nếu có).
String periodTr(ProgressPeriod p, String weekKey, String monthKey, String yearKey, [List<Object?> args = const []]) {
  final key = switch (p) {
    ProgressPeriod.week => weekKey,
    ProgressPeriod.month => monthKey,
    ProgressPeriod.year => yearKey,
  };
  return args.isEmpty ? key.tr : key.trArgs(args);
}

/// Loại tính vào "Running":chạy ngoài trời + chạy trong nhà (không gồm đi bộ).
Set<ActivityType> runningTypes({required bool indoor}) => {ActivityType.run, if (indoor) ActivityType.indoorRun};

/// Hệ số quy đổi mục tiêu tuần sang tháng/năm — chỉ là "target" ước lượng, ghi rõ trên UI.
const double weeksPerMonth = 4.345;
const double weeksPerYear = 52;

/// Pace kỳ = tổng moving time / tổng quãng đường GPS (không lấy trung bình cộng pace từng buổi).
double? periodPaceSecPerKm(ActivityTotals t) => avgPaceSecPerKm(movingMs: t.gpsMovingMs, distanceM: t.gpsDistanceM);

/// Mục tiêu quãng đường cho kỳ từ GoalVersion weeklyDistanceM áp dụng tại ngày cuối đã qua của kỳ.
double? periodDistanceTarget(List<GoalVersion> goals, PeriodRange r, DateTime now) {
  final lastDay = DateTime(r.end.year, r.end.month, r.end.day - 1);
  final ref = lastDay.isAfter(now) ? dayOnly(now) : lastDay;
  final g = goalForDate(goals, GoalType.weeklyDistanceM, localDateKey(ref));
  if (g == null || g.value <= 0) return null;
  return switch (r.period) {
    ProgressPeriod.week => g.value,
    ProgressPeriod.month => g.value * weeksPerMonth,
    ProgressPeriod.year => g.value * weeksPerYear,
  };
}

class BucketValue {
  const BucketValue({required this.bucket, required this.value, required this.count, required this.future});
  final PeriodBucket bucket;

  /// Running: mét; Steps: bước. null = không có dữ liệu (khác 0 thật).
  final double? value;
  final int count;
  final bool future;
}

class PeriodComparison {
  const PeriodComparison({required this.current, required this.previous, required this.coverage});
  final ActivityTotals current;
  final ActivityTotals previous;
  final Coverage coverage;
  double get deltaDistanceM => current.distanceM - previous.distanceM;
}

class RunningSummary {
  const RunningSummary({
    required this.range,
    required this.totals,
    required this.buckets,
    required this.recent,
    required this.target,
    required this.comparison,
  });

  final PeriodRange range;
  final ActivityTotals totals;
  final List<BucketValue> buckets;

  /// 3 buổi mới nhất trong kỳ.
  final List<Activity> recent;
  final double? target;
  final PeriodComparison? comparison;

  double? get paceSecPerKm => periodPaceSecPerKm(totals);
}

/// Tổng và biểu đồ lấy từ cùng một query (I04: tổng/chart cùng data set).
Future<RunningSummary> loadRunningSummary({
  required ActivityRepository activities,
  required SettingsRepository settings,
  required String ownerId,
  required PeriodRange range,
  required DateTime now,
  required Set<ActivityType> types,
  required int weekStart,
}) async {
  final q = ActivityQuery(ownerId: ownerId, types: types, fromMs: range.fromMs, toMs: range.toMs, limit: 100000);
  final totals = await activities.totals(q);
  final list = await activities.list(q);
  final buckets = bucketsFor(range);
  final sums = List<double>.filled(buckets.length, 0);
  final counts = List<int>.filled(buckets.length, 0);
  for (final a in list) {
    final i = bucketIndexOf(buckets, DateTime.fromMillisecondsSinceEpoch(a.startedAt));
    if (i < 0) continue;
    sums[i] += a.distanceM ?? 0;
    counts[i]++;
  }
  final today = dayOnly(now);
  final values = [
    for (var i = 0; i < buckets.length; i++)
      BucketValue(bucket: buckets[i], value: buckets[i].start.isAfter(today) ? null : sums[i], count: counts[i], future: buckets[i].start.isAfter(today)),
  ];
  final goals = await settings.goals(ownerId);
  final target = periodDistanceTarget(goals, range, now);

  PeriodComparison? comparison;
  if (!range.start.isAfter(today)) {
    final cov = comparableCoverage(range, now, weekStart);
    final cur = cov.ongoing
        ? await activities.totals(ActivityQuery(ownerId: ownerId, types: types, fromMs: range.fromMs, toMs: cov.currentEnd.millisecondsSinceEpoch))
        : totals;
    final prev = await activities.totals(
      ActivityQuery(ownerId: ownerId, types: types, fromMs: cov.previous.fromMs, toMs: cov.previousEnd.millisecondsSinceEpoch),
    );
    comparison = PeriodComparison(current: cur, previous: prev, coverage: cov);
  }
  return RunningSummary(range: range, totals: totals, buckets: values, recent: list.take(3).toList(), target: target, comparison: comparison);
}

class StepsSummary {
  const StepsSummary({required this.range, required this.days, required this.buckets, required this.dailyGoals, required this.hasPermission});

  final PeriodRange range;

  /// Ngày đã qua/hôm nay trong kỳ (ngày tương lai không có).
  final List<StepDay> days;
  final List<BucketValue> buckets;

  /// dateKey → mục tiêu bước của ngày đó (theo GoalVersion có hiệu lực).
  final Map<String, double> dailyGoals;
  final bool hasPermission;

  List<StepDay> get withData => days.where((d) => d.hasValue).toList();

  /// null khi không ngày nào có dữ liệu (không hiển thị 0 giả).
  int? get totalSteps => withData.isEmpty ? null : withData.fold<int>(0, (a, d) => a + (d.steps ?? 0));
  double? get averagePerDay => withData.isEmpty ? null : totalSteps! / withData.length;

  /// Chỉ đếm ngày có dữ liệu và có mục tiêu.
  int get goalDaysMet => withData.where((d) {
    final g = dailyGoals[d.date];
    return g != null && (d.steps ?? 0) >= g;
  }).length;

  bool get noPermissionAndNoData => !hasPermission && withData.isEmpty;

  /// Nguồn bước của ngày gần nhất có dữ liệu.
  StepSource? get latestSource => withData.isEmpty ? null : withData.last.sourceUsed;

  /// Mục tiêu hiện hành (ngày cuối có trong kỳ) cho đường goal trên biểu đồ ngày.
  double? get currentDailyGoal => days.isEmpty ? null : dailyGoals[days.last.date];
}

Future<StepsSummary> loadStepsSummary({
  required StepRepository steps,
  required SettingsRepository settings,
  required String ownerId,
  required PeriodRange range,
  required DateTime now,
  required bool hasPermission,
}) async {
  final days = range.period == ProgressPeriod.year
      ? await _yearDays(steps, ownerId, range, now, hasPermission)
      : await steps.range(ownerId, range.start, range.end, hasPermission: hasPermission);
  final goals = await settings.goals(ownerId);
  final dailyGoals = <String, double>{};
  for (final d in days) {
    final g = goalForDate(goals, GoalType.dailySteps, d.date);
    if (g != null) dailyGoals[d.date] = g.value;
  }
  final byKey = {for (final d in days) d.date: d};
  final today = dayOnly(now);
  final buckets = <BucketValue>[];
  for (final b in bucketsFor(range)) {
    final future = b.start.isAfter(today);
    if (range.period == ProgressPeriod.year) {
      var sum = 0;
      var n = 0;
      for (final d in days) {
        final dt = parseDateKey(d.date);
        if (b.contains(dt) && d.hasValue) {
          sum += d.steps ?? 0;
          n++;
        }
      }
      buckets.add(BucketValue(bucket: b, value: n == 0 ? null : sum.toDouble(), count: n, future: future));
    } else {
      final d = byKey[localDateKey(b.start)];
      buckets.add(
        BucketValue(bucket: b, value: (d != null && d.hasValue) ? (d.steps ?? 0).toDouble() : null, count: d != null && d.hasValue ? 1 : 0, future: future),
      );
    }
  }
  return StepsSummary(range: range, days: days, buckets: buckets, dailyGoals: dailyGoals, hasPermission: hasPermission);
}

/// Năm: đọc mẫu một lần rồi tổng hợp từng ngày tại chỗ (tránh ~730 truy vấn), cùng quy tắc aggregateDay.
Future<List<StepDay>> _yearDays(StepRepository steps, String ownerId, PeriodRange range, DateTime now, bool hasPermission) async {
  final today = dayOnly(now);
  final endExclusive = DateTime(today.year, today.month, today.day + 1);
  final end = endExclusive.isBefore(range.end) ? endExclusive : range.end;
  if (!range.start.isBefore(end)) return const [];
  final samples = await steps.samplesBetween(ownerId, range.fromMs, end.millisecondsSinceEpoch);
  final out = <StepDay>[];
  for (var d = range.start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final next = DateTime(d.year, d.month, d.day + 1);
    final from = d.millisecondsSinceEpoch;
    final to = next.millisecondsSinceEpoch;
    final daySamples = [
      for (final s in samples)
        if (s.endAt > from && s.startAt < to) s,
    ];
    out.add(aggregateDay(dateKey: localDateKey(d), samples: daySamples, offsetMin: d.timeZoneOffset.inMinutes, hasPermission: hasPermission));
  }
  return out;
}
