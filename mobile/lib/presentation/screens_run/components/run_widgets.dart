import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/formatters.dart';
import '../../../values/tokens.dart';
import '../../../models/data_models/activity.dart';
import '../../../models/ui_models/workout_models.dart';
import '../../../controller/run/engine/run_sources.dart';

String runGoalLabel(RunGoal g, StrideFormat fmt) => switch (g.type) {
  RunGoalType.free => 'Free run',
  RunGoalType.distance => '${fmt.distance(g.value)} goal',
  RunGoalType.time => '${((g.value ?? 0) / 60000).round()} min goal',
};

String workoutLabel(WorkoutPlan? plan) => plan == null ? 'Free run' : '${plan.name} · ${formatStepDuration(plan.totalMs)}';

String longDate(int utcMs) => DateFormat('EEEE, MMMM d, y').format(DateTime.fromMillisecondsSinceEpoch(utcMs));
String clockTime(int utcMs) => DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(utcMs));

/// Chip trạng thái GPS: luôn có icon + chữ.
class GpsStatusChip extends StatelessWidget {
  const GpsStatusChip({super.key, required this.quality, this.dark = false});
  final GpsQuality quality;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (quality) {
      GpsQuality.good => (Icons.gps_fixed, 'GPS good', StrideColors.success),
      GpsQuality.weak => (Icons.gps_not_fixed, 'GPS weak', StrideColors.warning),
      GpsQuality.lost => (Icons.gps_off, 'GPS lost', StrideColors.error),
      GpsQuality.searching => (Icons.location_searching, 'Searching for GPS', StrideColors.textSecondary),
      GpsQuality.notUsed => (Icons.location_disabled, 'GPS not used', StrideColors.textSecondary),
    };
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: StrideColors.surface, borderRadius: BorderRadius.circular(StrideRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(text, style: StrideText.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// Số liệu lớn khi chạy: giá trị + đơn vị + nhãn, có Semantics đầy đủ.
class RunMetric extends StatelessWidget {
  const RunMetric({super.key, required this.value, required this.label, this.unit, this.big = false, this.color, this.estimated = false});
  final String value;
  final String label;
  final String? unit;
  final bool big;
  final Color? color;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? StrideColors.textPrimary;
    final style = (big ? StrideText.runTimer : StrideText.metricMedium).copyWith(color: fg);
    return Semantics(
      label: '$label, $value${unit == null ? '' : ' $unit'}${estimated ? ', estimated' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: style),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: StrideText.label.copyWith(color: color ?? StrideColors.textSecondary),
                    ),
                ],
              ),
              maxLines: 1,
            ),
          ),
          Text(estimated ? '$label · estimated' : label, style: StrideText.caption.copyWith(color: color?.withValues(alpha: 0.8) ?? StrideColors.textMuted)),
        ],
      ),
    );
  }
}

/// Bảng kết quả từng pha interval: planned vs actual (K03).
class PhaseTable extends StatelessWidget {
  const PhaseTable({super.key, required this.results, required this.fmt, this.incomplete = false});
  final List<PhaseResult> results;
  final StrideFormat fmt;
  final bool incomplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Interval phases', style: StrideText.subheading)),
            if (incomplete)
              Semantics(
                label: 'Workout incomplete',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: StrideColors.warningBg, borderRadius: BorderRadius.circular(StrideRadius.pill)),
                  child: Text('Incomplete', style: StrideText.label.copyWith(color: StrideColors.warning)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(flex: 4, child: Text('Phase', style: StrideText.caption)),
            Expanded(
              flex: 3,
              child: Text('Planned', style: StrideText.caption, textAlign: TextAlign.end),
            ),
            Expanded(
              flex: 3,
              child: Text('Actual', style: StrideText.caption, textAlign: TextAlign.end),
            ),
            Expanded(
              flex: 3,
              child: Text('Distance', style: StrideText.caption, textAlign: TextAlign.end),
            ),
          ],
        ),
        const Divider(),
        for (final r in results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Icon(
                        r.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: r.completed ? StrideColors.success : StrideColors.textMuted,
                        semanticLabel: r.completed ? 'Completed' : 'Not completed',
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(r.label, style: StrideText.label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(formatDuration(r.plannedMs), style: StrideText.metricSmall.copyWith(fontSize: 14), textAlign: TextAlign.end),
                ),
                Expanded(
                  flex: 3,
                  child: Text(formatDuration(r.actualMs), style: StrideText.metricSmall.copyWith(fontSize: 14), textAlign: TextAlign.end),
                ),
                Expanded(
                  flex: 3,
                  child: Text(fmt.distance(r.distanceM), style: StrideText.metricSmall.copyWith(fontSize: 14), textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
