import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../../utils/clock.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/profile.dart';
import '../../controller/sync/sync_providers.dart';
import '../../controller/setup/setup_logic.dart';
import 'components/setup_widgets.dart';

const _metersPerMile = 1609.344;

/// Bước 2: mục tiêu bước ngày + mục tiêu chạy tuần (tùy chọn). Lưu GoalVersion có ngày hiệu lực (E04, F06).
class SetupGoalScreen extends ConsumerStatefulWidget {
  const SetupGoalScreen({super.key});

  @override
  ConsumerState<SetupGoalScreen> createState() => _SetupGoalScreenState();
}

class _SetupGoalScreenState extends ConsumerState<SetupGoalScreen> {
  final _guard = OnceGuard();
  int _steps = StepGoalLimits.defaultValue;
  bool _custom = false;
  bool _weekly = false;
  int _runs = 3;
  int _distance = 15; // theo đơn vị hiển thị (km hoặc mi)
  bool _saving = false;
  String? _error;

  final _fmt = NumberFormat.decimalPattern('en_US');

  Future<void> _customSteps() async {
    final controller = TextEditingController(text: '$_steps');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom daily goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Steps per day', helperText: '${_fmt.format(StepGoalLimits.min)}–${_fmt.format(StepGoalLimits.max)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n == null || n < StepGoalLimits.min || n > StepGoalLimits.max) return;
              Navigator.pop(ctx, n);
            },
            child: const Text('Set goal'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (v != null) {
      setState(() {
        _steps = v;
        _custom = !StepGoalLimits.presets.contains(v);
      });
    }
  }

  Future<void> _save({required bool skip}) => _guard.run(() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final owner = ref.read(ownerProvider).ownerId;
      final repo = ref.read(settingsRepositoryProvider);
      final sync = ref.read(syncServiceProvider);
      final today = localDateKey(ref.read(clockProvider).nowLocal());
      final existing = await repo.goals(owner);

      // Tránh nhân đôi version khi người dùng quay lại bước này: chỉ ghi khi giá trị khác bản đang áp dụng.
      Future<void> put(GoalType type, double value) async {
        final current = goalForDate(existing, type, today);
        if (current != null && current.value == value) return;
        final g = await repo.setGoal(owner, type, value);
        await sync.enqueueGoal(g);
      }

      await put(GoalType.dailySteps, (skip ? StepGoalLimits.defaultValue : _steps).toDouble());
      if (!skip && _weekly) {
        final unit = ref.read(settingsProvider).value?.distanceUnit ?? DistanceUnit.km;
        await put(GoalType.weeklyRuns, _runs.toDouble());
        await put(GoalType.weeklyDistanceM, _distance * (unit == DistanceUnit.mi ? _metersPerMile : 1000.0));
      }
      if (mounted) context.push(Routes.setupPermissions);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save your goal on this device. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider).value?.distanceUnit ?? DistanceUnit.km;
    final unitLabel = unit == DistanceUnit.mi ? 'mi' : 'km';
    return StrideScreen(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: 'Continue', trailingIcon: Icons.arrow_forward, loading: _saving, onPressed: () => _save(skip: false)),
          TextButton(onPressed: _saving ? null : () => _save(skip: true), child: const Text('Skip for now')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SetupHeader(
            step: 1,
            title: 'Set a goal that fits you',
            subtitle: 'Choose your daily steps goal and, if you like, a weekly running goal. You can change this anytime.',
          ),
          if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
          SageCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    IconBadge(icon: Icons.directions_walk),
                    SizedBox(width: StrideSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daily steps goal', style: StrideText.subheading),
                          Text('A great way to stay active and healthy every day.', style: StrideText.bodySecondary),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: StrideSpace.s16),
                ValueStepper(
                  valueText: _fmt.format(_steps),
                  unitLabel: 'steps per day',
                  semanticLabel: 'Daily steps goal',
                  onDecrement: _steps - StepGoalLimits.step < StepGoalLimits.min
                      ? null
                      : () => setState(() {
                          _steps -= StepGoalLimits.step;
                          _custom = !StepGoalLimits.presets.contains(_steps);
                        }),
                  onIncrement: _steps + StepGoalLimits.step > StepGoalLimits.max
                      ? null
                      : () => setState(() {
                          _steps += StepGoalLimits.step;
                          _custom = !StepGoalLimits.presets.contains(_steps);
                        }),
                ),
                const SizedBox(height: StrideSpace.s16),
                Wrap(
                  spacing: StrideSpace.s8,
                  runSpacing: StrideSpace.s8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final p in StepGoalLimits.presets)
                      StrideChip(
                        label: _fmt.format(p),
                        selected: !_custom && _steps == p,
                        onTap: () => setState(() {
                          _steps = p;
                          _custom = false;
                        }),
                      ),
                    StrideChip(label: 'Custom', selected: _custom, onTap: _customSteps),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: StrideSpace.s16),
          SageCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: Row(
                    children: [
                      const IconBadge(icon: Icons.directions_run),
                      const SizedBox(width: StrideSpace.s12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Weekly running goal', style: StrideText.subheading),
                            Text('Set a target to keep you motivated. This is optional.', style: StrideText.bodySecondary),
                          ],
                        ),
                      ),
                      Switch(value: _weekly, onChanged: (v) => setState(() => _weekly = v)),
                    ],
                  ),
                ),
                if (_weekly) ...[
                  const SizedBox(height: StrideSpace.s16),
                  _MiniStepper(
                    icon: Icons.calendar_today_outlined,
                    label: 'Runs per week',
                    value: '$_runs',
                    unit: 'runs per week',
                    onMinus: _runs > 1 ? () => setState(() => _runs--) : null,
                    onPlus: _runs < 14 ? () => setState(() => _runs++) : null,
                  ),
                  const SizedBox(height: StrideSpace.s12),
                  _MiniStepper(
                    icon: Icons.place_outlined,
                    label: 'Total distance',
                    value: '$_distance',
                    unit: '$unitLabel per week',
                    onMinus: _distance > 1 ? () => setState(() => _distance--) : null,
                    onPlus: _distance < 300 ? () => setState(() => _distance++) : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: StrideSpace.s16),
          Text('Skip for now uses ${_fmt.format(StepGoalLimits.defaultValue)} steps a day and no weekly running goal.', style: StrideText.caption),
        ],
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({required this.icon, required this.label, required this.value, required this.unit, required this.onMinus, required this.onPlus});
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback? f, String sem) => IconButton(
      tooltip: sem,
      onPressed: f,
      icon: Icon(i),
      style: IconButton.styleFrom(
        side: const BorderSide(color: StrideColors.borderSubtle),
        backgroundColor: StrideColors.surface,
      ),
    );
    return Row(
      children: [
        Icon(icon, color: StrideColors.primary),
        const SizedBox(width: StrideSpace.s12),
        Expanded(child: Text(label, style: StrideText.body)),
        btn(Icons.remove, onMinus, 'Decrease $label'),
        SizedBox(
          width: 72,
          child: Semantics(
            label: '$label $value $unit',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(value, style: StrideText.metricSmall),
                Text(unit, style: StrideText.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        btn(Icons.add, onPlus, 'Increase $label'),
      ],
    );
  }
}
