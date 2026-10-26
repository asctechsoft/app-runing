import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../utils/logger.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../controller/run/engine/run_session_state.dart';
import 'components/run_widgets.dart';

/// Khôi phục phiên chưa chốt (G08): hiển thị checkpoint cuối và khoảng thiếu; Resume / Finish & save / Discard.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  bool _loading = true;
  Object? _error;
  RecoveryInfo? _info;
  final _guard = OnceGuard();
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = ref.read(runSessionProvider);
      if (st.isActive) {
        if (mounted) context.go(Routes.live);
        return;
      }
      final info = await ref.read(runSessionProvider.notifier).loadOpenSession();
      if (!mounted) return;
      if (ref.read(runSessionProvider).phase == SessionPhase.awaitingSave) {
        context.go(Routes.results);
        return;
      }
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e, st) {
      StrideLog.e('run.recovery', e, st);
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _act(String key, Future<void> Function() f) => _guard.run(() async {
    setState(() => _busy = key);
    try {
      await f();
    } catch (e, st) {
      StrideLog.e('run.recovery', e, st);
      if (mounted) showStrideSnack(context, 'run_recovery_error_snack'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  });

  Future<void> _resume() => _act('resume', () async {
    final ok = await ref.read(runSessionProvider.notifier).recover();
    if (ok && mounted) context.go(Routes.live);
  });

  Future<void> _finish() => _act('finish', () async {
    await ref.read(runSessionProvider.notifier).finishRecovered();
    if (mounted) context.go(Routes.results);
  });

  Future<void> _discard() async {
    final ok = await confirmDialog(
      context,
      title: 'run_discard_title'.tr,
      message: 'run_recovery_discard_message'.tr,
      confirmLabel: 'run_discard_confirm'.tr,
      cancelLabel: 'run_discard_keep'.tr,
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    await _act('discard', () async {
      await ref.read(runSessionProvider.notifier).discard();
      if (mounted) context.go(Routes.home);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(formatProvider);
    if (_loading) {
      return const StrideScreen(
        showBack: false,
        body: Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard(height: 300)),
      );
    }
    if (_error != null) {
      return StrideScreen(
        showBack: false,
        body: ErrorState(title: 'run_recovery_check_failed_title'.tr, message: 'run_recovery_check_failed_message'.tr, onRetry: _load),
      );
    }
    final info = _info;
    if (info == null) {
      return StrideScreen(
        showBack: false,
        body: EmptyState(
          title: 'run_recovery_empty_title'.tr,
          message: 'run_recovery_empty_message'.tr,
          icon: Icons.check_circle_outline,
          actionLabel: 'run_back_home'.tr,
          onAction: () => context.go(Routes.home),
        ),
      );
    }
    final a = info.activity;
    final cpAt = info.checkpointAt;
    final indoor = a.type == ActivityType.indoorRun;
    return PopScope(
      canPop: false,
      // Phải chọn một cách xử lý hoạt động dở (không thoát lặng lẽ): Back chỉ nhắc người dùng chọn bên dưới.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showStrideSnack(context, 'run_recovery_back_hint'.tr);
      },
      child: StrideScreen(
        showBack: false,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Center(child: IconBadge(icon: Icons.restore, size: 72)),
            const SizedBox(height: 16),
            Text('run_recovery_title'.tr, style: StrideText.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              cpAt == null ? 'run_recovery_stopped'.tr : 'run_recovery_stopped_at'.trArgs([clockTime(cpAt)]),
              style: StrideText.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            StrideCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('run_recovery_started'.trArgs([activityTypeLabel(a.type), clockTime(a.startedAt)]), style: StrideText.label),
                  Text(longDate(a.startedAt), style: StrideText.caption),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'run_recovery_distance_saved'.tr,
                          value: fmt.distanceValue(info.distanceM),
                          unit: fmt.distanceUnitLabel,
                          estimated: indoor,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(label: 'run_recovery_moving_saved'.tr, value: formatDuration(info.movingMs)),
                      ),
                      Expanded(
                        child: MetricTile(label: 'run_recovery_last_checkpoint'.tr, value: cpAt == null ? missingValue : clockTime(cpAt)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StatusBanner(
              tone: BannerTone.warning,
              title: 'run_recovery_missing_title'.tr,
              message: cpAt == null ? 'run_recovery_missing_no_cp'.tr : 'run_recovery_missing_after'.trArgs([clockTime(cpAt)]),
            ),
          ],
        ),
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'run_recovery_resume'.tr, icon: Icons.play_arrow, loading: _busy == 'resume', onPressed: _busy == null ? _resume : null),
            const SizedBox(height: 8),
            SecondaryButton(label: 'run_recovery_finish'.tr, onPressed: _busy == null ? _finish : null),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy == null ? _discard : null,
              style: TextButton.styleFrom(foregroundColor: StrideColors.error, minimumSize: const Size(48, 48)),
              child: Text('run_discard'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
