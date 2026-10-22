import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../utils/calc/run_metrics.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../controller/activity/activity_actions.dart';
import 'components/activity_charts.dart';
import '../../utils/activity_charts_data.dart';
import '../../services/application/activity_export.dart';
import '../../utils/activity_format.dart';
import 'components/activity_map_view.dart';
import '../../controller/activity/activity_providers.dart';
import '../../utils/route_geometry.dart';
import '../../utils/l10n.dart';

enum _DetailTab { overview, splits, charts }

enum _MenuAction { edit, share, gpx, csv, delete }

/// Chi tiết hoạt động (I02, F15). Dùng chung dưới /home, /progress, /history — luôn đọc theo ID từ DB local.
class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  @override
  ConsumerState<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  _DetailTab _tab = _DetailTab.overview;
  final _guard = OnceGuard();

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.history);
    }
  }

  Future<void> _edit() async {
    final r = await context.push<String>(Routes.activityEdit(widget.activityId));
    if (r == 'deleted' && mounted) _back();
  }

  Future<void> _onMenu(_MenuAction action, ActivityDetailData d) async {
    switch (action) {
      case _MenuAction.edit:
        await _edit();
      case _MenuAction.share:
        await context.push(Routes.activityShare(widget.activityId));
      case _MenuAction.gpx:
        await _guard.run(() => exportGpx(context, d.activity, d.points));
      case _MenuAction.csv:
        await _guard.run(() => exportCsv(context, d.activity));
      case _MenuAction.delete:
        final deleted = await confirmAndDeleteActivity(context, ref, d.activity);
        if (deleted && mounted) {
          showStrideSnack(context, 'activity_deleted_snack'.tr);
          _back();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityDetailProvider(widget.activityId));
    return async.when(
      loading: () => StrideScreen(
        onBack: _back,
        body: const Column(children: [SizedBox(height: 8), LoadingCard(height: 220), SizedBox(height: 16), LoadingCard(height: 140)]),
      ),
      error: (e, _) => StrideScreen(
        onBack: _back,
        body: ErrorState(
          title: 'activity_open_error_title'.tr,
          message: 'activity_open_error_message_detail'.tr,
          onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (d) {
        if (d == null) {
          return StrideScreen(
            onBack: _back,
            body: EmptyState(
              icon: Icons.search_off,
              title: 'activity_not_found_title'.tr,
              message: 'activity_not_found_message_detail'.tr,
              actionLabel: 'activity_back_to_history'.tr,
              onAction: () => context.go(Routes.history),
            ),
          );
        }
        return _buildDetail(d);
      },
    );
  }

  Widget _buildDetail(ActivityDetailData d) {
    final a = d.activity;
    final canGpx = canExportGpx(a, d.points);
    return StrideScreen(
      onBack: _back,
      title: activityDisplayTitle(a),
      actions: [
        PopupMenuButton<_MenuAction>(
          tooltip: 'activity_more_options'.tr,
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => _onMenu(v, d),
          itemBuilder: (_) => [
            PopupMenuItem(value: _MenuAction.edit, child: Text('activity_edit'.tr)),
            PopupMenuItem(value: _MenuAction.share, child: Text('activity_share_image'.tr)),
            if (canGpx) PopupMenuItem(value: _MenuAction.gpx, child: Text('activity_export_gpx'.tr)),
            PopupMenuItem(value: _MenuAction.csv, child: Text('activity_export_csv'.tr)),
            PopupMenuItem(
              value: _MenuAction.delete,
              child: Text('activity_delete'.tr, style: StrideText.body.copyWith(color: StrideColors.error)),
            ),
          ],
        ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: PrimaryButton(label: 'activity_share'.tr, icon: Icons.ios_share, onPressed: () => context.push(Routes.activityShare(a.id))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SecondaryButton(label: 'activity_edit'.tr, icon: Icons.edit_outlined, onPressed: _edit),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(activityDateTimeLabel(a), style: StrideText.bodySecondary),
          const SizedBox(height: 12),
          StrideSegmented<_DetailTab>(
            values: _DetailTab.values,
            selected: _tab,
            labelOf: (t) => switch (t) {
              _DetailTab.overview => 'activity_tab_overview'.tr,
              _DetailTab.splits => 'activity_tab_splits'.tr,
              _DetailTab.charts => 'activity_tab_charts'.tr,
            },
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            _DetailTab.overview => _Overview(data: d, onEdit: _edit),
            _DetailTab.splits => _Splits(data: d),
            _DetailTab.charts => _Charts(data: d),
          },
        ],
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.data, required this.onEdit});
  final ActivityDetailData data;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = data.activity;
    final f = ref.watch(formatProvider);
    final estimatedDistance = a.distanceSource != DistanceSource.gps;
    final elapsed = a.elapsedMs > 0 ? a.elapsedMs : (a.endedAt == null ? null : a.endedAt! - a.startedAt);
    final paceValue = f.paceValue(a.avgPaceSecPerKm ?? avgPaceSecPerKm(movingMs: a.movingMs, distanceM: a.distanceM));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.hasRoute)
          ClipRRect(
            borderRadius: BorderRadius.circular(StrideRadius.card),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Positioned.fill(child: ActivityRouteMap(route: routeFromPoints(data.points))),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: StrideColors.surface,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'activity_expand_map'.tr,
                        icon: const Icon(Icons.open_in_full),
                        onPressed: () => context.push(Routes.activityMap(a.id)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          StatusBanner(
            tone: BannerTone.info,
            icon: Icons.location_off_outlined,
            title: 'activity_no_gps_title'.tr,
            message: a.type == ActivityType.indoorRun ? 'activity_no_gps_indoor_message'.tr : 'activity_no_gps_saved_message'.tr,
          ),
        const SizedBox(height: 16),
        StrideCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: Icons.route_outlined,
                      label: 'activity_metric_distance'.tr,
                      value: f.distanceValue(a.distanceM),
                      unit: a.distanceM == null ? null : f.distanceUnitLabel,
                      estimated: estimatedDistance,
                      center: true,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.timer_outlined, label: 'activity_metric_moving_time'.tr, value: formatDuration(a.movingMs), center: true),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.schedule, label: 'activity_metric_elapsed_time'.tr, value: formatDuration(elapsed), center: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: Icons.speed,
                      label: 'activity_metric_avg_pace'.tr,
                      value: paceValue,
                      unit: paceValue == missingValue ? null : f.paceUnitLabel,
                      center: true,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.directions_walk, label: 'activity_metric_steps'.tr, value: f.steps(a.steps), center: true),
                  ),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.local_fire_department_outlined,
                      label: 'activity_metric_calories'.tr,
                      value: a.caloriesKcal == null ? missingValue : f.kcal(a.caloriesKcal).replaceAll(' kcal', ''),
                      unit: a.caloriesKcal == null ? null : 'kcal',
                      estimated: a.caloriesKcal != null,
                      center: true,
                    ),
                  ),
                ],
              ),
              if (a.caloriesKcal == null) ...[
                const SizedBox(height: 8),
                Text('activity_calories_need_weight'.tr, style: StrideText.caption, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          children: [
            SettingsRow(icon: Icons.sentiment_satisfied_alt_outlined, title: 'activity_row_feeling'.tr, subtitle: feelingLabel(a.feeling), onTap: onEdit),
            SettingsRow(
              icon: Icons.notes,
              title: 'activity_row_notes'.tr,
              subtitle: (a.notes == null || a.notes!.trim().isEmpty) ? 'activity_no_notes'.tr : a.notes!.trim(),
              onTap: onEdit,
            ),
            SettingsRow(icon: Icons.lock_outline, title: 'activity_privacy'.tr, subtitle: privacyLabel(a.privacy), onTap: onEdit),
            SettingsRow(
              icon: Icons.sync,
              title: 'activity_row_sync_status'.tr,
              trailing: SyncBadge(state: a.syncState.name),
              showChevron: false,
            ),
            SettingsRow(
              icon: Icons.sensors,
              title: 'activity_row_distance_source'.tr,
              subtitle: switch (a.distanceSource) {
                DistanceSource.gps => 'activity_source_gps'.tr,
                DistanceSource.steps => 'activity_source_steps'.tr,
                DistanceSource.manual => 'activity_source_manual'.tr,
              },
              showChevron: false,
            ),
          ],
        ),
        if (data.photos.isNotEmpty) ...[
          SectionHeader(title: 'activity_photos'.tr),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = data.photos[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(StrideRadius.control),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: p.fileExists
                        ? Image.file(File(p.localPath!), fit: BoxFit.cover, semanticLabel: 'activity_photo_n'.trArgs([i + 1]))
                        : const ColoredBox(
                            color: StrideColors.subtle,
                            child: Icon(Icons.broken_image_outlined, color: StrideColors.textMuted),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _Splits extends ConsumerWidget {
  const _Splits({required this.data});
  final ActivityDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(formatProvider);
    if (!data.hasRoute) {
      return StatusBanner(tone: BannerTone.info, title: 'activity_splits_need_gps_title'.tr, message: 'activity_splits_need_gps_message'.tr);
    }
    final splitM = f.distanceUnit == DistanceUnit.km ? 1000.0 : metersPerMile;
    final splits = computeSplits(data.points, splitM: splitM);
    if (splits.isEmpty) {
      return StatusBanner(tone: BannerTone.info, title: 'activity_no_splits_title'.tr, message: 'activity_no_splits_message'.tr);
    }
    final paces = splits.map((s) => s.paceSecPerKm).whereType<double>().toList();
    final fastest = paces.isEmpty ? null : paces.reduce((a, b) => a < b ? a : b);
    final slowest = paces.isEmpty ? null : paces.reduce((a, b) => a > b ? a : b);
    final unit = f.distanceUnitLabel;
    return StrideCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 56, child: Text(unit == 'km' ? 'activity_split_col_km'.tr : 'activity_split_col_mile'.tr, style: StrideText.label)),
                Expanded(child: Text('activity_split_col_pace'.trArgs([f.paceUnitLabel]), style: StrideText.label)),
                SizedBox(
                  width: 72,
                  child: Text('activity_time'.tr, style: StrideText.label, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final s in splits)
            Builder(
              builder: (context) {
                final partial = (s.distanceM - splitM).abs() > 0.5;
                final label = partial ? f.distanceValue(s.distanceM) : '${s.index + 1}';
                final pace = s.paceSecPerKm;
                final paceText = f.paceValue(pace);
                // Thanh tương đối: dài hơn = nhanh hơn.
                double? frac;
                if (pace != null && fastest != null && slowest != null) {
                  frac = slowest == fastest ? 1.0 : (0.35 + 0.65 * (slowest - pace) / (slowest - fastest));
                }
                return Semantics(
                  label: partial
                      ? 'activity_split_semantic_partial'.trArgs([f.distance(s.distanceM), paceText, formatDuration(s.movingMs)])
                      : 'activity_split_semantic'.trArgs([s.index + 1, paceText, formatDuration(s.movingMs)]),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text(label, style: StrideText.metricSmall.copyWith(fontSize: 16))),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(width: 52, child: Text(paceText, style: StrideText.metricSmall.copyWith(fontSize: 16))),
                              Expanded(
                                child: frac == null
                                    ? const SizedBox.shrink()
                                    : FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: frac.clamp(0.05, 1.0),
                                        child: Container(
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: pace == fastest ? StrideColors.primary : StrideColors.chartBar,
                                            borderRadius: BorderRadius.circular(StrideRadius.pill),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 72,
                          child: Text(
                            formatDuration(s.movingMs),
                            style: StrideText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('activity_splits_footnote'.tr, style: StrideText.caption),
          ),
        ],
      ),
    );
  }
}

class _Charts extends ConsumerWidget {
  const _Charts({required this.data});
  final ActivityDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(formatProvider);
    final a = data.activity;
    final unit = f.distanceUnitLabel;
    double toUnit(double km) => f.metersToUnit(km * 1000);
    String fmtX(double v) => v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

    ChartSeries convertX(ChartSeries s) => s.available ? ChartSeries.ok([for (final p in s.samples) ChartSample(toUnit(p.x), p.y)]) : s;

    final pace = data.hasRoute ? convertX(paceSeries(data.points)) : const ChartSeries.unavailable('activity_chart_pace_no_route');
    final elevation = data.hasRoute ? convertX(elevationSeries(data.points)) : const ChartSeries.unavailable('activity_chart_elevation_no_route');
    final hr = heartRateSeries(data.heartRate, a.startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeriesChartCard(
          title: 'activity_pace'.tr,
          series: pace,
          xLabel: unit,
          yLabel: 'activity_chart_pace_unit'.trArgs([unit]),
          invertY: true,
          formatY: (v) => f.paceValue(v),
          formatX: fmtX,
          helper: 'activity_chart_pace_helper'.tr,
          semanticSummary: 'activity_chart_pace_semantic'.trArgs([f.pace(a.avgPaceSecPerKm)]),
        ),
        const SizedBox(height: 12),
        SeriesChartCard(
          title: 'activity_chart_elevation'.tr,
          series: elevation,
          xLabel: unit,
          yLabel: 'activity_unit_m'.tr,
          formatY: (v) => v.toStringAsFixed(0),
          formatX: fmtX,
          semanticSummary: 'activity_chart_elevation_semantic'.tr,
        ),
        const SizedBox(height: 12),
        SeriesChartCard(
          title: 'activity_chart_hr'.tr,
          series: hr,
          xLabel: 'activity_unit_min'.tr,
          yLabel: 'activity_unit_bpm'.tr,
          formatY: (v) => v.toStringAsFixed(0),
          formatX: (v) => v.toStringAsFixed(0),
          semanticSummary: 'activity_chart_hr_semantic'.tr,
        ),
      ],
    );
  }
}
