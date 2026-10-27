import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Explore hub (M01): mỗi thẻ mở module thật; module có flag tắt bị ẩn hẳn.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final cards = [
      if (flags.exploreClubs) (Icons.groups_outlined, 'explore_clubs_title'.tr, 'explore_clubs_hub_subtitle'.tr, Routes.clubs),
      if (flags.exploreChallenges) (Icons.emoji_events_outlined, 'explore_challenges_title'.tr, 'explore_challenges_subtitle'.tr, Routes.challenges),
      if (flags.exploreRoutes) (Icons.place_outlined, 'explore_routes_title'.tr, 'explore_routes_subtitle'.tr, Routes.routesDiscover),
    ];
    return StrideScreen(
      title: 'explore_title'.tr,
      largeTitle: true,
      body: cards.isEmpty
          ? EmptyState(icon: Icons.explore_off_outlined, title: 'explore_unavailable_title'.tr, message: 'explore_unavailable_message'.tr)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Gap(8),
                for (final c in cards) ...[_HubCard(icon: c.$1, title: c.$2, subtitle: c.$3, onTap: () => context.push(c.$4)), const Gap(12)],
              ],
            ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => StrideCard(
    onTap: onTap,
    semanticLabel: '$title. $subtitle',
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: StrideText.title.copyWith(fontSize: 24)),
              const Gap(4),
              Text(subtitle, style: StrideText.bodySecondary),
              const Gap(16),
              Row(
                children: [
                  IconBadge(icon: icon, size: 48),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: StrideColors.primary),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(color: StrideColors.subtle, shape: BoxShape.circle),
          child: Icon(icon, size: 48, color: StrideColors.primary),
        ),
      ],
    ),
  );
}
