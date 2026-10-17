import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/profile.dart';
import 'engine/run_session_controller.dart';

/// Mục tiêu cho buổi chạy này (Free / Distance / Time) — không phải Goals hằng ngày.
class RunGoalScreen extends ConsumerStatefulWidget {
  const RunGoalScreen({super.key});

  @override
  ConsumerState<RunGoalScreen> createState() => _RunGoalScreenState();
}

class _RunGoalScreenState extends ConsumerState<RunGoalScreen> {
  late RunGoalType _type;

  /// Quãng đường theo đơn vị hiển thị (km hoặc mi).
  double _distanceUnits = 5;
  int _minutes = 30;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final g = ref.read(runSessionProvider).setup.goal;
    final fmt = ref.read(formatProvider);
    _type = g.type;
    if (g.type == RunGoalType.distance && g.value != null) _distanceUnits = double.parse(fmt.metersToUnit(g.value!).toStringAsFixed(1));
    if (g.type == RunGoalType.time && g.value != null) _minutes = (g.value! / 60000).round();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(formatProvider);
    final km = fmt.distanceUnit == DistanceUnit.km;
    final presets = km ? const [1.0, 3.0, 5.0, 10.0, 21.1] : const [1.0, 2.0, 3.0, 5.0, 10.0];
    String num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

    return StrideScreen(
      title: 'Run goal',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set a target for this activity. Your daily goals don\'t change.', style: StrideText.bodySecondary),
          const SizedBox(height: 16),
          StrideSegmented<RunGoalType>(
            values: RunGoalType.values,
            selected: _type,
            labelOf: (t) => switch (t) {
              RunGoalType.free => 'Free',
              RunGoalType.distance => 'Distance',
              RunGoalType.time => 'Time',
            },
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 24),
          if (_type == RunGoalType.free)
            SageCard(
              child: Row(
                children: [
                  const IconBadge(icon: Icons.all_inclusive),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Run as long as you like. Finish whenever you\'re ready.', style: StrideText.body)),
                ],
              ),
            ),
          if (_type == RunGoalType.distance) ...[
            StrideCard(
              child: ValueStepper(
                valueText: num(_distanceUnits),
                unitLabel: fmt.distanceUnitLabel,
                semanticLabel: 'Distance goal',
                onDecrement: _distanceUnits > 0.5 ? () => setState(() => _distanceUnits = (_distanceUnits - 0.5).clamp(0.5, 100)) : null,
                onIncrement: _distanceUnits < 100 ? () => setState(() => _distanceUnits = (_distanceUnits + 0.5).clamp(0.5, 100)) : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('Quick presets', style: StrideText.caption),
            PresetChips<double>(
              values: presets,
              selected: presets.contains(_distanceUnits) ? _distanceUnits : null,
              labelOf: (v) => '${num(v)} ${fmt.distanceUnitLabel}',
              onSelected: (v) => setState(() => _distanceUnits = v),
            ),
          ],
          if (_type == RunGoalType.time) ...[
            StrideCard(
              child: ValueStepper(
                valueText: '$_minutes',
                unitLabel: 'minutes',
                semanticLabel: 'Time goal',
                onDecrement: _minutes > 5 ? () => setState(() => _minutes -= 5) : null,
                onIncrement: _minutes < 600 ? () => setState(() => _minutes += 5) : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('Quick presets', style: StrideText.caption),
            PresetChips<int>(values: const [15, 30, 45, 60, 90], selected: _minutes, labelOf: (v) => '$v min', onSelected: (v) => setState(() => _minutes = v)),
          ],
        ],
      ),
      bottom: PrimaryButton(
        label: 'Save',
        onPressed: () {
          final goal = switch (_type) {
            RunGoalType.free => const RunGoal.free(),
            RunGoalType.distance => RunGoal(RunGoalType.distance, fmt.unitToMeters(_distanceUnits)),
            RunGoalType.time => RunGoal(RunGoalType.time, _minutes * 60000.0),
          };
          ref.read(runSessionProvider.notifier).setGoal(goal);
          context.pop();
        },
      ),
    );
  }
}
