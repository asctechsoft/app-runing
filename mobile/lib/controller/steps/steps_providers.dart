import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/native/permission_coordinator.dart';
import '../providers.dart';
import '../../utils/clock.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/steps.dart';
import '../../services/application/step_source_priority.dart';
import 'steps_logic.dart';

/// Quyền motion hiện tại; kiểm tra lại mỗi khi coordinator báo đổi (resume app, sau khi xin quyền).
final stepsMotionPermissionProvider = StreamProvider<PermStatus>((ref) async* {
  final perms = ref.watch(permissionsProvider);
  yield await perms.status(PermKind.motion);
  await for (final _ in perms.changes) {
    yield await perms.status(PermKind.motion);
  }
});

bool isMotionGranted(PermStatus s) => s == PermStatus.granted || s == PermStatus.limited;

/// Dữ liệu bước của một ngày + mục tiêu áp dụng cho chính ngày đó (goal history).
class StepsDayView {
  const StepsDayView({required this.day, required this.permission, required this.goal, required this.checkedAt, required this.activeMinutes});

  final StepDay day;
  final PermStatus permission;

  /// Mục tiêu bước của ngày (null = chưa đặt mục tiêu).
  final int? goal;

  /// Thời điểm app đọc dữ liệu (UTC ms) — "Last checked".
  final int checkedAt;
  final int? activeMinutes;
}

/// [dateKey] = YYYY-MM-DD địa phương.
final stepsDayProvider = FutureProvider.autoDispose.family<StepsDayView, String>((ref, dateKey) async {
  ref.watch(stepRevisionProvider);
  ref.watch(settingsProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final perm = await ref.watch(stepsMotionPermissionProvider.future);
  final priority = await ref.watch(stepsSourcePriorityProvider.future);
  final repo = ref.read(stepRepositoryProvider);
  final settingsRepo = ref.read(settingsRepositoryProvider);
  final date = parseDateKey(dateKey);
  final day = await repo.day(owner, date, hasPermission: isMotionGranted(perm), priority: priority);
  final goals = await settingsRepo.goals(owner);
  final goal = goalForDate(goals, GoalType.dailySteps, dateKey)?.value.round();
  int? active;
  if (day.hasValue) {
    final from = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final to = DateTime(date.year, date.month, date.day + 1).millisecondsSinceEpoch;
    final samples = await repo.samplesBetween(owner, from, to);
    active = activeMinutesFromSamples(samples, fromMs: from, toMs: to, source: day.sourceUsed);
  }
  return StepsDayView(day: day, permission: perm, goal: goal, checkedAt: ref.read(clockProvider).nowMs(), activeMinutes: active);
});
