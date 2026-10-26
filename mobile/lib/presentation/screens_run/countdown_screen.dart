import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/session_state.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../controller/run/engine/run_session_state.dart';
import 'components/run_widgets.dart';

/// Đếm ngược 3–2–1 (G02). Mỗi số đúng 1 s theo Timer, không phụ thuộc animation.
/// Draft + timestamp start chỉ được tạo khi đếm xong; Cancel không tạo hoạt động và không tính thời gian đếm.
class CountdownScreen extends ConsumerStatefulWidget {
  const CountdownScreen({super.key});

  @override
  ConsumerState<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends ConsumerState<CountdownScreen> with SingleTickerProviderStateMixin {
  int _n = 3;
  Timer? _timer;
  bool _starting = false;
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 1))..forward();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(runSessionProvider).phase != SessionPhase.countdown) {
        context.go(Routes.run);
        return;
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
    });
  }

  void _onSecond() {
    if (!mounted) return;
    if (_n > 1) {
      setState(() => _n--);
      _ring.forward(from: 0);
      HapticFeedback.selectionClick();
      return;
    }
    _timer?.cancel();
    _begin();
  }

  Future<void> _begin() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final a = await ref.read(runSessionProvider.notifier).startRecording();
      if (!mounted) return;
      if (a != null || ref.read(runSessionProvider).isActive) {
        HapticFeedback.heavyImpact();
        context.go(Routes.live);
      } else {
        context.go(Routes.run);
      }
    } on RunSessionAlreadyOpen {
      if (mounted) context.go(Routes.recovery);
    } catch (e) {
      if (!mounted) return;
      ref.read(runSessionProvider.notifier).cancelCountdown();
      showStrideSnack(context, 'run_countdown_failed'.tr, isError: true);
      context.go(Routes.run);
    }
  }

  void _cancel() {
    if (_starting) return;
    _timer?.cancel();
    ref.read(runSessionProvider.notifier).cancelCountdown();
    context.go(Routes.run);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(runSessionProvider).setup;
    final fmt = ref.watch(formatProvider);
    final subtitle = [activityTypeLabel(setup.type), if (setup.plan != null) setup.plan!.name else runGoalLabel(setup.goal, fmt)].join(' · ');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                Text('run_countdown_title'.tr, style: StrideText.title),
                const SizedBox(height: 4),
                Text(subtitle, style: StrideText.bodySecondary, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _ring,
                        builder: (context, _) => SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: ((3 - _n) + _ring.value) / 3,
                            strokeWidth: 12,
                            color: StrideColors.primary,
                            backgroundColor: StrideColors.subtle,
                          ),
                        ),
                      ),
                      Semantics(
                        liveRegion: true,
                        label: _starting ? 'run_countdown_starting'.tr : 'run_countdown_starting_in'.trArgs([_n]),
                        excludeSemantics: true,
                        child: Text(_starting ? 'run_countdown_go'.tr : '$_n', style: StrideText.countdown),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
                  child: SecondaryButton(label: 'action_cancel'.tr, onPressed: _starting ? null : _cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
