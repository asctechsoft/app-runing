import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';
import '../../../utils/activity_charts_data.dart';

/// Thẻ biểu đồ đường; khi chuỗi không có dữ liệu thì hiện lý do thay vì biểu đồ rỗng.
class SeriesChartCard extends StatelessWidget {
  const SeriesChartCard({
    super.key,
    required this.title,
    required this.series,
    required this.xLabel,
    required this.yLabel,
    required this.formatY,
    required this.formatX,
    this.invertY = false,
    this.helper,
    this.semanticSummary,
  });

  final String title;
  final ChartSeries series;
  final String xLabel;
  final String yLabel;
  final String Function(double) formatY;
  final String Function(double) formatX;

  /// Pace: giá trị nhỏ hơn = nhanh hơn → vẽ đảo trục để "nhanh hơn" nằm trên.
  final bool invertY;
  final String? helper;
  final String? semanticSummary;

  @override
  Widget build(BuildContext context) {
    if (!series.available) {
      return StrideCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: StrideColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: StrideText.subheading),
                  const SizedBox(height: 4),
                  Text(series.reason!, style: StrideText.bodySecondary),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final s = series.samples;
    final ys = s.map((e) => invertY ? -e.y : e.y).toList();
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.1, 1.0);
    minY -= pad;
    maxY += pad;
    final maxX = s.last.x <= 0 ? 1.0 : s.last.x;
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: StrideText.subheading)),
              if (invertY)
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, size: 14, color: StrideColors.textSecondary),
                    Text('Faster', style: StrideText.caption.copyWith(color: StrideColors.textSecondary)),
                  ],
                ),
            ],
          ),
          if (helper != null) Text(helper!, style: StrideText.caption),
          const SizedBox(height: 12),
          Semantics(
            label: semanticSummary ?? title,
            excludeSemantics: true,
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (var i = 0; i < s.length; i++) FlSpot(s[i].x, ys[i])],
                      isCurved: true,
                      curveSmoothness: 0.15,
                      preventCurveOverShooting: true,
                      color: StrideColors.primary,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(color: StrideColors.borderSubtle, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      axisNameWidget: Text(yLabel, style: StrideText.caption),
                      axisNameSize: 18,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (v, meta) {
                          if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(formatY(invertY ? -v : v), style: StrideText.caption),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: Text(xLabel, style: StrideText.caption),
                      axisNameSize: 18,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(formatX(v), style: StrideText.caption),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => StrideColors.textPrimary,
                      getTooltipItems: (spots) => [
                        for (final sp in spots)
                          LineTooltipItem(
                            '${formatY(invertY ? -sp.y : sp.y)} · ${formatX(sp.x)} $xLabel',
                            StrideText.label.copyWith(color: StrideColors.surface),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
