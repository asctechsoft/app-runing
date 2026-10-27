import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../controller/providers.dart';
import '../../../repository/explore_repository.dart';
import '../../../utils/date_locale.dart';
import '../../../utils/l10n.dart';
import '../../../values/routes.dart';
import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';

/// Màn lỗi Explore theo nguyên nhân; hết phiên/khách → CTA đăng nhập.
class ExploreFailureView extends StatelessWidget {
  const ExploreFailureView({super.key, required this.failure, this.onRetry, this.signInLabel});
  final ExploreFailure failure;
  final VoidCallback? onRetry;
  final String? signInLabel;

  @override
  Widget build(BuildContext context) {
    if (failure.kind == ExploreErrorKind.signedOut) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: failure.title,
        message: failure.userMessage,
        actionLabel: signInLabel ?? 'explore_sign_in'.tr,
        onAction: () => context.push(Routes.login),
      );
    }
    final retry = failure.kind == ExploreErrorKind.notConfigured || failure.kind == ExploreErrorKind.notFound ? null : onRetry;
    return EmptyState(
      icon: failure.kind == ExploreErrorKind.offline ? Icons.cloud_off_outlined : Icons.error_outline,
      title: failure.title,
      message: failure.userMessage,
      actionLabel: retry == null ? null : 'explore_try_again'.tr,
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
    return EmptyState(icon: icon, title: title, message: message, actionLabel: 'explore_sign_in'.tr, onAction: () => context.push(Routes.login));
  }
}

void showExploreError(BuildContext context, Object e) {
  final f = mapExploreError(e);
  showStrideSnack(context, f.kind == ExploreErrorKind.offline ? 'explore_offline_snack'.tr : f.userMessage, isError: true);
}

bool _tzReady = false;

/// Định dạng thời điểm theo múi giờ của sự kiện/challenge (không theo máy), kèm tên tz.
String formatInZone(int utcMs, String tzId) {
  try {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final loc = tz.getLocation(tzId);
    final t = tz.TZDateTime.fromMillisecondsSinceEpoch(loc, utcMs);
    return '${AppDates.shortWeekdayDateTime(DateTime(t.year, t.month, t.day, t.hour, t.minute))} ${t.timeZoneName}';
  } catch (_) {
    final t = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true);
    return '${AppDates.shortWeekdayDateTime(t)} UTC';
  }
}

/// Ngày YYYY-MM-DD → "Oct 18, 2026".
String formatLocalDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : AppDates.monthDayYear(d);
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
      child: loading ? const CircularProgressIndicator() : TextButton(onPressed: onPressed, child: Text('explore_load_more'.tr)),
    ),
  );
}
