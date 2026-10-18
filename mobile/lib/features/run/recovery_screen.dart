import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/logging/logger.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/activity.dart';
import '../../domain/session/session_state.dart';
import 'engine/run_session_controller.dart';
import 'engine/run_session_state.dart';
import 'widgets/run_widgets.dart';

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
      if (mounted) showStrideSnack(context, 'Something went wrong while recovering. Your data is still on this device.', isError: true);
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
      title: 'Discard this activity?',
      message: 'The recovered route, time and distance will be deleted from this device. This can\'t be undone.',
      confirmLabel: 'Discard activity',
      cancelLabel: 'Keep activity',
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
        body: ErrorState(title: 'Couldn\'t check your last activity', message: 'Your data is still on this device. Try again.', onRetry: _load),
      );
    }
    final info = _info;
    if (info == null) {
      return StrideScreen(
        showBack: false,
        body: EmptyState(
          title: 'Nothing to recover',
          message: 'All your activities are finished.',
          icon: Icons.check_circle_outline,
          actionLabel: 'Back to home',
          onAction: () => context.go(Routes.home),
        ),
      );
    }
    final a = info.activity;
    final cpAt = info.checkpointAt;
    final indoor = a.type == ActivityType.indoorRun;
    return PopScope(
      canPop: false,
      child: StrideScreen(
        showBack: false,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Center(child: IconBadge(icon: Icons.restore, size: 72)),
            const SizedBox(height: 16),
            Text('Your last activity was interrupted', style: StrideText.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              cpAt == null
                  ? 'STRIDE stopped before your activity finished.'
                  : 'STRIDE stopped before your activity finished. We saved it up to ${clockTime(cpAt)}.',
              style: StrideText.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            StrideCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${activityTypeLabel(a.type)} · started ${clockTime(a.startedAt)}', style: StrideText.label),
                  Text(longDate(a.startedAt), style: StrideText.caption),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: MetricTile(label: 'Distance saved', value: fmt.distanceValue(info.distanceM), unit: fmt.distanceUnitLabel, estimated: indoor),
                      ),
                      Expanded(
                        child: MetricTile(label: 'Moving time saved', value: formatDuration(info.movingMs)),
                      ),
                      Expanded(
                        child: MetricTile(label: 'Last checkpoint', value: cpAt == null ? missingValue : clockTime(cpAt)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StatusBanner(
              tone: BannerTone.warning,
              title: 'Missing time',
              message: cpAt == null
                  ? 'Anything after the last saved point wasn\'t recorded and won\'t be counted.'
                  : 'Time and route after ${clockTime(cpAt)} weren\'t recorded and won\'t be counted as moving time.',
            ),
          ],
        ),
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'Resume as new segment', icon: Icons.play_arrow, loading: _busy == 'resume', onPressed: _busy == null ? _resume : null),
            const SizedBox(height: 8),
            SecondaryButton(label: 'Finish & save', onPressed: _busy == null ? _finish : null),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy == null ? _discard : null,
              style: TextButton.styleFrom(foregroundColor: StrideColors.error, minimumSize: const Size(48, 48)),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
  }
}
