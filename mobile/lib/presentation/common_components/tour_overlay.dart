import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/tour/tour_controller.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';

/// Gắn một lần phía trên navigator (`MaterialApp.builder`) để làm nổi bật widget ở mọi route. Không vẽ gì khi tour không chạy.
class TourOverlay extends ConsumerWidget {
  const TourOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(tourControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        children: [
          child,
          if (controller.active) _TourStepView(controller: controller),
        ],
      ),
    );
  }
}

class _TourStepView extends StatefulWidget {
  const _TourStepView({required this.controller});

  final TourController controller;

  @override
  State<_TourStepView> createState() => _TourStepViewState();
}

class _TourStepViewState extends State<_TourStepView> with SingleTickerProviderStateMixin {
  static const double _gap = 22; // giữa vùng sáng và bong bóng (mũi tên nằm ở đây)
  static const double _arrowW = 26;
  static const double _arrowH = 14;
  static const double _margin = 20;

  // Điều khiển vòng sóng và mũi tên nhấp nhô.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (StrideMotion.reduced(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final step = controller.step;
    final target = controller.anchorRect(step.anchorId);
    final size = MediaQuery.of(context).size;

    if (target == null) {
      // Chưa layout (vừa đăng ký trong frame này): thử lại ở frame sau.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }

    final below = target.center.dy < size.height / 2;
    const accent = StrideColors.primary;
    final slide = StrideMotion.of(context, const Duration(milliseconds: 500));

    // Bước đầu: lớp phủ mờ dần vào và vùng sáng thu về mục tiêu. Các bước sau: vùng sáng trượt từ mục tiêu cũ sang mới.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: slide,
      curve: Curves.easeOut,
      builder: (context, intro, _) => TweenAnimationBuilder<Rect?>(
        tween: RectTween(end: target.inflate(4)),
        duration: slide,
        curve: Curves.easeInOutCubic,
        builder: (context, rect, _) => Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.next,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _HolePainter(rect: rect!, radius: step.radius, intro: intro, pulse: _pulse.value, color: StrideColors.lime),
                    ),
                  ),
                ),
              ),
              _arrow(size, target, below),
              _bubble(size, target, below, step, controller, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrow(Size size, Rect target, bool below) {
    final x = (target.center.dx - _arrowW / 2).clamp(_margin + 8, size.width - _margin - 8 - _arrowW);
    final top = below ? target.bottom + (_gap - _arrowH) / 2 : target.top - _gap + (_gap - _arrowH) / 2;
    return Positioned(
      left: x,
      top: top,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final bob = math.sin(_pulse.value * 2 * math.pi) * 2;
            return Transform.translate(offset: Offset(0, below ? -bob : bob), child: child);
          },
          child: CustomPaint(
            size: const Size(_arrowW, _arrowH),
            painter: _ArrowPainter(pointUp: below, color: StrideColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _bubble(Size size, Rect target, bool below, TourStep step, TourController controller, Color accent) {
    final onAccent = StrideText.body.copyWith(color: StrideColors.surface);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(step.titleKey.tr, style: StrideText.subheading.copyWith(color: StrideColors.surface)),
              ),
              if (!controller.isLast)
                TextButton(
                  onPressed: controller.finish,
                  style: TextButton.styleFrom(foregroundColor: StrideColors.surface, minimumSize: const Size(48, 48)),
                  child: Text('tour_skip'.tr),
                ),
            ],
          ),
          Text(step.textKey.tr, style: onAccent),
          const SizedBox(height: 4),
          Text('${controller.index + 1}/${controller.count}', style: StrideText.caption.copyWith(color: StrideColors.surface.withValues(alpha: 0.8))),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: controller.isFirst ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
            children: [
              if (!controller.isFirst)
                TextButton(
                  onPressed: controller.previous,
                  style: TextButton.styleFrom(foregroundColor: StrideColors.surface, minimumSize: const Size(48, 48)),
                  child: Text('tour_back'.tr),
                ),
              FilledButton(
                onPressed: controller.next,
                style: FilledButton.styleFrom(backgroundColor: StrideColors.surface, foregroundColor: accent, minimumSize: const Size(48, 48)),
                child: Text(controller.isLast ? 'tour_done'.tr : 'tour_next'.tr),
              ),
            ],
          ),
        ],
      ),
    );

    return Positioned(
      left: _margin,
      right: _margin,
      top: below ? target.bottom + _gap : null,
      bottom: below ? null : size.height - target.top + _gap,
      child: Align(
        alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: StrideMotion.of(context, const Duration(milliseconds: 300)),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: Offset(0, below ? 0.06 : -0.06), end: Offset.zero).animate(anim),
              child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(anim), child: child),
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(controller.index),
            child: Semantics(container: true, liveRegion: true, child: bubble),
          ),
        ),
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter({required this.rect, required this.radius, required this.intro, required this.pulse, required this.color});

  final Rect rect;
  final double radius;

  /// 0 → 1 khi tour mới hiện.
  final double intro;

  /// 0 → 1 lặp: vòng sóng quanh mục tiêu nở ra rồi mờ đi.
  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Thu dần về mục tiêu; mọi góc cùng một bán kính, chặn theo cạnh ngắn để mục tiêu thấp (nút) thành viên thuốc.
    final hole = rect.inflate((1 - intro) * 24);
    final r = math.min(radius, math.min(hole.width, hole.height) / 2);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(r)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.68 * intro));
    if (intro < 1 || pulse == 0) return;
    final grow = Curves.easeOut.transform(pulse) * 8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole.inflate(grow), Radius.circular(r + grow)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - pulse) * 0.7),
    );
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.rect != rect || old.radius != radius || old.intro != intro || old.pulse != pulse || old.color != color;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.pointUp, required this.color});

  final bool pointUp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pointUp != pointUp || old.color != color;
}
