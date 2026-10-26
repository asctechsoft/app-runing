import 'package:flutter/material.dart';

import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import 'buttons.dart';

/// Dialog xác nhận: tiêu đề 22, body 16, tối đa 2 tác vụ (DS mục 05).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: destructive ? StrideColors.errorBg : StrideColors.subtle, shape: BoxShape.circle),
                  child: Icon(icon, color: destructive ? StrideColors.error : StrideColors.primary),
                ),
                const SizedBox(height: 16),
              ],
              Text(title, style: StrideText.heading, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: StrideText.bodySecondary, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (destructive)
                DestructiveButton(label: confirmLabel, onPressed: () => Navigator.of(ctx).pop(true))
              else
                PrimaryButton(label: confirmLabel, onPressed: () => Navigator.of(ctx).pop(true)),
              const SizedBox(height: 8),
              SecondaryButton(label: cancelLabel, onPressed: () => Navigator.of(ctx).pop(false)),
            ],
          ),
        ),
      ),
    ),
  );
  return r ?? false;
}

/// Snackbar thông tin ngắn; lỗi quan trọng truyền [actionLabel] (vd. Retry) và giữ lâu hơn.
void showStrideSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, bool isError = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? StrideColors.error : StrideColors.textPrimary,
      duration: Duration(seconds: actionLabel != null ? 8 : 3),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, textColor: StrideColors.lime, onPressed: onAction ?? () {}),
    ),
  );
}

/// Bottom sheet chuẩn (radius 28, padding 20, cuộn khi dài).
Future<T?> showStrideSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: StrideText.heading)),
                IconButton(tooltip: 'common_close'.tr, onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 12),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}
