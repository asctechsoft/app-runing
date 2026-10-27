import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/explore/group_sharing.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/calc/group_stats.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenges_screen.dart';
import 'components/explore_widgets.dart';

ChallengeTarget _asTarget(GroupGoalMetric m) => ChallengeTarget.values.byName(m.name);

/// Tab "Group" của club (TM21 chuỗi nhóm, TM22 mục tiêu nhóm). Chỉ tính người tự bật chia sẻ (TM60); hôm nay chỉ hiện
/// số người đã xong, không nêu tên (tránh áp lực).
class ClubGroupTab extends ConsumerStatefulWidget {
  const ClubGroupTab({super.key, required this.club, required this.canManage, this.onGoalChanged});
  final Club club;
  final bool canManage;

  /// Mục tiêu vừa đổi → màn cha tải lại club.
  final VoidCallback? onGoalChanged;

  @override
  ConsumerState<ClubGroupTab> createState() => _ClubGroupTabState();
}

class _ClubGroupTabState extends ConsumerState<ClubGroupTab> {
  List<MemberStats>? _members;
  bool? _sharing;
  ExploreFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final sharing = (await ref.read(groupSharingProvider).clubs()).contains(widget.club.id);
      final members = await ref.read(exploreRepositoryProvider).clubMemberStats(widget.club.id);
      if (mounted) {
        setState(() {
          _sharing = sharing;
          _members = members;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(groupSharingProvider).set(widget.club.id, on);
      if (!mounted) return;
      showStrideSnack(context, on ? 'explore_group_share_on'.tr : 'explore_group_share_off'.tr);
      await _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editGoal() async {
    final saved = await showStrideSheet<bool>(
      context,
      title: 'explore_group_goal_set'.tr,
      builder: (_) => _GoalForm(club: widget.club),
    );
    if (saved == true) widget.onGoalChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final members = _members;
    if (members == null) return const Column(children: [LoadingCard(), Gap(12), LoadingCard()]);
    final today = ref.watch(clockProvider).nowLocal();
    final fmt = ref.watch(formatProvider);
    final streak = computeGroupStreak(members, today);
    final goal = widget.club.groupGoal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StrideCard(
          child: SwitchListTile(
            key: const Key('group-share'),
            contentPadding: EdgeInsets.zero,
            value: _sharing ?? false,
            onChanged: _busy ? null : _toggle,
            title: Text('explore_group_share_title'.tr, style: StrideText.body),
            subtitle: Text('explore_group_share_note'.tr, style: StrideText.caption),
          ),
        ),
        const Gap(12),
        StrideCard(
          key: const Key('group-streak'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department_outlined, color: StrideColors.primary),
                  const SizedBox(width: StrideSpace.s8),
                  Expanded(
                    child: Text(
                      streak.summary.current > 0
                          ? 'explore_group_streak'.trPlural(streak.summary.current, [streak.summary.current])
                          : 'explore_group_streak_none'.tr,
                      style: StrideText.heading.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ),
              const Gap(StrideSpace.s4),
              if (streak.members == 0)
                Text('explore_group_nobody_sharing'.tr, style: StrideText.caption)
              else
                Text('explore_group_today_done'.trArgs([streak.doneToday, streak.members]), style: StrideText.caption),
              Text('explore_group_streak_rule'.tr, style: StrideText.caption),
            ],
          ),
        ),
        const Gap(12),
        StrideCard(
          key: const Key('group-goal'),
          child: goal == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('explore_group_goal_none'.tr, style: StrideText.subheading),
                    Text(widget.canManage ? 'explore_group_goal_none_manager'.tr : 'explore_group_goal_none_member'.tr, style: StrideText.caption),
                    if (widget.canManage) ...[
                      const Gap(8),
                      OutlineButton(key: const Key('group-goal-edit'), label: 'explore_group_goal_set'.tr, onPressed: _editGoal),
                    ],
                  ],
                )
              : _GoalProgress(goal: goal, progress: computeGroupGoalProgress(goal, members, today), fmt: fmt, onEdit: widget.canManage ? _editGoal : null),
        ),
      ],
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.goal, required this.progress, required this.fmt, this.onEdit});
  final GroupGoal goal;
  final GroupGoalProgress progress;
  final StrideFormat fmt;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = _asTarget(goal.metric);
    final ratio = (progress.total / goal.target).clamp(0.0, 1.0);
    final done = progress.total >= goal.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                (goal.period == GroupGoalPeriod.week ? 'explore_group_goal_week' : 'explore_group_goal_month').trArgs([challengeValue(t, goal.target, fmt)]),
                style: StrideText.subheading,
              ),
            ),
            if (onEdit != null) TextButton(key: const Key('group-goal-edit'), onPressed: onEdit, child: Text('explore_club_edit'.tr)),
          ],
        ),
        const Gap(4),
        Text('explore_progress_of'.trArgs([challengeValue(t, progress.total, fmt), challengeValue(t, goal.target, fmt)]), style: StrideText.metricSmall),
        const Gap(8),
        Semantics(
          label: done ? 'explore_completed'.tr : 'explore_percent_complete'.trArgs([(ratio * 100).floor()]),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(StrideRadius.pill),
            child: LinearProgressIndicator(value: ratio, minHeight: 8, color: StrideColors.primary, backgroundColor: StrideColors.subtle),
          ),
        ),
        if (done) ...[const Gap(8), Text('explore_group_goal_reached'.tr, style: StrideText.label.copyWith(color: StrideColors.primary))],
        if (progress.byMember.isNotEmpty) ...[
          const Gap(12),
          Text('explore_group_contributions'.tr, style: StrideText.label),
          for (final (id, name, v) in progress.byMember)
            Padding(
              key: Key('contribution-$id'),
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(child: Text(name.trim().isEmpty ? 'explore_event_attendee_unnamed'.tr : name, style: StrideText.body)),
                  Text(challengeValue(t, v, fmt), style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
        ],
        const Gap(8),
        Text('explore_group_goal_note'.tr, style: StrideText.caption),
      ],
    );
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({required this.club});
  final Club club;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late GroupGoalPeriod _period = widget.club.groupGoal?.period ?? GroupGoalPeriod.week;
  late GroupGoalMetric _metric = widget.club.groupGoal?.metric ?? GroupGoalMetric.distance;
  final _target = TextEditingController();
  bool _busy = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final g = widget.club.groupGoal;
    if (g != null) _target.text = _toInput(g.target, g.metric);
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  StrideFormat get _fmt => ref.read(formatProvider);

  String _toInput(double v, GroupGoalMetric m) {
    final x = switch (m) {
      GroupGoalMetric.distance => _fmt.metersToUnit(v),
      GroupGoalMetric.count => v,
      GroupGoalMetric.time => v / 3600 / 1000,
    };
    return x == x.roundToDouble() ? x.round().toString() : x.toStringAsFixed(1);
  }

  double? get _base {
    final v = double.tryParse(_target.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return switch (_metric) {
      GroupGoalMetric.distance => _fmt.unitToMeters(v),
      GroupGoalMetric.count => v.roundToDouble(),
      GroupGoalMetric.time => v * 3600 * 1000,
    };
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy) return;
    setState(() => _submitted = true);
    final base = _base;
    if (!remove && base == null) return;
    setState(() => _busy = true);
    try {
      final weekStart = ref.read(settingsProvider).value?.weekStart ?? DateTime.monday;
      await ref
          .read(exploreRepositoryProvider)
          .setGroupGoal(widget.club.id, remove ? null : GroupGoal(period: _period, metric: _metric, target: base!, weekStart: weekStart));
      if (!mounted) return;
      showStrideSnack(context, remove ? 'explore_group_goal_removed'.tr : 'explore_group_goal_saved'.tr);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StrideSegmented<GroupGoalPeriod>(
        values: GroupGoalPeriod.values,
        selected: _period,
        labelOf: (p) => p == GroupGoalPeriod.week ? 'explore_group_period_week'.tr : 'explore_group_period_month'.tr,
        onChanged: (p) => setState(() => _period = p),
      ),
      const Gap(12),
      StrideSegmented<GroupGoalMetric>(
        values: GroupGoalMetric.values,
        selected: _metric,
        labelOf: (m) => switch (m) {
          GroupGoalMetric.distance => 'explore_challenge_metric_distance'.tr,
          GroupGoalMetric.count => 'explore_challenge_metric_count'.tr,
          GroupGoalMetric.time => 'explore_challenge_metric_time'.tr,
        },
        onChanged: (m) => setState(() {
          _metric = m;
          _target.clear();
        }),
      ),
      const Gap(12),
      TextField(
        key: const Key('group-goal-target'),
        controller: _target,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'explore_challenge_target_label'.tr,
          suffixText: switch (_metric) {
            GroupGoalMetric.distance => _fmt.distanceUnitLabel,
            GroupGoalMetric.count => 'explore_challenge_unit_runs'.tr,
            GroupGoalMetric.time => 'explore_challenge_unit_hours'.tr,
          },
          errorText: _submitted && _base == null ? 'explore_challenge_err_target'.tr : null,
        ),
      ),
      const Gap(16),
      PrimaryButton(key: const Key('group-goal-save'), label: 'explore_club_save'.tr, loading: _busy, onPressed: _busy ? null : _save),
      if (widget.club.groupGoal != null) ...[
        const Gap(8),
        TextButton(onPressed: _busy ? null : () => _save(remove: true), child: Text('explore_group_goal_remove'.tr)),
      ],
    ],
  );
}
