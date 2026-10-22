import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../../utils/clock.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/steps.dart';
import '../../services/application/step_source_priority.dart';
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
  return computeWeekStreak(today: today, weekStart: settings.weekStart, days: days, goals: goals);
});
