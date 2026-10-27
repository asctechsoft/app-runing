import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/ui_models/period.dart';
import '../../../utils/clock.dart';
import '../../../utils/formatters.dart';
import '../../../utils/l10n.dart';
import '../../../utils/progress_data.dart';
import '../../../values/tokens.dart';

/// Biểu đồ cột theo kỳ. Ngày tương lai không có cột; ngày thiếu dữ liệu không vẽ 0 giả.
/// Có tooltip khi chạm và danh sách thay thế cho trình đọc màn hình (I04).
class ProgressBarChart extends StatelessWidget {
  const ProgressBarChart({
    super.key,
    required this.period,
    required this.buckets,
    required this.toDisplay,
    required this.formatValue,
    required this.today,
    this.goalLine,
    this.goalLabel,
    this.semanticTitle = 'Chart',
  });

  final ProgressPeriod period;
  final List<BucketValue> buckets;

  /// Đổi đơn vị gốc → giá trị vẽ (vd. mét → km).
  final double Function(double) toDisplay;

  /// Định dạng giá trị gốc cho tooltip/danh sách; null → "—".
  final String Function(double?) formatValue;
  final DateTime today;

  /// Đường mục tiêu (đơn vị gốc), vẽ nét đứt.
  final double? goalLine;
  final String? goalLabel;
  final String semanticTitle;

  @override
  Widget build(BuildContext context) {
    final todayKey = localDateKey(today);
    final values = [for (final b in buckets) b.value == null ? null : toDisplay(b.value!)];
    final goal = goalLine == null ? null : toDisplay(goalLine!);
    final maxV = [...values.whereType<double>(), ?goal, 0.0].reduce(math.max);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.15;
    final many = buckets.length > 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(color: StrideColors.borderSubtle, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: goal == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: goal,
                            color: StrideColors.textSecondary,
                            strokeWidth: 1.5,
                            dashArray: const [6, 4],
                            label: HorizontalLineLabel(
                              show: goalLabel != null,
                              alignment: Alignment.topRight,
                              style: StrideText.caption,
                              labelResolver: (_) => goalLabel ?? '',
                            ),
                          ),
                        ],
                      ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: maxY / 4,
                      getTitlesWidget: (v, meta) {
                        if (v == meta.max) return const SizedBox.shrink();
                        final text = v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : v.toStringAsFixed(v < 10 && v != 0 ? 1 : 0);
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(text, style: StrideText.caption),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                        // Tháng: chỉ ghi ngày 1, 8, 15, 22, 29 để không chồng chữ.
                        if (many && (buckets[i].bucket.start.day - 1) % 7 != 0) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(bucketLabel(period, buckets[i].bucket), style: StrideText.caption),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => StrideColors.textPrimary,
                    getTooltipItem: (group, _, _, _) {
                      final b = buckets[group.x];
                      return BarTooltipItem(
                        '${bucketLongLabel(period, b.bucket)}\n${formatValue(b.value)}',
                        StrideText.label.copyWith(color: StrideColors.surface),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: buckets[i].future || values[i] == null
                          ? []
                          : [
                              BarChartRodData(
                                toY: values[i]!,
                                width: many ? 6 : 18,
                                color: _isCurrent(buckets[i], todayKey) ? StrideColors.primary : StrideColors.chartBar,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('progress_view_as_list'.tr, style: StrideText.label.copyWith(color: StrideColors.primary)),
            children: [
              for (final b in buckets)
                Semantics(
                  label: 'progress_bar_label'.trArgs([bucketLongLabel(period, b.bucket), b.future ? 'progress_upcoming_lower'.tr : formatValue(b.value)]),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(bucketLongLabel(period, b.bucket), style: StrideText.body)),
                        Text(
                          b.future ? 'progress_upcoming'.tr : formatValue(b.value),
                          style: StrideText.body.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: b.future || b.value == null ? StrideColors.textMuted : StrideColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isCurrent(BucketValue b, String todayKey) => period == ProgressPeriod.year ? b.bucket.contains(today) : localDateKey(b.bucket.start) == todayKey;
}

/// Giá trị thiếu → "—".
String formatOrMissing(double? v, String Function(double) f) => v == null ? missingValue : f(v);
