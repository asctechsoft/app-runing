import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/activity.dart';
import '../../domain/session/session_state.dart';
import 'engine/run_session_controller.dart';
import 'engine/run_session_state.dart' show activityTypeLabel;
import '../live/live_share_providers.dart';
import 'engine/run_sources.dart';
import 'widgets/run_map.dart';
import 'widgets/run_widgets.dart';

/// Màn chuẩn bị (G01). Tab Run và Home "Start a run" cùng vào đây. Mở màn không tạo track/draft.
class RunPrepareScreen extends ConsumerStatefulWidget {
  const RunPrepareScreen({super.key});

  @override
  ConsumerState<RunPrepareScreen> createState() => _RunPrepareScreenState();
}

class _RunPrepareScreenState extends ConsumerState<RunPrepareScreen> with WidgetsBindingObserver {
  PermStatus? _perm;
  bool _serviceOn = true;
  RawFix? _fix;
  StreamSubscription<RawFix>? _preview;
  StreamSubscription<void>? _permSub;
  bool _visible = false;
  bool _appActive = true;
  final _startGuard = OnceGuard();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permSub = ref.read(permissionsProvider).changes.listen((_) => _checkPermission());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(runSessionProvider.notifier).open();
      await _checkPermission();
      await _checkUnfinished();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Chỉ xem trước vị trí khi tab Run đang hiển thị — không theo dõi vị trí khi ở tab khác.
    final visible = TickerMode.of(context);
    if (visible != _visible) {
      _visible = visible;
      _syncPreview();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPreview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview?.cancel();
    _permSub?.cancel();
    super.dispose();
  }

  bool get _locationOk => _perm == PermStatus.granted || _perm == PermStatus.limited;

  void _syncPreview() {
    final setup = ref.read(runSessionProvider).setup;
    final want = _visible && _appActive && _locationOk && _serviceOn && setup.type != ActivityType.indoorRun && !ref.read(runSessionProvider).isActive;
    if (want && _preview == null) {
      _preview = ref
          .read(runLocationSourceProvider)
          .previewPositions()
          .listen(
            (f) {
              if (mounted) setState(() => _fix = f);
            },
            onError: (Object _) {
              if (mounted) setState(() => _fix = null);
            },
          );
    } else if (!want && _preview != null) {
      _preview!.cancel();
      _preview = null;
    }
  }

  Future<void> _checkPermission() async {
    final perms = ref.read(permissionsProvider);
    final s = await perms.status(PermKind.location);
    final on = await perms.locationServiceEnabled();
    if (!mounted) return;
    setState(() {
      _perm = s;
      _serviceOn = on;
    });
    _syncPreview();
  }

  Future<void> _checkUnfinished() async {
    final st = ref.read(runSessionProvider);
    if (st.isActive || st.phase == SessionPhase.awaitingSave) return;
    final owner = ref.read(ownerProvider).ownerId;
    final open = await ref.read(activityRepositoryProvider).openSession(owner);
    if (open != null && mounted) context.go(Routes.recovery);
  }

  Future<void> _requestLocation() async {
    final perms = ref.read(permissionsProvider);
    if (_perm == PermStatus.blocked || _perm == PermStatus.restricted) {
      await perms.openSettings();
    } else {
      await perms.request(PermKind.location);
    }
    await _checkPermission();
  }

