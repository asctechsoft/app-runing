import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/badges/badges_providers.dart';
import '../../utils/calc/badges.dart';
import '../../utils/date_locale.dart';
import '../../utils/haptics.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Biểu tượng tạm theo loại (Material Icons) cho tới khi có bộ icon từ Design (TM40).
IconData badgeIcon(BadgeKind k) => switch (k) {
  BadgeKind.first5k || BadgeKind.first10k || BadgeKind.firstHalf => Icons.directions_run,
  BadgeKind.total100km || BadgeKind.total500km => Icons.route,
  BadgeKind.streak7 || BadgeKind.streak30 || BadgeKind.streak100 => Icons.local_fire_department,
  BadgeKind.challenge => Icons.military_tech,
};

String badgeTitle(EarnedBadge? b, BadgeKind k) => k == BadgeKind.challenge ? (b?.title ?? '') : 'badge_${k.name}_title'.tr;
String badgeCondition(BadgeKind k) => 'badge_${k.name}_desc'.tr;
String badgeRarityLabel(BadgeRarity r) => 'badge_rarity_${r.name}'.tr;

/// Tủ huy hiệu (TM40): mốc cá nhân (đã nhận / chưa nhận kèm điều kiện) + huy hiệu thử thách đã hoàn thành.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(badgesProvider);
    return StrideScreen(
      title: 'badges_title'.tr,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Column(children: [LoadingCard(height: 120), SizedBox(height: 12), LoadingCard(height: 240)]),
        error: (_, _) => ErrorState(title: 'badges_error_title'.tr, message: 'badges_error_message'.tr, onRetry: () => ref.invalidate(badgesProvider)),
        data: (cab) {
          final byId = {for (final b in cab.earned) b.id: b};
          final challenges = cab.earned.where((b) => b.kind == BadgeKind.challenge).toList();
          final count = cab.earned.where((b) => b.kind != BadgeKind.challenge).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Gap(8),
              Text('badges_count'.trArgs([count, personalBadges.length]), style: StrideText.bodySecondary),
              const Gap(12),
              for (final k in personalBadges) ...[
                BadgeTile(kind: k, badge: byId[k.name], earnedAt: byId[k.name] == null ? null : cab.earnedAtOf(byId[k.name]!)),
                const Gap(8),
              ],
              const Gap(8),
              Text('badges_challenges'.tr, style: StrideText.subheading),
              const Gap(8),
              if (challenges.isEmpty)
                Text('badges_challenges_empty'.tr, style: StrideText.bodySecondary)
              else
                for (final b in challenges) ...[BadgeTile(kind: b.kind, badge: b, earnedAt: cab.earnedAtOf(b)), const Gap(8)],
              const Gap(8),
              Text('badges_note'.tr, style: StrideText.caption),
            ],
          );
        },
      ),
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.kind, this.badge, this.earnedAt});
  final BadgeKind kind;
  final EarnedBadge? badge;
  final int? earnedAt;

  @override
  Widget build(BuildContext context) {
    final earned = badge != null;
    final title = badgeTitle(badge, kind);
    final status = earned
        ? (earnedAt == null ? 'badges_earned'.tr : 'badges_earned_on'.trArgs([AppDates.monthDayYear(DateTime.fromMillisecondsSinceEpoch(earnedAt!))]))
        : 'badges_locked'.tr;
    return Semantics(
      label: '$title. $status',
      container: true,
      child: StrideCard(
        key: Key('badge-${badge?.id ?? kind.name}'),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: earned ? StrideColors.lime : StrideColors.subtle, shape: BoxShape.circle),
              child: Icon(badgeIcon(kind), color: earned ? StrideColors.primary : StrideColors.textMuted, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: StrideText.subheading.copyWith(color: earned ? StrideColors.textPrimary : StrideColors.textSecondary)),
                  Text(badgeCondition(kind), style: StrideText.bodySecondary.copyWith(fontSize: 14)),
                  const Gap(2),
                  Text('$status · ${badgeRarityLabel(kind.rarity)}', style: StrideText.caption),
                ],
              ),
            ),
            if (!earned) const Icon(Icons.lock_outline, color: StrideColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Báo nhận huy hiệu mới (một lần): huy hiệu phóng nhẹ vào + haptic; giảm chuyển động → hiện ngay.
Future<void> showBadgeEarnedDialog(BuildContext context, List<EarnedBadge> fresh) {
  StrideHaptics.medium();
  final first = fresh.first;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('badge-earned-dialog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: StrideMotion.of(ctx, StrideMotion.screen),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: StrideColors.lime, shape: BoxShape.circle),
              child: Icon(badgeIcon(first.kind), color: StrideColors.primary, size: 44),
            ),
          ),
          const Gap(16),
          Text('badges_new_title'.tr, style: StrideText.label, textAlign: TextAlign.center),
          const Gap(4),
          Text(badgeTitle(first, first.kind), style: StrideText.heading, textAlign: TextAlign.center),
          if (fresh.length > 1) ...[
            const Gap(4),
            Text('badges_new_more'.trPlural(fresh.length - 1, [fresh.length - 1]), style: StrideText.bodySecondary, textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('badges_new_ok'.tr))],
    ),
  );
}
