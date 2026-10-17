import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'explore_repository.dart';

/// Màn lỗi Explore theo nguyên nhân; hết phiên/khách → CTA đăng nhập.
class ExploreFailureView extends StatelessWidget {
  const ExploreFailureView({super.key, required this.failure, this.onRetry, this.signInLabel = 'Sign in'});
  final ExploreFailure failure;
  final VoidCallback? onRetry;
  final String signInLabel;

  @override
  Widget build(BuildContext context) {
    if (failure.kind == ExploreErrorKind.signedOut) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: failure.title,
        message: failure.userMessage,
        actionLabel: signInLabel,
        onAction: () => context.push(Routes.login),
      );
    }
    final retry = failure.kind == ExploreErrorKind.notConfigured || failure.kind == ExploreErrorKind.notFound ? null : onRetry;
    return EmptyState(
      icon: failure.kind == ExploreErrorKind.offline ? Icons.cloud_off_outlined : Icons.error_outline,
      title: failure.title,
      message: failure.userMessage,
      actionLabel: retry == null ? null : 'Try again',
      onAction: retry,
    );
  }
}

/// Khách chưa đăng nhập: mọi API Explore yêu cầu tài khoản → hiện CTA thay vì gọi API.
class ExploreGuestGate extends ConsumerWidget {
  const ExploreGuestGate({super.key, required this.title, required this.message, required this.child, this.icon = Icons.groups_outlined});
  final String title;
  final String message;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ownerProvider).isGuest) return child;
    return EmptyState(icon: icon, title: title, message: message, actionLabel: 'Sign in', onAction: () => context.push(Routes.login));
  }
}

void showExploreError(BuildContext context, Object e) {
  final f = mapExploreError(e);
  showStrideSnack(context, f.kind == ExploreErrorKind.offline ? 'You’re offline. Try again when connected.' : f.userMessage, isError: true);
}

bool _tzReady = false;

/// Định dạng thời điểm theo múi giờ của sự kiện/challenge (không theo máy), kèm tên tz.
String formatInZone(int utcMs, String tzId, {String pattern = 'EEE, MMM d · h:mm a'}) {
  try {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final loc = tz.getLocation(tzId);
    final t = tz.TZDateTime.fromMillisecondsSinceEpoch(loc, utcMs);
    return '${DateFormat(pattern).format(DateTime(t.year, t.month, t.day, t.hour, t.minute))} ${t.timeZoneName}';
  } catch (_) {
    final t = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true);
    return '${DateFormat(pattern).format(t)} UTC';
  }
}

/// Ngày YYYY-MM-DD → "Oct 18, 2026".
String formatLocalDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('MMM d, y').format(d);
}

/// Hàng tiêu đề lớn đầu màn module.
class ExploreHeader extends StatelessWidget {
  const ExploreHeader({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: StrideText.title),
        Text(subtitle, style: StrideText.bodySecondary),
      ],
    ),
  );
}

/// Nút "Load more" cho phân trang cursor.
class ExploreLoadMore extends StatelessWidget {
  const ExploreLoadMore({super.key, required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: loading ? const CircularProgressIndicator() : TextButton(onPressed: onPressed, child: const Text('Load more')),
    ),
  );
}
