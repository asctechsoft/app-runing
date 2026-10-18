import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/calc/run_metrics.dart';
import '../../domain/models/profile.dart';
import '../../domain/session/session_state.dart';
import 'engine/run_session_controller.dart';
import 'engine/run_session_state.dart';
import 'engine/run_sources.dart';
import 'widgets/run_map.dart';
import 'widgets/run_widgets.dart';

/// Màn ghi (G06, G09): Metrics/Map (swipe + toggle), Pause, Lock, Paused, Finish dialog.
/// Back không kết thúc phiên; bottom tab đã ẩn vì route nằm ngoài shell.
class LiveRunScreen extends ConsumerStatefulWidget {
  const LiveRunScreen({super.key});

  @override
  ConsumerState<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends ConsumerState<LiveRunScreen> {
  final _pages = PageController();
  int _page = 0;
  Timer? _ticker;
  final _guard = OnceGuard();

  @override
  void initState() {
    super.initState();
    // Chỉ để vẽ lại đồng hồ; thời gian thật lấy từ controller (đồng hồ đơn điệu).
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfNotActive());
  }

  void _redirectIfNotActive() {
    if (!mounted) return;
    final st = ref.read(runSessionProvider);
    if (st.isActive) return;
    if (st.phase == SessionPhase.awaitingSave) {
      context.go(Routes.results);
    } else if (st.phase == SessionPhase.recoveryNeeded) {
      context.go(Routes.recovery);
    } else {
      context.go(Routes.run);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _goPage(int i) {
    setState(() => _page = i);
    _pages.animateToPage(i, duration: StrideMotion.screen, curve: Curves.easeOut);
  }

  Future<void> _confirmFinish() async {
    final ctl = ref.read(runSessionProvider.notifier);
    final st = ref.read(runSessionProvider);
    final fmt = ref.read(formatProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconBadge(icon: Icons.pause, size: 48),
                const SizedBox(height: 12),
                Text('Finish this run?', style: StrideText.heading, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Distance',
                        value: fmt.distanceValue(st.distanceM),
                        unit: fmt.distanceUnitLabel,
                        center: true,
                        estimated: st.isIndoor,
                      ),
                    ),
                    Expanded(
                      child: MetricTile(label: 'Moving time', value: formatDuration(ctl.movingMsNow()), center: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('You can review and save your activity next.', style: StrideText.bodySecondary, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Finish & review', onPressed: () => Navigator.of(ctx).pop(true)),
                const SizedBox(height: 8),
                SecondaryButton(label: 'Keep paused', onPressed: () => Navigator.of(ctx).pop(false)),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _guard.run(() async {
      try {
        await ctl.finish();
        if (mounted) context.go(Routes.results);
      } catch (e) {
        if (mounted) showStrideSnack(context, 'Couldn\'t finish the activity. Your recording is safe — try again.', isError: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(runSessionProvider);
    final ctl = ref.read(runSessionProvider.notifier);
    final fmt = ref.watch(formatProvider);
    final settings = ref.watch(settingsProvider).value;

    ref.listen(runSessionProvider.select((s) => s.targetReached), (prev, next) {
      if (prev == false && next == true) showStrideSnack(context, 'Target reached! Keep going, or finish when you\'re ready.');
    });
    ref.listen(runSessionProvider.select((s) => s.phase), (prev, next) {
      if (next != SessionPhase.recording && next != SessionPhase.paused) _redirectIfNotActive();
    });

    final moving = ctl.movingMsNow();
    final avgPace = avgPaceSecPerKm(movingMs: moving, distanceM: st.distanceM);
    final m = _Metrics(
      time: formatDuration(moving),
      distance: fmt.distanceValue(st.distanceM),
      unit: fmt.distanceUnitLabel,
      avgPace: fmt.paceValue(avgPace),
      curPace: fmt.paceValue(st.currentPaceSecPerKm),
      paceUnit: fmt.paceUnitLabel,
      steps: fmt.steps(st.steps),
      kcal: st.caloriesKcal == null ? missingValue : st.caloriesKcal!.round().toString(),
      estimatedDistance: st.isIndoor,
    );

    final Widget body;
    if (st.locked) {
      body = _LockedView(m: m, st: st, onUnlock: ctl.unlock);
    } else if (st.phase == SessionPhase.paused) {
      body = _PausedView(m: m, st: st, ctl: ctl, onFinish: _confirmFinish, settings: settings, fmt: fmt);
    } else {
      body = _recording(st, ctl, m, fmt, settings);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back không kết thúc phiên ghi.
        if (!st.locked) showStrideSnack(context, 'Pause first, then hold to finish.');
      },
      child: body,
    );
  }

  Widget _recording(RunSessionState st, RunSessionController ctl, _Metrics m, StrideFormat fmt, UserSettings? settings) {
    final g = StrideScreen.gutterOf(context);
    final everyM = fmt.distanceUnit == DistanceUnit.km ? 1000.0 : metersPerMile;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(g, 8, g, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GpsStatusChip(quality: st.gps),
                    ),
                  ),
                  if (!st.isIndoor)
                    SizedBox(
                      width: 180,
                      child: StrideSegmented<int>(
                        dense: true,
                        values: const [0, 1],
                        selected: _page,
                        labelOf: (i) => i == 0 ? 'Metrics' : 'Map',
                        onChanged: _goPage,
                      ),
                    ),
                ],
              ),
            ),
            if (st.gps == GpsQuality.lost && !st.isIndoor)
              Padding(
                padding: EdgeInsets.fromLTRB(g, 8, g, 0),
                child: StatusBanner(
                  tone: BannerTone.warning,
                  title: 'GPS signal lost',
                  message: st.lastFixWallMs == null
                      ? 'Time is still recording. Distance resumes when GPS returns.'
                      : 'Last known location at ${clockTime(st.lastFixWallMs!)}. Time is still recording.',
                ),
              ),
            if (st.interval != null)
              Padding(
                padding: EdgeInsets.fromLTRB(g, 8, g, 0),
                child: _IntervalCard(status: st.interval!),
              ),
            Expanded(
              child: st.isIndoor
                  ? _MetricsPage(m: m)
                  : PageView(
                      controller: _pages,
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [
                        _MetricsPage(m: m),
                        Column(
                          children: [
                            Expanded(
                              child: RunMap(
                                segments: st.segments,
                                markerEveryM: everyM,
                                current: st.lastFix == null
                                    ? null
                                    : RunMapCurrent(
                                        lat: st.lastFix!.lat,
                                        lon: st.lastFix!.lon,
                                        accuracyM: st.lastFix!.accuracyM,
                                        stale: st.gps == GpsQuality.lost,
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: RunMetric(value: m.distance, unit: m.unit, label: 'Distance', estimated: m.estimatedDistance),
                                  ),
                                  Expanded(
                                    child: RunMetric(value: m.time, label: 'Moving time'),
                                  ),
                                  Expanded(
                                    child: RunMetric(value: m.avgPace, unit: m.avgPace == missingValue ? null : m.paceUnit, label: 'Avg. pace'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            if (!st.isIndoor)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      margin: const EdgeInsets.all(4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? StrideColors.primary : StrideColors.borderSubtle),
                    ),
                ],
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(g, 8, g, 16),
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  RoundActionButton(icon: Icons.pause, label: 'Pause', size: 80, onPressed: ctl.pause),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 52,
                        child: OutlineButton(label: 'Lock', icon: Icons.lock_outline, expand: false, onPressed: ctl.lock),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metrics {
  const _Metrics({
    required this.time,
    required this.distance,
    required this.unit,
    required this.avgPace,
    required this.curPace,
    required this.paceUnit,
    required this.steps,
    required this.kcal,
    required this.estimatedDistance,
  });
  final String time;
  final String distance;
  final String unit;
  final String avgPace;
  final String curPace;
  final String paceUnit;
  final String steps;
  final String kcal;
  final bool estimatedDistance;
}

class _MetricsPage extends StatelessWidget {
  const _MetricsPage({required this.m});
  final _Metrics m;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RunMetric(value: m.time, label: 'Moving time', big: true),
                const SizedBox(height: 24),
                RunMetric(value: m.distance, unit: m.unit, label: 'Distance', big: true, estimated: m.estimatedDistance),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: RunMetric(value: m.avgPace, unit: m.avgPace == missingValue ? null : m.paceUnit, label: 'Avg. pace'),
                    ),
                    Expanded(
                      child: RunMetric(value: m.curPace, unit: m.curPace == missingValue ? null : m.paceUnit, label: 'Current pace'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: RunMetric(value: m.steps, label: 'Steps'),
                    ),
                    Expanded(
                      child: RunMetric(value: m.kcal, unit: m.kcal == missingValue ? null : 'kcal', label: 'Calories', estimated: true),
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
}

class _IntervalCard extends StatelessWidget {
  const _IntervalCard({required this.status});
  final IntervalStatus status;

  @override
  Widget build(BuildContext context) {
    final cur = status.current;
    return SageCard(
      semanticLabel: cur == null ? 'Workout complete' : '${cur.label}, ${formatDuration(status.position.remainingMs)} left',
      child: Row(
        children: [
          IconBadge(icon: cur == null ? Icons.check : Icons.timer_outlined, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cur?.label ?? 'Workout complete', style: StrideText.label),
                Text(
                  cur == null ? 'Keep going, or finish when you\'re ready.' : (status.next == null ? 'Last phase' : 'Next: ${status.next!.label}'),
                  style: StrideText.caption,
                ),
              ],
            ),
          ),
          if (cur != null) Text(formatDuration(status.position.remainingMs), style: StrideText.metricMedium),
        ],
      ),
    );
  }
}

class _PausedView extends StatelessWidget {
  const _PausedView({required this.m, required this.st, required this.ctl, required this.onFinish, required this.settings, required this.fmt});
  final _Metrics m;
  final RunSessionState st;
  final RunSessionController ctl;
  final VoidCallback onFinish;
  final UserSettings? settings;
  final StrideFormat fmt;

  @override
  Widget build(BuildContext context) {
    final g = StrideScreen.gutterOf(context);
    final auto = st.pauseKind == PauseKind.auto;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: auto ? 'Paused automatically' : 'Paused',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: StrideColors.warningBg, borderRadius: BorderRadius.circular(StrideRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pause_circle_filled, color: StrideColors.warning, size: 20),
                    const SizedBox(width: 6),
                    Text('Paused', style: StrideText.label.copyWith(color: StrideColors.warning)),
                  ],
                ),
              ),
            ),
            if (!st.isIndoor && st.segments.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(g, 12, g, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(StrideRadius.card),
                    child: RunMap(
                      segments: st.segments,
                      follow: false,
                      current: st.lastFix == null ? null : RunMapCurrent(lat: st.lastFix!.lat, lon: st.lastFix!.lon, stale: true),
                    ),
                  ),
                ),
              )
            else
              const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(g, 16, g, 0),
              child: Column(
                children: [
                  Text('Take your time', style: StrideText.heading),
                  Text('Time and distance are paused.', style: StrideText.bodySecondary),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: RunMetric(value: m.time, label: 'Moving time'),
                      ),
                      Expanded(
                        child: RunMetric(value: m.distance, unit: m.unit, label: 'Distance', estimated: m.estimatedDistance),
                      ),
                      Expanded(
                        child: RunMetric(value: m.avgPace, unit: m.avgPace == missingValue ? null : m.paceUnit, label: 'Avg. pace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'Resume', icon: Icons.play_arrow, onPressed: ctl.resume),
                  const SizedBox(height: 12),
                  HoldButton(label: 'Hold to finish', icon: Icons.stop_circle_outlined, onCompleted: onFinish),
                  const SizedBox(height: 8),
                  Text(auto ? 'Paused automatically · resumes when you move' : 'Paused manually', style: StrideText.caption),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Màn khóa: nền navy, chữ trắng, nhấn lime; ghi vẫn chạy (G06).
class _LockedView extends StatelessWidget {
  const _LockedView({required this.m, required this.st, required this.onUnlock});
  final _Metrics m;
  final RunSessionState st;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    const fg = StrideColors.surface;
    return Scaffold(
      backgroundColor: StrideColors.iconNavy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, color: StrideColors.lime, size: 18),
                  const SizedBox(width: 6),
                  Text(st.phase == SessionPhase.paused ? 'Locked · paused' : 'Locked · recording', style: StrideText.label.copyWith(color: StrideColors.lime)),
                ],
              ),
              const Spacer(),
              RunMetric(value: m.time, label: 'Moving time', big: true, color: fg),
              const SizedBox(height: 24),
              RunMetric(value: m.distance, unit: m.unit, label: 'Distance', big: true, color: StrideColors.lime, estimated: m.estimatedDistance),
              const SizedBox(height: 24),
              RunMetric(value: m.avgPace, unit: m.avgPace == missingValue ? null : m.paceUnit, label: 'Avg. pace', color: fg),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
                child: HoldButton(
                  label: 'Hold to unlock',
                  icon: Icons.lock_open,
                  foreground: StrideColors.lime,
                  background: StrideColors.iconNavy,
                  onCompleted: onUnlock,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
