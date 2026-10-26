import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../values/tokens.dart';

/// Đường dẫn logo chính thức (người chạy trắng + lime trên nền navy, góc bo sẵn). Nguồn icon launcher: `tool/icons/`.
const String strideLogoAsset = 'assets/images/img_logo.png';

/// Logo STRIDE (ảnh chính thức) + wordmark. [size] là cạnh ô logo; không kéo giãn, xoay hay đổi màu.
class StrideLogo extends StatelessWidget {
  const StrideLogo({super.key, this.size = 96, this.showWordmark = true, this.wordmarkColor = StrideColors.iconNavy});
  final double size;
  final bool showWordmark;
  final Color wordmarkColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'STRIDE',
      image: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Vùng an toàn ≥ 16% quanh logo.
          Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: Image.asset(strideLogoAsset, width: size * 0.68, height: size * 0.68, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ),
          if (showWordmark)
            Text(
              'STRIDE',
              style: TextStyle(fontFamily: StrideText.fontFamily, fontWeight: FontWeight.w800, fontSize: size * 0.34, letterSpacing: 1, color: wordmarkColor),
            ),
        ],
      ),
    );
  }
}

/// Wordmark ngang dùng trên header (vd. "STRIDE" ở Home).
class StrideWordmark extends StatelessWidget {
  const StrideWordmark({super.key, this.fontSize = 22});
  final double fontSize;
  @override
  Widget build(BuildContext context) => Text(
    'STRIDE',
    semanticsLabel: 'STRIDE',
    style: TextStyle(fontFamily: StrideText.fontFamily, fontWeight: FontWeight.w800, fontSize: fontSize, letterSpacing: 0.5, color: StrideColors.iconNavy),
  );
}

/// Vòng tiến độ (Home ring, countdown). Giữ bước thực kể cả vượt 100% — chỉ vòng dừng ở 100%.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 200,
    this.stroke = 14,
    this.color = StrideColors.primary,
    this.track = StrideColors.subtle,
    this.semanticLabel,
  });
  final double? progress;
  final Widget child;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, stroke: stroke, color: color, track: track),
        child: Center(child: child),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.stroke, required this.color, required this.track});
  final double? progress;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final p = progress;
    if (p == null || p <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * p.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.color != color;
}
