import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../utils/logger.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../models/ui_models/workout_models.dart';
import '../../repository/workout_repository.dart';

const _stepMs = 30000;
const _maxStepMs = 120 * 60000;

IconData _iconFor(IntervalKind k) => switch (k) {
  IntervalKind.warmup => Icons.wb_sunny_outlined,
  IntervalKind.run => Icons.directions_run,
  IntervalKind.walk => Icons.directions_walk,
  IntervalKind.rest => Icons.self_improvement,
  IntervalKind.cooldown => Icons.ac_unit,
  IntervalKind.repeat => Icons.repeat,
};

/// Interval editor (K01) theo mockup "Interval workout". Sửa không bao giờ bắt đầu ghi;
/// Start workout chỉ chọn giáo án rồi quay về màn chuẩn bị.
class IntervalEditorScreen extends ConsumerStatefulWidget {
  const IntervalEditorScreen({super.key, this.planId});
  final String? planId;

  @override
  ConsumerState<IntervalEditorScreen> createState() => _IntervalEditorScreenState();
}

class _IntervalEditorScreenState extends ConsumerState<IntervalEditorScreen> {
  WorkoutPlan? _plan;
  bool _loading = true;
  bool _notFound = false;
  final _saveGuard = OnceGuard();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.planId;
    if (id == null) {
      final current = ref.read(runSessionProvider).setup.plan;
      setState(() {
        _plan = current ?? WorkoutPlan.starter();
        _loading = false;
      });
      return;
    }
    try {
      final p = await ref.read(workoutRepositoryProvider).plan(ref.read(ownerProvider).ownerId, id);
      if (!mounted) return;
      setState(() {
        _plan = p;
        _notFound = p == null;
        _loading = false;
      });
    } catch (e, st) {
      StrideLog.e('workout.load', e, st);
      if (mounted) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
      }
    }
  }

  void _setSteps(List<IntervalStep> steps) => setState(() => _plan = _plan!.copyWith(steps: steps));

  // --------- Sửa bước ---------

  Future<void> _editStep({required int index, int? childIndex}) async {
    final steps = List.of(_plan!.steps);
    final parent = steps[index];
    final step = childIndex == null ? parent : parent.children[childIndex];
    final siblings = childIndex == null ? steps.length : parent.children.length;
    final pos = childIndex ?? index;
    final result = await showStrideSheet<_StepEdit>(
      context,
      title: step.isRepeat ? 'Repeat block' : intervalKindLabel(step.kind),
      builder: (ctx) => _StepEditor(step: step, canMoveUp: pos > 0, canMoveDown: pos < siblings - 1, allowKindChange: childIndex != null),
    );
    if (result == null) return;
    List<IntervalStep> apply(List<IntervalStep> list, int i) {
      final l = List.of(list);
      switch (result.action) {
        case _EditAction.remove:
          l.removeAt(i);
        case _EditAction.moveUp:
          l.insert(i - 1, l.removeAt(i));
        case _EditAction.moveDown:
          l.insert(i + 1, l.removeAt(i));
        case _EditAction.update:
          l[i] = result.step!;
      }
      return l;
    }

    if (childIndex == null) {
      _setSteps(apply(steps, index));
    } else {
      final children = apply(parent.children, childIndex);
      steps[index] = parent.copyWith(children: children);
      _setSteps(steps);
    }
  }

  Future<void> _addTopLevel() async {
    final kind = await showStrideSheet<IntervalKind>(
      context,
      title: 'Add step',
      builder: (ctx) => Column(
        children: [
          for (final k in IntervalKind.values)
            SettingsRow(
              icon: _iconFor(k),
              title: k == IntervalKind.repeat ? 'Repeat block' : intervalKindLabel(k),
              subtitle: k == IntervalKind.repeat ? 'Repeat a set of intervals' : intervalKindHint(k),
              onTap: () => Navigator.of(ctx).pop(k),
            ),
        ],
      ),
    );
    if (kind == null) return;
    final steps = List.of(_plan!.steps);
    final newStep = kind == IntervalKind.repeat
        ? IntervalStep(
            kind: IntervalKind.repeat,
            repeat: 4,
            children: [
              IntervalStep(kind: IntervalKind.run, durationMs: 60000),
              IntervalStep(kind: IntervalKind.walk, durationMs: 60000),
            ],
          )
        : IntervalStep(kind: kind, durationMs: kind == IntervalKind.warmup || kind == IntervalKind.cooldown ? 5 * 60000 : 60000);
    // Thêm trước cool-down nếu cool-down đang ở cuối.
    final insertAt = steps.isNotEmpty && steps.last.kind == IntervalKind.cooldown && kind != IntervalKind.cooldown ? steps.length - 1 : steps.length;
    steps.insert(insertAt, newStep);
    _setSteps(steps);
  }

  void _addChild(int index) {
    final steps = List.of(_plan!.steps);
    final parent = steps[index];
    final last = parent.children.isEmpty ? IntervalKind.walk : parent.children.last.kind;
    final kind = last == IntervalKind.run ? IntervalKind.walk : IntervalKind.run;
    steps[index] = parent.copyWith(
      children: [
        ...parent.children,
        IntervalStep(kind: kind, durationMs: 60000),
      ],
    );
    _setSteps(steps);
  }

  String? _validate() {
    final p = _plan!;
    if (p.steps.isEmpty) return 'Add at least one step.';
    if (p.totalMs <= 0) return 'Your workout needs at least one timed step.';
    for (final s in p.steps) {
      if (s.isRepeat && s.children.isEmpty) return 'Each repeat block needs at least one interval.';
    }
    return null;
  }

  Future<void> _savePreset() => _saveGuard.run(() async {
    final err = _validate();
    if (err != null) {
      showStrideSnack(context, err, isError: true);
      return;
    }
    final ctrl = TextEditingController(text: _plan!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as preset'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Preset name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final saved = await ref.read(workoutRepositoryProvider).savePlan(ref.read(ownerProvider).ownerId, _plan!.copyWith(name: name));
      if (!mounted) return;
      setState(() => _plan = saved);
      ref.invalidate(workoutPlansProvider);
      showStrideSnack(context, 'Preset saved.');
    } catch (e, st) {
      StrideLog.e('workout.save', e, st);
      if (mounted) showStrideSnack(context, 'Couldn\'t save the preset. Try again.', actionLabel: 'Retry', onAction: _savePreset, isError: true);
    }
  });

  void _startWorkout() {
    final err = _validate();
    if (err != null) {
      showStrideSnack(context, err, isError: true);
      return;
    }
    // Chỉ chọn giáo án — ghi chỉ bắt đầu khi người dùng bấm Start ở màn chuẩn bị.
    ref.read(runSessionProvider.notifier).setPlan(_plan);
    context.go(Routes.run);
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    if (!flags.workoutIntervals) {
      return StrideScreen(
        title: 'Intervals',
        body: EmptyState(title: 'Intervals aren\'t available', message: 'Interval workouts are turned off in this version.', icon: Icons.timer_off_outlined),
      );
    }
    if (_loading) return const StrideScreen(title: 'Interval workout', body: LoadingCard(height: 300));
    if (_notFound || _plan == null) {
      return StrideScreen(
        title: 'Interval workout',
        body: EmptyState(
          title: 'Preset not found',
          message: 'This preset may have been deleted.',
          icon: Icons.search_off,
          actionLabel: 'Build a new workout',
          onAction: () => context.go(Routes.runIntervals),
        ),
      );
    }
    final plan = _plan!;
    final steps = plan.steps;
    return StrideScreen(
      title: 'Build a workout',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name, style: StrideText.title),
                    Text('A mix of running and walking to build endurance.', style: StrideText.bodySecondary),
                  ],
                ),
              ),
              const IconBadge(icon: Icons.directions_run, size: 48),
            ],
          ),
          const SizedBox(height: 16),
          StrideCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: MetricTile(label: 'Total time', value: formatStepDuration(plan.totalMs), icon: Icons.schedule, center: true),
                ),
                Expanded(
                  child: MetricTile(label: 'Intervals', value: '${plan.intervalCount}', icon: Icons.repeat, center: true),
                ),
                Expanded(
                  child: MetricTile(label: 'Phases', value: '${plan.phases.length}', icon: Icons.format_list_numbered, center: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Workout plan', style: StrideText.subheading)),
              const Icon(Icons.graphic_eq, size: 18, color: StrideColors.primary),
              const SizedBox(width: 4),
              Text('Audio cues', style: StrideText.label.copyWith(color: StrideColors.primary)),
              Switch(
                value: plan.audioCues,
                onChanged: (v) => setState(() => _plan = plan.copyWith(audioCues: v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (steps.isEmpty)
            const EmptyState(title: 'No steps yet', message: 'Add a warm-up, intervals and a cool-down.', icon: Icons.add_task)
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: steps.length,
              onReorder: (from, to) {
                final l = List.of(steps);
                final item = l.removeAt(from);
                l.insert(to > from ? to - 1 : to, item);
                _setSteps(l);
              },
              itemBuilder: (context, i) {
                final s = steps[i];
                return Padding(
                  key: ValueKey(s.key),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StrideCard(
                    padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                    child: Column(
                      children: [
                        _StepRow(
                          step: s,
                          dragHandle: ReorderableDragStartListener(
                            index: i,
                            child: const SizedBox(
                              width: 40,
                              height: 48,
                              child: Icon(Icons.drag_indicator, color: StrideColors.textMuted, semanticLabel: 'Drag to reorder'),
                            ),
                          ),
                          onTap: () => _editStep(index: i),
                        ),
                        if (s.isRepeat) ...[
                          for (var c = 0; c < s.children.length; c++)
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: _StepRow(
                                step: s.children[c],
                                onTap: () => _editStep(index: i, childIndex: c),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 32),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                              onPressed: () => _addChild(i),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Add interval'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          OutlineButton(label: 'Add step', icon: Icons.add, onPressed: _addTopLevel),
          const SizedBox(height: 16),
          SageCard(
            child: Semantics(
              label: 'Total time ${formatStepDuration(plan.totalMs)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: StrideColors.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Total time', style: StrideText.body)),
                  Text(formatStepDuration(plan.totalMs), style: StrideText.metricSmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlineButton(label: plan.id == null ? 'Save as preset' : 'Update preset', icon: Icons.bookmark_add_outlined, onPressed: _savePreset),
        ],
      ),
      bottom: PrimaryButton(label: 'Start workout', trailingIcon: Icons.arrow_forward, onPressed: _startWorkout),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.onTap, this.dragHandle});
  final IntervalStep step;
  final VoidCallback onTap;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final title = step.isRepeat ? 'Repeat ${step.repeat} times' : intervalKindLabel(step.kind);
    final trailing = step.isRepeat ? formatStepDuration(planTotalMs([step])) : formatStepDuration(step.durationMs ?? 0);
    return Semantics(
      button: true,
      label: '$title, $trailing. Tap to edit',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StrideRadius.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              dragHandle ?? const SizedBox(width: 8),
              IconBadge(icon: _iconFor(step.kind), size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: StrideText.label.copyWith(fontSize: 16)),
                    if (!step.isRepeat) Text(intervalKindHint(step.kind), style: StrideText.caption),
                  ],
                ),
              ),
              Text(trailing, style: StrideText.metricSmall.copyWith(fontSize: 16)),
              const Icon(Icons.chevron_right, size: 20, color: StrideColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EditAction { update, remove, moveUp, moveDown }

class _StepEdit {
  const _StepEdit(this.action, [this.step]);
  final _EditAction action;
  final IntervalStep? step;
}

class _StepEditor extends StatefulWidget {
  const _StepEditor({required this.step, required this.canMoveUp, required this.canMoveDown, required this.allowKindChange});
  final IntervalStep step;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool allowKindChange;

  @override
  State<_StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<_StepEditor> {
  late IntervalKind _kind = widget.step.kind;
  late int _ms = widget.step.durationMs ?? 60000;
  late int _repeat = widget.step.repeat;

  @override
  Widget build(BuildContext context) {
    final repeat = widget.step.isRepeat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowKindChange) ...[
          StrideSegmented<IntervalKind>(
            values: const [IntervalKind.run, IntervalKind.walk, IntervalKind.rest],
            selected: _kind,
            labelOf: intervalKindLabel,
            onChanged: (k) => setState(() => _kind = k),
          ),
          const SizedBox(height: 16),
        ],
        if (repeat)
          ValueStepper(
            valueText: '$_repeat',
            unitLabel: 'times',
            semanticLabel: 'Repeats',
            onDecrement: _repeat > 1 ? () => setState(() => _repeat--) : null,
            onIncrement: _repeat < 50 ? () => setState(() => _repeat++) : null,
          )
        else
          ValueStepper(
            valueText: formatStepDuration(_ms),
            unitLabel: 'duration',
            semanticLabel: 'Duration',
            onDecrement: _ms > _stepMs ? () => setState(() => _ms -= _stepMs) : null,
            onIncrement: _ms < _maxStepMs ? () => setState(() => _ms += _stepMs) : null,
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (widget.canMoveUp)
              Expanded(
                child: OutlineButton(
                  label: 'Move up',
                  icon: Icons.arrow_upward,
                  onPressed: () => Navigator.of(context).pop(const _StepEdit(_EditAction.moveUp)),
                ),
              ),
            if (widget.canMoveUp && widget.canMoveDown) const SizedBox(width: 8),
            if (widget.canMoveDown)
              Expanded(
                child: OutlineButton(
                  label: 'Move down',
                  icon: Icons.arrow_downward,
                  onPressed: () => Navigator.of(context).pop(const _StepEdit(_EditAction.moveDown)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Done',
          onPressed: () =>
              Navigator.of(context)
                  .pop(_StepEdit(_EditAction.update, repeat ? widget.step.copyWith(repeat: _repeat) : widget.step.copyWith(kind: _kind, durationMs: _ms))),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: StrideColors.error, minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(const _StepEdit(_EditAction.remove)),
          child: Text(repeat ? 'Remove repeat block' : 'Remove step'),
        ),
      ],
    );
  }
}
