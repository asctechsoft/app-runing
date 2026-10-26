import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../controller/run/engine/run_session_controller.dart';

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
      title: 'run_goal_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('run_goal_intro'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: 16),
          StrideSegmented<RunGoalType>(
            values: RunGoalType.values,
            selected: _type,
            labelOf: (t) => switch (t) {
              RunGoalType.free => 'run_goal_tab_free'.tr,
              RunGoalType.distance => 'run_label_distance'.tr,
              RunGoalType.time => 'run_goal_tab_time'.tr,
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
                  Expanded(child: Text('run_goal_free_desc'.tr, style: StrideText.body)),
                ],
              ),
            ),
          if (_type == RunGoalType.distance) ...[
            StrideCard(
              child: ValueStepper(
                valueText: num(_distanceUnits),
                unitLabel: fmt.distanceUnitLabel,
                semanticLabel: 'run_goal_distance_semantic'.tr,
                onDecrement: _distanceUnits > 0.5 ? () => setState(() => _distanceUnits = (_distanceUnits - 0.5).clamp(0.5, 100)) : null,
                onIncrement: _distanceUnits < 100 ? () => setState(() => _distanceUnits = (_distanceUnits + 0.5).clamp(0.5, 100)) : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('run_goal_presets'.tr, style: StrideText.caption),
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
                unitLabel: 'run_goal_minutes'.tr,
                semanticLabel: 'run_goal_time_semantic'.tr,
                onDecrement: _minutes > 5 ? () => setState(() => _minutes -= 5) : null,
                onIncrement: _minutes < 600 ? () => setState(() => _minutes += 5) : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('run_goal_presets'.tr, style: StrideText.caption),
            PresetChips<int>(
              values: const [15, 30, 45, 60, 90],
              selected: _minutes,
              labelOf: (v) => 'run_goal_min_short'.trArgs([v]),
              onSelected: (v) => setState(() => _minutes = v),
            ),
          ],
        ],
      ),
      bottom: PrimaryButton(
        label: 'run_save'.tr,
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
