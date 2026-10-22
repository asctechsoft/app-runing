import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../services/native/permission_coordinator.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../controller/run/engine/run_session_state.dart' show activityTypeLabel;
import '../../controller/live/live_share_providers.dart';
import '../../controller/run/engine/run_sources.dart';
import 'components/run_map.dart';
import 'components/run_widgets.dart';

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
          title: 'run_prepare_motion_title'.tr,
          message: 'run_prepare_motion_message'.tr,
          confirmLabel: 'run_start_anyway'.tr,
          cancelLabel: 'run_not_now'.tr,
          icon: Icons.directions_walk,
        );
        if (!go) return;
      }
    } else {
      if (!_locationOk) {
        await _requestLocation();
        if (!_locationOk) {
          if (mounted) showStrideSnack(context, 'run_prepare_allow_location'.tr, isError: true);
          return;
        }
      }
      if (!_serviceOn) {
        if (mounted) {
          showStrideSnack(
            context,
            'run_prepare_services_snack'.tr,
            actionLabel: 'run_settings'.tr,
            onAction: () => ref.read(runLocationSourceProvider).openLocationSettings(),
            isError: true,
          );
        }
        return;
      }
      if (_fix == null && mounted) {
        final go = await confirmDialog(
          context,
          title: 'run_prepare_no_gps_title'.tr,
          message: 'run_prepare_no_gps_message'.tr,
          confirmLabel: 'run_start_anyway'.tr,
          cancelLabel: 'run_prepare_wait_gps'.tr,
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
        ? 'run_off'.tr
        : 'run_prepare_audio_every'.trArgs([cues.everyKm == cues.everyKm.roundToDouble() ? cues.everyKm.round() : cues.everyKm, fmt.distanceUnitLabel]);
    final gps = _fix == null ? GpsQuality.searching : qualityForAccuracy(_fix!.accuracyM);
    final g = StrideScreen.gutterOf(context);
    final startLabel = setup.plan != null
        ? 'run_prepare_start_workout'.tr
        : setup.type == ActivityType.walk
        ? 'run_prepare_start_walk'.tr
        : 'run_prepare_start_run'.tr;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(g, 16, g, 24),
              children: [
                Text('run_prepare_title'.tr, style: StrideText.title),
                Text(longDate(ref.read(clockProvider).nowMs()), style: StrideText.bodySecondary),
                const SizedBox(height: 16),
                if (st.isActive) ...[
                  StatusBanner(
                    tone: BannerTone.info,
                    title: 'run_prepare_active_title'.tr,
                    message: 'run_prepare_active_message'.tr,
                    actionLabel: 'run_prepare_return'.tr,
                    onAction: () => context.go(Routes.live),
                  ),
                  const SizedBox(height: 12),
                ] else if (st.phase == SessionPhase.awaitingSave) ...[
                  StatusBanner(
                    tone: BannerTone.warning,
                    title: 'run_prepare_unsaved_title'.tr,
                    message: 'run_prepare_unsaved_message'.tr,
                    actionLabel: 'run_prepare_review'.tr,
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
                              Text('run_prepare_indoor_title'.tr, style: StrideText.label),
                              Text(
                                settings?.heightCm == null ? 'run_prepare_indoor_no_height'.tr : 'run_prepare_indoor_estimated'.tr,
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
                        title: 'run_prepare_perm_title'.tr,
                        message: 'run_prepare_perm_message'.tr,
                        actionLabel: (_perm == PermStatus.blocked || _perm == PermStatus.restricted) ? 'run_prepare_open_settings'.tr : 'run_prepare_allow'.tr,
                        onAction: _requestLocation,
                        icon: Icons.location_off_outlined,
                      ),
                    )
                  else ...[
                    if (!_serviceOn) ...[
                      StatusBanner(
                        tone: BannerTone.warning,
                        title: 'run_prepare_services_title'.tr,
                        message: 'run_prepare_services_message'.tr,
                        actionLabel: 'run_prepare_turn_on'.tr,
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
                        message: 'run_prepare_precise_off'.tr,
                        actionLabel: 'run_settings'.tr,
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
                      subtitle: indoor ? 'run_prepare_type_indoor'.tr : 'run_prepare_type_outdoor'.tr,
                      onTap: () => context.push(Routes.runActivity),
                    ),
                    SettingsRow(
                      icon: Icons.flag_outlined,
                      title: 'run_prepare_row_goal'.tr,
                      subtitle: runGoalLabel(setup.goal, fmt),
                      onTap: () => context.push(Routes.runGoal),
                    ),
                    if (flags.workoutIntervals)
                      SettingsRow(
                        icon: Icons.timer_outlined,
                        title: 'run_prepare_row_workout'.tr,
                        subtitle: workoutLabel(setup.plan),
                        onTap: () => context.push(Routes.runWorkout),
                      ),
                    SettingsRow(
                      icon: Icons.volume_up_outlined,
                      title: 'run_prepare_row_audio'.tr,
                      subtitle: audioLabel,
                      onTap: () => context.push(Routes.runAudio),
                    ),
                    if (flags.liveSharing)
                      SettingsRow(
                        icon: Icons.share_location_outlined,
                        title: 'run_prepare_row_live'.tr,
                        subtitle: _liveShareLabel(ref),
                        onTap: () => context.push(Routes.runLiveShare),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: st.isActive ? 'run_prepare_return_activity'.tr : startLabel, trailingIcon: Icons.arrow_forward, onPressed: _start),
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
  if (!c.enabled || c.consentedAt == null || c.viewers.isEmpty) return 'run_off'.tr;
  final n = c.viewers.length;
  return (n == 1 ? 'run_prepare_live_one' : 'run_prepare_live_many').trArgs([n]);
}
