import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Explore hub (M01): mỗi thẻ mở module thật; module có flag tắt bị ẩn hẳn.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final cards = [
      if (flags.exploreClubs) (Icons.groups_outlined, 'Running clubs', 'Find a group and run together.', Routes.clubs),
      if (flags.exploreChallenges) (Icons.emoji_events_outlined, 'Challenges', 'Set yourself a new challenge.', Routes.challenges),
      if (flags.exploreRoutes) (Icons.place_outlined, 'Discover routes', 'Find your next running route.', Routes.routesDiscover),
    ];
    return StrideScreen(
      title: 'Explore',
      largeTitle: true,
      body: cards.isEmpty
          ? const EmptyState(
              icon: Icons.explore_off_outlined,
              title: 'Explore isn’t available',
              message: 'Clubs, challenges and routes aren’t turned on in this version.',
            )
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
