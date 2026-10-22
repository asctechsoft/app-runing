import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../values/tokens.dart';

/// Nút chính cao 52, radius 12. Loading giữ bề rộng và chặn bấm lặp (DS mục 04).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.trailingIcon, this.loading = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? Semantics(
            label: '$label, in progress',
            child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 20)],
            ],
          );
    final btn = FilledButton(onPressed: loading ? () {} : onPressed, child: child);
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Nút phụ: nền subtle, chữ primary.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? StrideColors.disabledBg
              : s.contains(WidgetState.pressed)
              ? StrideColors.borderSubtle
              : StrideColors.subtle,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? StrideColors.disabledText : StrideColors.primary),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Nút viền (vd. "Back to home", "Set up later").
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, required this.onPressed, this.icon, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Nút phá hủy: error + chữ trắng. Luôn đi kèm xác nhận ở nơi gọi.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? StrideColors.disabledBg : StrideColors.error),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        ),
        onPressed: loading ? () {} : onPressed,
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Nút nhấn giữ (Hold to finish / Hold to unlock), mặc định ~800 ms (DS mục 04).
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.onCompleted,
    this.icon,
    this.duration = const Duration(milliseconds: 800),
    this.foreground = StrideColors.error,
    this.background = StrideColors.errorBg,
    this.semanticsHint = 'Press and hold to confirm',
  });

  final String label;
  final VoidCallback onCompleted;
  final IconData? icon;
  final Duration duration;
  final Color foreground;
  final Color background;
  final String semanticsHint;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onCompleted();
        _c.reset();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.semanticsHint,
      // Screen reader: double-tap = xác nhận rõ ràng (thay cho nhấn giữ).
      onTap: widget.onCompleted,
      child: GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) {
          if (_c.status != AnimationStatus.completed) _c.reverse();
        },
        onTapCancel: () => _c.reverse(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(StrideRadius.control),
              border: Border.all(color: widget.foreground, width: 1.5),
              gradient: LinearGradient(colors: [widget.foreground.withValues(alpha: 0.25), widget.background], stops: [_c.value, _c.value]),
              color: widget.background,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, color: widget.foreground, size: 20), const SizedBox(width: 8)],
                Text(widget.label, style: StrideText.label.copyWith(color: widget.foreground, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chặn bấm lặp cho async action (Start/Save): bỏ qua lần bấm khi đang chạy.
class OnceGuard {
  bool _busy = false;
  bool get busy => _busy;

  Future<T?> run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

/// Nút tròn lớn (Pause/Resume khi chạy, ≥ 64).
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 72,
    this.background = StrideColors.primary,
    this.foreground = Colors.white,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

/// Debounce đơn giản cho search.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 350)]);
  final Duration delay;
  Timer? _t;
  void call(VoidCallback f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }

  void dispose() => _t?.cancel();
}
