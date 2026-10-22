import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../controller/run/engine/run_session_controller.dart';
import 'components/run_map.dart';
import 'components/run_widgets.dart';

/// Kết quả sau Finish (G10, K03). Rời màn mà không lưu → draft vẫn ở trạng thái awaitingSave.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _loading = false;
  final _guard = OnceGuard();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final st = ref.read(runSessionProvider);
      if (st.phase == SessionPhase.awaitingSave && st.activity != null) return;
      if (st.isActive) {
        context.go(Routes.live);
        return;
      }
      setState(() => _loading = true);
      try {
        await ref.read(runSessionProvider.notifier).loadOpenSession();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      if (!mounted) return;
      if (ref.read(runSessionProvider).phase == SessionPhase.recoveryNeeded) context.go(Routes.recovery);
    });
  }

  Future<void> _discard() => _guard.run(() async {
    final ok = await confirmDialog(
      context,
      title: 'run_discard_title'.tr,
      message: 'run_results_discard_message'.tr,
      confirmLabel: 'run_discard_confirm'.tr,
      cancelLabel: 'run_discard_keep'.tr,
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(runSessionProvider.notifier).discard();
      if (mounted) context.go(Routes.home);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'run_results_discard_failed'.tr, isError: true);
    }
  });

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(runSessionProvider);
    final fmt = ref.watch(formatProvider);
    final a = st.activity;
    if (_loading) {
      return const StrideScreen(
        showBack: false,
        body: Padding(padding: EdgeInsets.only(top: 24), child: LoadingCard(height: 320)),
      );
    }
    if (a == null || st.phase != SessionPhase.awaitingSave) {
      return StrideScreen(
        showBack: false,
        body: EmptyState(
          title: 'run_results_empty_title'.tr,
          message: 'run_results_empty_message'.tr,
          icon: Icons.inbox_outlined,
          actionLabel: 'run_back_home'.tr,
          onAction: () => context.go(Routes.home),
        ),
      );
    }
    final indoor = a.type == ActivityType.indoorRun;
    final short = a.movingMs < 60000 || (a.distanceM != null && a.distanceM! < 100);
    final title = switch (a.type) {
      ActivityType.walk => 'run_results_walk_done'.tr,
      _ => st.setup.plan != null ? 'run_interval_complete'.tr : 'run_results_run_done'.tr,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Giữ bản nháp; có thể quay lại từ tab Run.
        if (!didPop) context.go(Routes.home);
      },
      child: StrideScreen(
        onBack: () => context.go(Routes.home),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.emoji_events_outlined, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: StrideText.title),
                      Text('${longDate(a.startedAt)} · ${clockTime(a.startedAt)}', style: StrideText.bodySecondary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (short) ...[StatusBanner(tone: BannerTone.warning, message: 'run_results_short'.tr), const SizedBox(height: 12)],
            if (a.hasGps && st.segments.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(StrideRadius.card),
                child: SizedBox(height: 240, child: RunMap(segments: st.segments, showFinish: true, fitRoute: true, follow: false, showRecenter: false)),
              )
            else
              SageCard(
                child: Row(
                  children: [
                    IconBadge(icon: indoor ? Icons.home_outlined : Icons.location_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(child: Text(indoor ? 'run_results_indoor_note'.tr : 'run_results_no_gps'.tr, style: StrideText.body)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            StrideCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MetricTile(
                    label: 'run_label_distance'.tr,
                    value: fmt.distanceValue(a.distanceM),
                    unit: fmt.distanceUnitLabel,
                    large: true,
                    estimated: indoor,
                  ),
                  const Divider(height: 24),
                  Wrap(
                    runSpacing: 16,
                    children: [
                      for (final t in [
                        MetricTile(label: 'run_label_moving_time'.tr, value: formatDuration(a.movingMs), icon: Icons.timer_outlined),
                        MetricTile(label: 'run_label_elapsed_time'.tr, value: formatDuration(a.elapsedMs), icon: Icons.schedule),
                        MetricTile(
                          label: 'run_label_avg_pace'.tr,
                          value: fmt.paceValue(a.avgPaceSecPerKm),
                          unit: a.avgPaceSecPerKm == null ? null : fmt.paceUnitLabel,
                          icon: Icons.speed,
                          estimated: indoor,
                        ),
                        MetricTile(label: 'run_label_steps'.tr, value: fmt.steps(a.steps), icon: Icons.directions_walk),
                        MetricTile(
                          label: 'run_label_calories'.tr,
                          value: a.caloriesKcal == null ? missingValue : a.caloriesKcal!.round().toString(),
                          unit: a.caloriesKcal == null ? null : 'run_unit_kcal'.tr,
                          icon: Icons.local_fire_department_outlined,
                          estimated: true,
                        ),
                      ])
                        FractionallySizedBox(widthFactor: 0.5, child: t),
                    ],
                  ),
                  if (a.caloriesKcal == null) ...[const SizedBox(height: 12), Text('run_results_add_weight'.tr, style: StrideText.caption)],
                ],
              ),
            ),
            if (st.phaseResults != null && st.phaseResults!.isNotEmpty) ...[
              const SizedBox(height: 16),
              StrideCard(
                child: PhaseTable(results: st.phaseResults!, fmt: fmt, incomplete: st.workoutIncomplete),
              ),
            ],
          ],
        ),
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'run_results_continue'.tr, trailingIcon: Icons.arrow_forward, onPressed: () => context.push(Routes.saveActivity)),
            const SizedBox(height: 8),
            OutlineButton(label: 'run_discard'.tr, onPressed: _discard),
          ],
        ),
      ),
    );
  }
}