  Future<void> _start() => _startGuard.run(() async {
    final ctl = ref.read(runSessionProvider.notifier);
    final st = ref.read(runSessionProvider);
    if (st.isActive) {
      context.go(Routes.live);
      return;
    }
    if (st.phase == SessionPhase.awaitingSave) {
      context.go(Routes.results);
      return;
    }
    final owner = ref.read(ownerProvider).ownerId;
    if (await ref.read(activityRepositoryProvider).openSession(owner) != null) {
      if (mounted) context.go(Routes.recovery);
      return;
    }
    final perms = ref.read(permissionsProvider);
    if (st.setup.type == ActivityType.indoorRun) {
      // Indoor dùng bước để ước tính quãng đường; không có quyền chuyển động thì chỉ ghi thời gian.
      var motion = await perms.status(PermKind.motion);
      if (motion != PermStatus.granted && motion != PermStatus.limited && motion != PermStatus.blocked) {
        motion = await perms.request(PermKind.motion);
      }
      if (!mounted) return;
      if (motion != PermStatus.granted && motion != PermStatus.limited) {
        final go = await confirmDialog(
          context,
          title: 'Steps aren\'t available',
          message: 'Without motion access, STRIDE can only record time for this indoor run. Distance and steps will show as —.',
          confirmLabel: 'Start anyway',
          cancelLabel: 'Not now',
          icon: Icons.directions_walk,
        );
        if (!go) return;
      }
    } else {
      if (!_locationOk) {
        await _requestLocation();
        if (!_locationOk) {
          if (mounted) showStrideSnack(context, 'Allow location to record your route.', isError: true);
          return;
        }
      }
      if (!_serviceOn) {
        if (mounted) {
          showStrideSnack(
            context,
            'Turn on location services to record your route.',
            actionLabel: 'Settings',
            onAction: () => ref.read(runLocationSourceProvider).openLocationSettings(),
            isError: true,
          );
        }
        return;
      }
      if (_fix == null && mounted) {
        final go = await confirmDialog(
          context,
          title: 'Start without GPS?',
          message: 'We haven\'t found your location yet. Your time starts now, and your route begins when GPS is found.',
          confirmLabel: 'Start anyway',
          cancelLabel: 'Wait for GPS',
          icon: Icons.location_searching,
        );
        if (!go) return;
      }
    }
    if (!mounted) return;
    if (ctl.beginCountdown()) context.go(Routes.countdown);
  });

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(runSessionProvider);
    final flags = ref.watch(flagsProvider);
    final fmt = ref.watch(formatProvider);
    final settings = ref.watch(settingsProvider).value;
    final setup = st.setup;
    final indoor = setup.type == ActivityType.indoorRun && flags.runIndoor;
    final cues = settings?.audioCues;
    final audioLabel = cues == null
        ? '—'
        : !cues.enabled
        ? 'Off'
        : 'Every ${cues.everyKm == cues.everyKm.roundToDouble() ? cues.everyKm.round() : cues.everyKm} ${fmt.distanceUnitLabel}';
    final gps = _fix == null ? GpsQuality.searching : qualityForAccuracy(_fix!.accuracyM);
    final g = StrideScreen.gutterOf(context);
    final startLabel = setup.plan != null
        ? 'Start workout'
        : setup.type == ActivityType.walk
        ? 'Start a walk'
        : 'Start a run';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(g, 16, g, 24),
              children: [
                Text('Ready for a run?', style: StrideText.title),
                Text(longDate(ref.read(clockProvider).nowMs()), style: StrideText.bodySecondary),
                const SizedBox(height: 16),
                if (st.isActive) ...[
                  StatusBanner(
                    tone: BannerTone.info,
                    title: 'Activity in progress',
                    message: 'Your activity is still recording.',
                    actionLabel: 'Return',
                    onAction: () => context.go(Routes.live),
                  ),
                  const SizedBox(height: 12),
                ] else if (st.phase == SessionPhase.awaitingSave) ...[
                  StatusBanner(
                    tone: BannerTone.warning,
                    title: 'Your last activity isn\'t saved',
                    message: 'Review it to save or discard.',
                    actionLabel: 'Review',
                    onAction: () => context.go(Routes.results),
                  ),
                  const SizedBox(height: 12),
                ],
                if (indoor)
                  SageCard(
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.home_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Indoor run doesn\'t use GPS', style: StrideText.label),
                              Text(
                                settings?.heightCm == null
                                    ? 'No route map. Add your height in Edit profile to estimate distance from steps.'
                                    : 'No route map. Distance is estimated from your steps.',
                                style: StrideText.bodySecondary.copyWith(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_perm != null && !_locationOk)
                    StrideCard(
                      child: PermissionState(
                        title: 'Location is off for STRIDE',
                        message: 'Allow location to map your route. STRIDE uses location only while you record an activity.',
                        actionLabel: (_perm == PermStatus.blocked || _perm == PermStatus.restricted) ? 'Open settings' : 'Allow location',
                        onAction: _requestLocation,
                        icon: Icons.location_off_outlined,
                      ),
                    )
                  else ...[
                    if (!_serviceOn) ...[
                      StatusBanner(
                        tone: BannerTone.warning,
                        title: 'Location services are off',
                        message: 'Turn them on to record your route.',
                        actionLabel: 'Turn on',
                        onAction: () async {
                          await ref.read(runLocationSourceProvider).openLocationSettings();
                          await _checkPermission();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(StrideRadius.card),
                      child: SizedBox(
                        height: 260,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: RunMap(
                                current: _fix == null ? null : RunMapCurrent(lat: _fix!.lat, lon: _fix!.lon, accuracyM: _fix!.accuracyM),
                              ),
                            ),
                            Positioned(left: 12, top: 12, child: GpsStatusChip(quality: gps)),
                          ],
                        ),
                      ),
                    ),
                    if (_perm == PermStatus.limited) ...[
                      const SizedBox(height: 8),
                      StatusBanner(
                        tone: BannerTone.info,
                        message: 'Precise location is off. Your route and distance may be less accurate.',
                        actionLabel: 'Settings',
                        onAction: () => ref.read(permissionsProvider).openSettings(),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 16),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: setup.type == ActivityType.walk ? Icons.directions_walk : Icons.directions_run,
                      title: activityTypeLabel(setup.type),
                      subtitle: indoor ? 'Treadmill or indoor track, no GPS' : 'Outside with GPS tracking',
                      onTap: () => context.push(Routes.runActivity),
                    ),
                    SettingsRow(icon: Icons.flag_outlined, title: 'Goal', subtitle: runGoalLabel(setup.goal, fmt), onTap: () => context.push(Routes.runGoal)),
                    if (flags.workoutIntervals)
                      SettingsRow(
                        icon: Icons.timer_outlined,
                        title: 'Workout',
                        subtitle: workoutLabel(setup.plan),
                        onTap: () => context.push(Routes.runWorkout),
                      ),
                    SettingsRow(icon: Icons.volume_up_outlined, title: 'Audio updates', subtitle: audioLabel, onTap: () => context.push(Routes.runAudio)),
                    if (flags.liveSharing)
                      SettingsRow(
                        icon: Icons.share_location_outlined,
                        title: 'Live share',
                        subtitle: _liveShareLabel(ref),
                        onTap: () => context.push(Routes.runLiveShare),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: st.isActive ? 'Return to activity' : startLabel, trailingIcon: Icons.arrow_forward, onPressed: _start),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Trạng thái live share thật cho buổi sắp chạy (mặc định Off).
String _liveShareLabel(WidgetRef ref) {
  final c = ref.watch(liveShareConfigProvider);
  if (!c.enabled || c.consentedAt == null || c.viewers.isEmpty) return 'Off';
  final n = c.viewers.length;
  return 'On · $n ${n == 1 ? 'person' : 'people'} can follow';
}
