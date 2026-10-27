import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../controller/steps/steps_logic.dart';
import '../../../models/data_models/steps.dart';
import '../../../utils/formatters.dart';
import '../../../utils/l10n.dart';
import '../../../values/tokens.dart';

/// Biểu đồ bước theo giờ (Home "Steps today" và Daily steps).
/// - Giờ tương lai: không có bar.
/// - Giờ thiếu dữ liệu (null): để trống, tooltip "No data" — khác với 0.
/// - Giờ có 0 bước thật: vạch nền ngắn màu control để phân biệt với thiếu dữ liệu.
class HourlyStepsChart extends StatelessWidget {
  const HourlyStepsChart({
    super.key,
    required this.entries,
    required this.format,
    this.source,
    this.targetPerHour,
    this.height = 200,
    this.compact = false,
    this.selectedHour,
  });

  final List<HourEntry> entries;
  final StrideFormat format;
  final StepSource? source;

  /// Đường mục tiêu (bước/giờ) nét đứt có nhãn; null → không vẽ.
  final double? targetPerHour;
  final double height;
  final bool compact;
  final int? selectedHour;

  @override
  Widget build(BuildContext context) {
    final maxVal = entries.fold<int>(0, (a, e) => math.max(a, e.steps ?? 0));
    final top = _niceMax(math.max(maxVal.toDouble(), targetPerHour ?? 0));
    final zeroStub = top * 0.015;
    final summary = _semanticSummary();
    return Semantics(
      label: summary,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: top,
              alignment: BarChartAlignment.spaceBetween,
              groupsSpace: 2,
              borderData: FlBorderData(
                show: true,
                border: const Border(bottom: BorderSide(color: StrideColors.borderSubtle)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: top / 2,
                getDrawingHorizontalLine: (_) => const FlLine(color: StrideColors.borderSubtle, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: top / 2,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(format.steps(v.round()), style: StrideText.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final h = v.round();
                      if (h % 6 != 0) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(hourLabel(h), style: StrideText.caption),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: targetPerHour == null
                  ? const ExtraLinesData()
                  : ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: targetPerHour!,
                          color: StrideColors.textSecondary,
                          strokeWidth: 1.5,
                          dashArray: const [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: StrideText.caption.copyWith(color: StrideColors.textSecondary),
                            labelResolver: (_) => 'steps_goal_pace'.trArgs([format.steps(targetPerHour!.round())]),
                          ),
                        ),
                      ],
                    ),
              barTouchData: BarTouchData(
                enabled: !compact,
                touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 8),
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 160,
                  getTooltipColor: (_) => StrideColors.textPrimary,
                  getTooltipItem: (group, gi, rod, ri) {
                    final e = entries[group.x];
                    if (e.future) return null;
                    final value = e.steps == null ? 'steps_no_data_short'.tr : 'steps_count'.trArgs([format.steps(e.steps)]);
                    final src = e.steps == null ? '' : '\n${sourceLabel(source)}';
                    return BarTooltipItem(
                      '${hourLabel(e.hour)}\n$value$src',
                      StrideText.caption.copyWith(color: StrideColors.surface, fontFeatures: const [FontFeature.tabularFigures()]),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final e in entries)
                  BarChartGroupData(
                    x: e.hour,
                    barRods: [
                      BarChartRodData(
                        toY: e.future || e.steps == null ? 0 : (e.steps == 0 ? zeroStub : e.steps!.toDouble()),
                        width: compact ? 6 : 8,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        color: e.steps == 0
                            ? StrideColors.borderControl
                            : (selectedHour == e.hour ? StrideColors.primary : (compact ? StrideColors.primary : StrideColors.chartBar)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticSummary() {
    final past = entries.where((e) => !e.future).toList();
    final withData = past.where((e) => e.steps != null).length;
    final total = past.fold<int>(0, (a, e) => a + (e.steps ?? 0));
    return 'steps_chart_summary'.trArgs([withData, past.length, format.steps(total)]);
  }

  static double _niceMax(double v) {
    if (v <= 0) return 1000;
    final steps = [100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000];
    for (final s in steps) {
      if (v <= s * 2) return (v / s).ceil() * s.toDouble();
    }
    return (v / 10000).ceil() * 10000.0;
  }
}

/// Danh sách thay thế cho trình đọc màn hình (DS §06): mỗi giờ một hàng, thiếu dữ liệu = —.
class HourlyStepsList extends StatelessWidget {
  const HourlyStepsList({super.key, required this.entries, required this.format});
  final List<HourEntry> entries;
  final StrideFormat format;

  @override
  Widget build(BuildContext context) {
    final rows = entries.where((e) => !e.future).toList();
    if (rows.isEmpty) return Text('steps_no_hours'.tr, style: StrideText.bodySecondary);
    return Column(
      children: [
        for (final e in rows)
          Semantics(
            label: e.steps == null ? 'steps_hour_no_data'.trArgs([hourLabel(e.hour)]) : 'steps_hour_steps'.trArgs([hourLabel(e.hour), format.steps(e.steps)]),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(hourLabel(e.hour), style: StrideText.body)),
                  Text(
                    e.steps == null ? missingValue : format.steps(e.steps),
                    style: StrideText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: e.steps == null ? StrideColors.textMuted : null),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
