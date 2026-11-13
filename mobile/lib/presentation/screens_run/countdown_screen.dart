import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../controller/run/engine/run_sources.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../utils/haptics.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/run_map.dart';
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
  RawFix? _fix;
  StreamSubscription<RawFix>? _preview;
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 1))..forward();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPreview();
      if (ref.read(runSessionProvider).phase != SessionPhase.countdown) {
        context.go(Routes.run);
        return;
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
    });
  }

  /// Chỉ để đặt bản đồ nền đúng chỗ trong 3 giây đếm ngược; ghi vị trí thật chỉ bắt đầu sau đếm xong.
  void _startPreview() {
    if (ref.read(runSessionProvider).setup.type == ActivityType.indoorRun) return;
    _preview = ref.read(runLocationSourceProvider).previewPositions().listen((f) {
      if (mounted) setState(() => _fix = f);
    }, onError: (Object _) {});
  }

  void _onSecond() {
    if (!mounted) return;
    if (_n > 1) {
      setState(() => _n--);
      _ring.forward(from: 0);
      StrideHaptics.selection();
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
        StrideHaptics.heavy();
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
    _preview?.cancel();
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(runSessionProvider).setup;
    final fmt = ref.watch(formatProvider);
    final subtitle = [if (setup.plan != null) setup.plan!.name else runGoalLabel(setup.goal, fmt)].join(' · ');
    final indoor = setup.type == ActivityType.indoorRun;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Nền bản đồ tại vị trí hiện tại (không tương tác); phủ tối nhẹ để số đếm luôn đọc được.
            if (!indoor)
              Positioned.fill(
                child: RunMap(
                  interactive: false,
                  showRecenter: false,
                  initialZoom: 17,
                  current: _fix == null ? null : RunMapCurrent(lat: _fix!.lat, lon: _fix!.lon, accuracyM: _fix!.accuracyM),
                ),
              ),
            Positioned.fill(
              child: ColoredBox(color: StrideColors.iconNavy.withValues(alpha: indoor ? 1 : 0.45)),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(_headline(setup.type), style: StrideText.title.copyWith(color: StrideColors.surface)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: StrideText.bodySecondary.copyWith(color: StrideColors.surface.withValues(alpha: 0.8)),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
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
                                strokeWidth: 10,
                                color: StrideColors.surface,
                                backgroundColor: StrideColors.surface.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          Semantics(
                            liveRegion: true,
                            label: _starting ? 'run_countdown_starting'.tr : 'run_countdown_starting_in'.trArgs([_n]),
                            excludeSemantics: true,
                            child: Text(_starting ? 'run_countdown_go'.tr : '$_n', style: StrideText.countdown.copyWith(color: StrideColors.surface)),
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
          ],
        ),
      ),
    );
  }

  /// Tiêu đề theo loại: "Đang đi bộ" / "Đang chạy bộ" / "Đang đạp xe" (khớp màn ghi ở ảnh thiết kế).
  String _headline(ActivityType t) => switch (t) {
    ActivityType.walk => 'run_countdown_walking'.tr,
    ActivityType.bike => 'run_countdown_biking'.tr,
    _ => 'run_countdown_running'.tr,
  };
}
