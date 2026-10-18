import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/calc/run_metrics.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/profile.dart';
import 'activity_actions.dart';
import 'activity_charts.dart';
import 'activity_charts_data.dart';
import 'activity_export.dart';
import 'activity_format.dart';
import 'activity_map_view.dart';
import 'activity_providers.dart';
import 'route_geometry.dart';

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
          showStrideSnack(context, 'Activity deleted');
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
          title: 'Couldn\'t open this activity',
          message: 'Reading it from this device failed. Your data has not been changed.',
          onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (d) {
        if (d == null) {
          return StrideScreen(
            onBack: _back,
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Activity not found',
              message: 'This activity may have been deleted or isn\'t available on this device.',
              actionLabel: 'Back to history',
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
          tooltip: 'More options',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => _onMenu(v, d),
          itemBuilder: (_) => [
            const PopupMenuItem(value: _MenuAction.edit, child: Text('Edit')),
            const PopupMenuItem(value: _MenuAction.share, child: Text('Share image')),
            if (canGpx) const PopupMenuItem(value: _MenuAction.gpx, child: Text('Export GPX')),
            const PopupMenuItem(value: _MenuAction.csv, child: Text('Export CSV summary')),
            PopupMenuItem(
              value: _MenuAction.delete,
              child: Text('Delete', style: StrideText.body.copyWith(color: StrideColors.error)),
            ),
          ],
        ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: PrimaryButton(label: 'Share', icon: Icons.ios_share, onPressed: () => context.push(Routes.activityShare(a.id))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SecondaryButton(label: 'Edit', icon: Icons.edit_outlined, onPressed: _edit),
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
              _DetailTab.overview => 'Overview',
              _DetailTab.splits => 'Splits',
              _DetailTab.charts => 'Charts',
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
                      child: IconButton(tooltip: 'Expand map', icon: const Icon(Icons.open_in_full), onPressed: () => context.push(Routes.activityMap(a.id))),
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
            title: 'No GPS route',
            message: a.type == ActivityType.indoorRun
                ? 'Indoor runs are recorded without GPS. Distance is estimated from steps.'
                : 'This activity was saved without a usable GPS route, so there is no map.',
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
                      label: 'Distance',
                      value: f.distanceValue(a.distanceM),
                      unit: a.distanceM == null ? null : f.distanceUnitLabel,
                      estimated: estimatedDistance,
                      center: true,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.timer_outlined, label: 'Moving time', value: formatDuration(a.movingMs), center: true),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.schedule, label: 'Elapsed time', value: formatDuration(elapsed), center: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: Icons.speed,
                      label: 'Avg. pace',
                      value: paceValue,
                      unit: paceValue == missingValue ? null : f.paceUnitLabel,
                      center: true,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.directions_walk, label: 'Steps', value: f.steps(a.steps), center: true),
                  ),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Calories',
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
                Text('Calories need your weight. Add it in Profile to estimate future activities.', style: StrideText.caption, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          children: [
            SettingsRow(icon: Icons.sentiment_satisfied_alt_outlined, title: 'Feeling', subtitle: feelingLabel(a.feeling), onTap: onEdit),
            SettingsRow(
              icon: Icons.notes,
              title: 'Notes',
              subtitle: (a.notes == null || a.notes!.trim().isEmpty) ? 'No notes' : a.notes!.trim(),
              onTap: onEdit,
            ),
            SettingsRow(icon: Icons.lock_outline, title: 'Privacy', subtitle: privacyLabel(a.privacy), onTap: onEdit),
            SettingsRow(
              icon: Icons.sync,
              title: 'Sync status',
              trailing: SyncBadge(state: a.syncState.name),
              showChevron: false,
            ),
            SettingsRow(
              icon: Icons.sensors,
              title: 'Distance source',
              subtitle: switch (a.distanceSource) {
                DistanceSource.gps => 'GPS',
                DistanceSource.steps => 'Steps (estimated)',
                DistanceSource.manual => 'Entered manually',
              },
              showChevron: false,
            ),
          ],
        ),
        if (data.photos.isNotEmpty) ...[
          const SectionHeader(title: 'Photos'),
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
                        ? Image.file(File(p.localPath!), fit: BoxFit.cover, semanticLabel: 'Activity photo ${i + 1}')
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
      return const StatusBanner(
        tone: BannerTone.info,
        title: 'Splits need GPS',
        message: 'Splits are calculated from GPS points. This activity has no usable GPS route.',
      );
    }
    final splitM = f.distanceUnit == DistanceUnit.km ? 1000.0 : metersPerMile;
    final splits = computeSplits(data.points, splitM: splitM);
    if (splits.isEmpty) {
      return const StatusBanner(tone: BannerTone.info, title: 'No splits yet', message: 'This activity is too short to calculate splits.');
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
                SizedBox(width: 56, child: Text(unit == 'km' ? 'Km' : 'Mile', style: StrideText.label)),
                Expanded(child: Text('Pace (${f.paceUnitLabel})', style: StrideText.label)),
                SizedBox(
                  width: 72,
                  child: Text('Time', style: StrideText.label, textAlign: TextAlign.end),
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
                      ? 'Final partial split, ${f.distance(s.distanceM)}, pace $paceText, time ${formatDuration(s.movingMs)}'
                      : 'Split ${s.index + 1}, pace $paceText, time ${formatDuration(s.movingMs)}',
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
            child: Text('Splits use GPS moving time only. Paused time and GPS gaps are not counted.', style: StrideText.caption),
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

    final pace = data.hasRoute ? convertX(paceSeries(data.points)) : const ChartSeries.unavailable('Pace charts need a GPS route. This activity has none.');
    final elevation = data.hasRoute ? convertX(elevationSeries(data.points)) : const ChartSeries.unavailable('Elevation needs a GPS route with altitude data.');
    final hr = heartRateSeries(data.heartRate, a.startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeriesChartCard(
          title: 'Pace',
          series: pace,
          xLabel: unit,
          yLabel: 'min/$unit',
          invertY: true,
          formatY: (v) => f.paceValue(v),
          formatX: fmtX,
          helper: 'Pace over distance, from GPS.',
          semanticSummary: 'Pace chart. Average pace ${f.pace(a.avgPaceSecPerKm)}.',
        ),
        const SizedBox(height: 12),
        SeriesChartCard(
          title: 'Elevation',
          series: elevation,
          xLabel: unit,
          yLabel: 'm',
          formatY: (v) => v.toStringAsFixed(0),
          formatX: fmtX,
          semanticSummary: 'Elevation chart in meters over distance.',
        ),
        const SizedBox(height: 12),
        SeriesChartCard(
          title: 'Heart rate',
          series: hr,
          xLabel: 'min',
          yLabel: 'bpm',
          formatY: (v) => v.toStringAsFixed(0),
          formatX: (v) => v.toStringAsFixed(0),
          semanticSummary: 'Heart rate chart in beats per minute over time.',
        ),
      ],
    );
  }
}
