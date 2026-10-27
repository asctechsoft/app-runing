import 'package:flutter/material.dart';

import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import 'buttons.dart';

/// Trạng thái rỗng: icon/illustration nhỏ, tiêu đề, một câu, CTA (DS mục 08).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.directions_run,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s24, vertical: StrideSpace.s32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(color: StrideColors.subtle, shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: StrideColors.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: StrideText.subheading, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: StrideText.bodySecondary, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            PrimaryButton(label: actionLabel!, onPressed: onAction, trailingIcon: Icons.arrow_forward, expand: false),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[const SizedBox(height: 8), TextButton(onPressed: onSecondary, child: Text(secondaryLabel!))],
        ],
      ),
    );
  }
}

/// Lỗi có nguyên nhân và Retry (không "Something went wrong" chung chung khi biết nguyên nhân).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.title, required this.message, this.onRetry, this.retryLabel, this.exitLabel, this.onExit});
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  /// T07: lối ra rõ ràng trên màn khi màn chặn nút Back (ngoài Retry).
  final String? exitLabel;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: title,
    message: message,
    icon: Icons.error_outline,
    actionLabel: onRetry == null ? null : (retryLabel ?? 'common_try_again'.tr),
    onAction: onRetry,
    secondaryLabel: exitLabel,
    onSecondary: onExit,
  );
}

/// Thiếu quyền: icon + lý do + tác động + Open phone settings / Not now.
class PermissionState extends StatelessWidget {
  const PermissionState({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.onNotNow,
    this.icon = Icons.lock_outline,
  });
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onNotNow;
  final IconData icon;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: title,
    message: message,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
    secondaryLabel: onNotNow == null ? null : 'common_not_now'.tr,
    onSecondary: onNotNow,
  );
}

enum BannerTone { info, success, warning, error }

/// Banner trạng thái luôn có icon + chữ (không truyền trạng thái chỉ bằng màu).
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.tone, required this.message, this.title, this.actionLabel, this.onAction, this.icon});
  final BannerTone tone;
  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  (Color, Color, IconData) get _style => switch (tone) {
    BannerTone.info => (StrideColors.info, StrideColors.infoBg, Icons.info_outline),
    BannerTone.success => (StrideColors.success, StrideColors.successBg, Icons.check_circle_outline),
    BannerTone.warning => (StrideColors.warning, StrideColors.warningBg, Icons.warning_amber_rounded),
    BannerTone.error => (StrideColors.error, StrideColors.errorBg, Icons.error_outline),
  };

  @override
  Widget build(BuildContext context) {
    final (fg, bg, defIcon) = _style;
    return Semantics(
      liveRegion: tone == BannerTone.error || tone == BannerTone.warning,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(StrideRadius.control)),
        child: Row(
          children: [
            Icon(icon ?? defIcon, color: fg, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) Text(title!, style: StrideText.label.copyWith(color: fg)),
                  Text(
                    message,
                    style: StrideText.body.copyWith(color: fg, fontSize: 14, height: 20 / 14),
                  ),
                ],
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton cho khối đã biết kích thước (không nháy số 0).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = StrideRadius.small});
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'common_loading'.tr,
    child: Container(
      height: height,
      width: width,
      decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(radius)),
    ),
  );
}

class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key, this.height = 120});
  final double height;
  @override
  Widget build(BuildContext context) => Skeleton(height: height, radius: StrideRadius.card);
}

/// Nhãn đồng bộ: Saved on this device / Waiting to sync / Synced / Sync error — có icon + chữ.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.state});

  /// local | pending | synced | error
  final String state;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (state) {
      'synced' => (Icons.cloud_done_outlined, 'common_sync_synced'.tr, StrideColors.success),
      'pending' => (Icons.cloud_upload_outlined, 'common_sync_pending'.tr, StrideColors.textSecondary),
      'error' => (Icons.cloud_off_outlined, 'common_sync_error'.tr, StrideColors.error),
      _ => (Icons.phone_android, 'common_sync_local'.tr, StrideColors.textSecondary),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: StrideText.caption.copyWith(color: color)),
      ],
    );
  }
}
