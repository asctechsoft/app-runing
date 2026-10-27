import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/data_models/activity.dart';
import '../../models/data_models/steps.dart';
import '../../services/application/step_source_priority.dart';
import '../../utils/calc/group_eligibility.dart';
import '../../utils/calc/step_aggregate.dart';
import '../../utils/calc/streak.dart';
import '../../utils/clock.dart';
import '../providers.dart';
import '../steps/steps_providers.dart';
import 'home_logic.dart';

/// Hoạt động đã lưu gần nhất (dữ liệu thật, không fixture).
final homeLatestActivityProvider = FutureProvider.autoDispose<Activity?>((ref) async {
  ref.watch(activityRevisionProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  return ref.read(activityRepositoryProvider).latest(owner);
});

/// Chuỗi tuần hiện tại theo weekStart trong settings.
final homeWeekStreakProvider = FutureProvider.autoDispose<WeekStreak>((ref) async {
  ref.watch(stepRevisionProvider);
  final settings = await ref.watch(settingsProvider.future);
  final owner = ref.watch(ownerProvider).ownerId;
  final perm = await ref.watch(stepsMotionPermissionProvider.future);
  final priority = await ref.watch(stepsSourcePriorityProvider.future);
  final repo = ref.read(stepRepositoryProvider);
  final today = ref.read(clockProvider).nowLocal();
  final start = startOfWeek(today, settings.weekStart);
  final days = <String, StepDay>{};
  for (var i = 0; i < 7; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    if (d.isAfter(today)) break;
    days[localDateKey(d)] = await repo.day(owner, d, hasPermission: isMotionGranted(perm), priority: priority);
  }
  final goals = await ref.read(settingsRepositoryProvider).goals(owner);
  final acts = await ref
      .read(activityRepositoryProvider)
      .allInRange(owner, start.subtract(const Duration(days: 1)).millisecondsSinceEpoch, today.add(const Duration(days: 1)).millisecondsSinceEpoch);
  final activityDays = {for (final a in acts.where(isStreakEligible)) localDateKeyFor(a.startedAt, a.tzOffsetMin)};
  return computeWeekStreak(today: today, weekStart: settings.weekStart, days: days, goals: goals, activityDays: activityDays);
});

/// Chuỗi cá nhân hiện tại + dài nhất (TM20), tính lại hoàn toàn từ dữ liệu cục bộ nên chạy được offline và tự đúng khi
/// hoạt động/mẫu bước bị sửa, xóa hay đồng bộ trễ.
final personalStreakProvider = FutureProvider.autoDispose<StreakSummary>((ref) async {
  ref.watch(stepRevisionProvider);
  ref.watch(activityRevisionProvider);
  ref.watch(ownerProvider);
  // Tính lại khi quyền chuyển động hoặc ưu tiên nguồn bước đổi.
  await ref.watch(stepsMotionPermissionProvider.future);
  await ref.watch(stepsSourcePriorityProvider.future);
  final today = ref.read(clockProvider).nowLocal();
  final (achieved, _) = await loadAchievedDays(ref, historyDays: streakHistoryDays);
  return computeStreak(today: today, achieved: achieved);
});

/// Ngày đạt (TM20) + hoạt động trong [historyDays] ngày gần nhất tới hết hôm nay, từ dữ liệu cục bộ. Dùng cho chuỗi cá nhân
/// và số liệu nhóm (TM21/TM22).
Future<(Set<String>, List<Activity>)> loadAchievedDays(Ref ref, {required int historyDays}) async {
  final owner = ref.read(ownerProvider).ownerId;
  final perm = await ref.read(stepsMotionPermissionProvider.future);
  final priority = await ref.read(stepsSourcePriorityProvider.future);
  final today = ref.read(clockProvider).nowLocal();
  final from = DateTime(today.year, today.month, today.day - historyDays);
  final to = DateTime(today.year, today.month, today.day + 1);
  final samples = await ref.read(stepRepositoryProvider).samplesBetween(owner, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
  // Gom mẫu theo ngày địa phương (mẫu qua nửa đêm thuộc cả hai ngày; aggregateDay tự chia theo giờ).
  final byDay = <String, List<StepSample>>{};
  for (final s in samples) {
    final a = DateTime.fromMillisecondsSinceEpoch(s.startAt);
    final b = DateTime.fromMillisecondsSinceEpoch(s.endAt - 1);
    for (var d = DateTime(a.year, a.month, a.day); !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1)) {
      (byDay[localDateKey(d)] ??= []).add(s);
    }
  }
  final days = [
    for (final e in byDay.entries)
      aggregateDay(
        dateKey: e.key,
        samples: e.value,
        offsetMin: parseDateKey(e.key).timeZoneOffset.inMinutes,
        hasPermission: isMotionGranted(perm),
        priority: priority,
      ),
  ];
  final goals = await ref.read(settingsRepositoryProvider).goals(owner);
  final acts = await ref
      .read(activityRepositoryProvider)
      .allInRange(owner, from.subtract(const Duration(days: 1)).millisecondsSinceEpoch, to.millisecondsSinceEpoch);
  return (achievedDayKeys(days: days, goals: goals, activities: acts), acts);
}
