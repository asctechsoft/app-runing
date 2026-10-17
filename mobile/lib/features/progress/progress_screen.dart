import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/clock.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/calc/calories.dart';
import '../../domain/calc/records.dart';
import '../../domain/models/steps.dart';
import '../activity/activity_card.dart';
import '../activity/activity_format.dart';
import 'choose_period_sheet.dart';
import 'period.dart';
import 'progress_chart.dart';
import 'progress_data.dart';
import 'records_service.dart';

typedef ProgressKey = ({ProgressPeriod period, String anchor});

int _weekStartOf(Ref ref) => ref.watch(settingsProvider).value?.weekStart ?? DateTime.monday;

/// Running theo kỳ: cùng data set cho totals, chart, list (I04).
final progressRunningProvider = FutureProvider.autoDispose.family<RunningSummary, ProgressKey>((ref, key) async {
  ref.watch(activityRevisionProvider);
  ref.watch(settingsRepositoryProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final weekStart = _weekStartOf(ref);
  final range = periodFor(key.period, parseDateKey(key.anchor), weekStart);
  return loadRunningSummary(
    activities: ref.watch(activityRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    ownerId: owner,
    range: range,
    now: ref.watch(clockProvider).nowLocal(),
    types: runningTypes(indoor: ref.watch(flagsProvider).runIndoor),
    weekStart: weekStart,
  );
});

final progressStepsProvider = FutureProvider.autoDispose.family<StepsSummary, ProgressKey>((ref, key) async {
  ref.watch(stepRevisionProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final range = periodFor(key.period, parseDateKey(key.anchor), _weekStartOf(ref));
  final perms = ref.watch(permissionsProvider);
  final granted = (await perms.status(PermKind.motion)) == PermStatus.granted;
  return loadStepsSummary(
    steps: ref.watch(stepRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    ownerId: owner,
    range: range,
    now: ref.watch(clockProvider).nowLocal(),
    hasPermission: granted,
  );
});

/// Your progress (I04, F16): Week/Month/Year × Steps/Running đổi tại chỗ, không push stack.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key, this.period, this.kind, this.anchor});
  final String? period;
  final String? kind;
  final String? anchor;

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  late ProgressPeriod _period;
  late ProgressKind _kind;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _applyParams();
  }

  @override
  void didUpdateWidget(covariant ProgressScreen old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period || old.kind != widget.kind || old.anchor != widget.anchor) _applyParams();
  }

  void _applyParams() {
    _period = parseProgressPeriod(widget.period);
    _kind = parseProgressKind(widget.kind);
    final now = ref.read(clockProvider).nowLocal();
    final parsed = widget.anchor == null ? null : DateTime.tryParse(widget.anchor!);
    _anchor = dayOnly(parsed == null || parsed.isAfter(now) ? now : parsed);
  }

  int get _weekStart => ref.read(settingsProvider).value?.weekStart ?? DateTime.monday;

  PeriodRange _range(int weekStart) => periodFor(_period, _anchor, weekStart);

  void _shift(int delta) {
    final r = shiftPeriod(_range(_weekStart), delta, _weekStart);
    setState(() => _anchor = r.start);
  }

  Future<void> _choose(PeriodRange current, DateTime now) async {
    final r = await showChoosePeriodSheet(context, initial: current, weekStart: _weekStart, now: now);
    if (r != null && mounted) {
      setState(() {
        _period = r.period;
        _anchor = r.contains(dayOnly(now)) ? dayOnly(now) : r.start;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = ref.watch(settingsProvider).value?.weekStart ?? DateTime.monday;
    final now = ref.watch(clockProvider).nowLocal();
    final range = _range(weekStart);
    final ongoing = range.contains(dayOnly(now));
    final key = (period: _period, anchor: localDateKey(range.start));
    final g = StrideScreen.gutterOf(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: ListView(
              key: const PageStorageKey('progress-scroll'),
              padding: EdgeInsets.fromLTRB(g, 16, g, 24),
              children: [
                Text('Your progress', style: StrideText.title),
                const SizedBox(height: 12),
                StrideSegmented<ProgressPeriod>(
                  values: ProgressPeriod.values,
                  selected: _period,
                  labelOf: (p) => switch (p) {
                    ProgressPeriod.week => 'Week',
                    ProgressPeriod.month => 'Month',
                    ProgressPeriod.year => 'Year',
                  },
                  onChanged: (p) => setState(() {
                    _period = p;
                    if (!_range(weekStart).contains(_anchor)) _anchor = dayOnly(now);
                  }),
                ),
                Row(
                  children: [
                    IconButton(tooltip: 'Previous ${periodNoun(_period)}', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _choose(range, now),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(periodLabel(range), style: StrideText.label.copyWith(fontSize: 16))),
                            const SizedBox(width: 4),
                            const Icon(Icons.calendar_today_outlined, size: 16),
                          ],
                        ),
                      ),
                    ),
                    IconButton(tooltip: 'Next ${periodNoun(_period)}', onPressed: ongoing ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                StrideSegmented<ProgressKind>(
                  values: ProgressKind.values,
                  selected: _kind,
                  dense: true,
                  labelOf: (k) => k == ProgressKind.steps ? 'Steps' : 'Running',
                  onChanged: (k) => setState(() => _kind = k),
                ),
                if (ongoing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('This ${periodNoun(_period)} through ${DateFormat('EEE, MMM d', 'en_US').format(now)}', style: StrideText.caption),
                  ),
                const SizedBox(height: 12),
                if (_kind == ProgressKind.running) _RunningSection(progressKey: key, now: now) else _StepsSection(progressKey: key, now: now),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RunningSection extends ConsumerWidget {
  const _RunningSection({required this.progressKey, required this.now});
  final ProgressKey progressKey;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(progressRunningProvider(progressKey));
    final f = ref.watch(formatProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Column(children: [LoadingCard(height: 96), SizedBox(height: 12), LoadingCard(height: 220)]),
      error: (_, _) => ErrorState(
        title: 'Couldn\'t load your running stats',
        message: 'Reading activities saved on this device failed.',
        onRetry: () => ref.invalidate(progressRunningProvider(progressKey)),
      ),
      data: (s) {
        final p = s.range.period;
        final noun = periodNoun(p);
        final t = s.totals;
        final pace = s.paceSecPerKm;
        final runsTitle = switch (p) {
          ProgressPeriod.week => 'Runs this week',
          ProgressPeriod.month => 'Runs this month',
          ProgressPeriod.year => 'Runs this year',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SageCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(icon: Icons.route_outlined, value: f.distanceValue(t.distanceM), unit: f.distanceUnitLabel, label: 'Total distance'),
                      ),
                      Expanded(
                        child: MetricTile(icon: Icons.directions_run, value: '${t.count}', label: t.count == 1 ? 'Run' : 'Runs'),
                      ),
                      Expanded(
                        child: MetricTile(icon: Icons.timer_outlined, value: formatDurationShort(t.movingMs), label: 'Moving time'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    label: 'Average pace ${f.pace(pace)}, from total moving time and GPS distance',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        const Icon(Icons.speed, size: 18, color: StrideColors.primary),
                        const SizedBox(width: 6),
                        Text('Avg. pace ${f.pace(pace)}', style: StrideText.label),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('total time ÷ GPS distance', style: StrideText.caption, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StrideCard(
              child: ProgressBarChart(
                period: p,
                buckets: s.buckets,
                today: now,
                toDisplay: f.metersToUnit,
                formatValue: (v) => v == null ? missingValue : f.distance(v),
                semanticTitle: 'Distance per ${p == ProgressPeriod.year ? 'month' : 'day'}',
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _GoalCard(summary: s)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ComparisonCard(summary: s, now: now),
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: runsTitle,
              actionLabel: t.count > 0 ? 'View all' : null,
              onAction: () {
                final uri = Uri(path: Routes.progressRuns, queryParameters: {'from': '${s.range.fromMs}', 'to': '${s.range.toMs}', 'title': runsTitle});
                context.push(uri.toString());
              },
            ),
            if (s.recent.isEmpty)
              StrideCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No runs this $noun', style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
                    Text('Runs you save will show up here.', style: StrideText.bodySecondary),
                    if (s.range.contains(dayOnly(now))) ...[
                      const SizedBox(height: 12),
                      PrimaryButton(label: 'Start a run', expand: false, onPressed: () => context.go(Routes.run)),
                    ],
                  ],
                ),
              )
            else
              for (final a in s.recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ActivityCard(activity: a, compact: true),
                ),
            const _RecordsPreview(),
          ],
        );
      },
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.summary});
  final RunningSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(formatProvider);
    final target = summary.target;
    final p = summary.range.period;
    final title = switch (p) {
      ProgressPeriod.week => 'Weekly goal',
      ProgressPeriod.month => 'Monthly target',
      ProgressPeriod.year => 'Yearly target',
    };
    if (target == null) {
      return StrideCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: StrideText.label),
            const SizedBox(height: 4),
            Text('No weekly distance goal set.', style: StrideText.bodySecondary),
            TextButton(onPressed: () => context.go(Routes.profileGoals), child: const Text('Set a goal')),
          ],
        ),
      );
    }
    final progress = summary.totals.distanceM / target;
    final pct = (progress * 100).round();
    return StrideCard(
      semanticLabel: '$title, ${f.distance(summary.totals.distanceM)} of ${f.distance(target)}, $pct percent',
      child: ExcludeSemantics(
        child: Row(
          children: [
            ProgressRing(
              progress: progress,
              size: 56,
              stroke: 6,
              child: const Icon(Icons.flag_outlined, color: StrideColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: StrideText.caption),
                  Text(
                    '${f.distanceValue(summary.totals.distanceM)} / ${f.distance(target)}',
                    style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  Text(p == ProgressPeriod.week ? '$pct% complete' : '$pct% · from weekly goal', style: StrideText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends ConsumerWidget {
  const _ComparisonCard({required this.summary, required this.now});
  final RunningSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(formatProvider);
    final c = summary.comparison;
    final noun = periodNoun(summary.range.period);
    if (c == null) {
      return StrideCard(child: Text('Comparison isn\'t available for this $noun.', style: StrideText.bodySecondary));
    }
    final delta = c.deltaDistanceM;
    final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
    final through = c.coverage.ongoing ? 'Through ${DateFormat('EEEE', 'en_US').format(now)}' : 'Full $noun';
    final text = c.previous.count == 0 && c.current.count == 0 ? missingValue : '$sign${f.distance(delta.abs())}';
    return StrideCard(
      semanticLabel: 'Versus last $noun: $text. $through',
      child: ExcludeSemantics(
        child: Row(
          children: [
            const IconBadge(icon: Icons.trending_up, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: StrideText.label.copyWith(fontSize: 16, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('vs last $noun', style: StrideText.caption),
                  Text(through, style: StrideText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsPreview extends ConsumerWidget {
  const _RecordsPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(personalRecordsProvider);
    final f = ref.watch(formatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Personal records', actionLabel: 'View all', onAction: () => context.push(Routes.records)),
        async.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingCard(height: 80),
          error: (_, _) => Text('Records couldn\'t be calculated right now.', style: StrideText.bodySecondary),
          data: (records) {
            if (records.isEmpty) {
              return StrideCard(child: Text('Save an outdoor run with GPS to start setting records.', style: StrideText.bodySecondary));
            }
            return Row(
              children: [
                for (final r in records.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: StrideCard(
                        padding: const EdgeInsets.all(12),
                        onTap: () => context.push(activityPathFor(context, r.activityId)),
                        semanticLabel: '${recordTitle(r.kind)}, ${formatRecordValue(r, f)}',
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formatRecordValue(r, f),
                                style: StrideText.label.copyWith(fontSize: 16, fontFeatures: const [FontFeature.tabularFigures()]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(recordTitle(r.kind), style: StrideText.caption, maxLines: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Giá trị record: quãng đường hoặc thời gian (không kèm "/km").
String formatRecordValue(PersonalRecord r, StrideFormat f) => r.kind == RecordKind.longestRun ? f.distance(r.value) : formatDuration(r.value.round());

class _StepsSection extends ConsumerWidget {
  const _StepsSection({required this.progressKey, required this.now});
  final ProgressKey progressKey;
  final DateTime now;

  String _sourceLabel(StepSource? s) => switch (s) {
    StepSource.phoneSensor => 'This phone',
    StepSource.healthConnect => 'Health Connect',
    StepSource.healthKit => 'Apple Health',
    StepSource.device => 'Connected device',
    null => 'No step data yet',
  };

  Future<void> _requestPermission(WidgetRef ref) async {
    final perms = ref.read(permissionsProvider);
    final st = await perms.status(PermKind.motion);
    if (st == PermStatus.blocked || st == PermStatus.restricted) {
      await perms.openSettings();
    } else {
      await perms.request(PermKind.motion);
    }
    ref.invalidate(progressStepsProvider(progressKey));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(progressStepsProvider(progressKey));
    final f = ref.watch(formatProvider);
    final settings = ref.watch(settingsProvider).value;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Column(children: [LoadingCard(height: 96), SizedBox(height: 12), LoadingCard(height: 220)]),
      error: (_, _) => ErrorState(
        title: 'Couldn\'t load your steps',
        message: 'Reading steps saved on this device failed.',
        onRetry: () => ref.invalidate(progressStepsProvider(progressKey)),
      ),
      data: (s) {
        if (s.noPermissionAndNoData) {
          return PermissionState(
            icon: Icons.directions_walk,
            title: 'Allow motion access',
            message: 'STRIDE needs Motion & fitness access to count your daily steps. Without it, step stats stay empty.',
            actionLabel: 'Allow access',
            onAction: () => _requestPermission(ref),
          );
        }
        final p = s.range.period;
        final total = s.totalSteps;
        final avg = s.averagePerDay;
        final estDistance = total == null ? null : stepDistanceM(steps: total, heightCm: settings?.heightCm);
        final daysWithData = s.withData.length;
        final lastWithData = s.withData.isEmpty ? null : s.withData.last.date;
        final dateForLink = lastWithData ?? localDateKey(s.days.isEmpty ? s.range.start : parseDateKey(s.days.last.date));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!s.hasPermission)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusBanner(
                  tone: BannerTone.warning,
                  message: 'Motion access is off. New steps aren\'t being counted.',
                  actionLabel: 'Allow',
                  onAction: () => _requestPermission(ref),
                ),
              ),
            SageCard(
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(icon: Icons.directions_walk, value: f.steps(total), label: 'Total steps'),
                  ),
                  Expanded(
                    child: MetricTile(icon: Icons.show_chart, value: f.steps(avg?.round()), label: 'Avg. per day'),
                  ),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.flag_outlined,
                      value: daysWithData == 0 ? missingValue : '${s.goalDaysMet} of $daysWithData',
                      label: 'Goal days met',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StrideCard(
              child: ProgressBarChart(
                period: p,
                buckets: s.buckets,
                today: now,
                toDisplay: (v) => v,
                formatValue: (v) => v == null ? missingValue : '${f.steps(v.round())} steps',
                goalLine: p == ProgressPeriod.year ? null : s.currentDailyGoal,
                goalLabel: s.currentDailyGoal == null || p == ProgressPeriod.year ? null : 'Goal ${f.steps(s.currentDailyGoal!.round())}',
                semanticTitle: 'Steps per ${p == ProgressPeriod.year ? 'month' : 'day'}',
              ),
            ),
            const SizedBox(height: 4),
            Text('Days without step data show —. Only days with data count toward goal days.', style: StrideText.caption),
            const SizedBox(height: 12),
            if (estDistance != null) ...[
              StrideCard(
                child: MetricTile(
                  icon: Icons.route_outlined,
                  value: f.distanceValue(estDistance),
                  unit: f.distanceUnitLabel,
                  label: 'Distance from steps',
                  estimated: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            StrideCard(
              child: Row(
                children: [
                  const Icon(Icons.smartphone, color: StrideColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Source', style: StrideText.caption),
                        Text(_sourceLabel(s.latestSource), style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(Uri(path: Routes.dailySteps, queryParameters: {'date': dateForLink}).toString()),
                    child: const Text('View daily steps'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
