import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/profile/profile_logic.dart';
import 'components/profile_widgets.dart';

/// Tab Profile (J01): header, thống kê trọn đời và lối vào mọi màn cài đặt.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final settings = ref.watch(settingsProvider);
    final owner = ref.watch(ownerProvider);
    final gutter = StrideScreen.gutterOf(context);

    final rows = <(IconData, String, String, String)>[
      (Icons.person_outline, 'Edit profile', 'Update your photo, name and more', Routes.editProfile),
      (Icons.track_changes, 'Goals', 'Set your running and step goals', Routes.profileGoals),
      (Icons.settings_outlined, 'Run settings', 'Audio cues and auto pause', Routes.runSettings),
      (Icons.notifications_none, 'Reminders', 'Stay on track with helpful notifications', Routes.reminders),
      (Icons.language, 'Units & language', 'Distance, pace and app language', Routes.units),
      (Icons.link, 'Data sources', 'Phone sensor, devices and source priority', Routes.dataSources),
      if (flags.exploreAny) (Icons.map_outlined, 'Explore', _exploreSubtitle(flags.exploreClubs, flags.exploreChallenges, flags.exploreRoutes), Routes.explore),
      (Icons.shield_outlined, 'Privacy', 'Control who can see your activities', Routes.privacy),
      (Icons.storage_outlined, 'Account & data', 'Manage your account and export data', Routes.account),
      (Icons.help_outline, 'Help', 'Guides, feedback and diagnostics', Routes.help),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
              children: [
                settings.when(
                  data: (s) => _Header(name: s.displayName, avatarPath: s.avatarPath, isGuest: owner.isGuest),
                  loading: () => const Skeleton(height: 72),
                  error: (e, _) => _Header(name: '', avatarPath: null, isGuest: owner.isGuest),
                ),
                const SizedBox(height: 16),
                const _StatsCard(),
                const SizedBox(height: 16),
                SettingsGroup(
                  children: [for (final r in rows) SettingsRow(icon: r.$1, title: r.$2, subtitle: r.$3, onTap: () => context.push(r.$4))],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text('STRIDE', style: StrideText.label.copyWith(color: StrideColors.iconNavy)),
                ),
                Center(child: Text(profileVersionLabel, style: StrideText.caption)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _exploreSubtitle(bool clubs, bool challenges, bool routes) {
    final parts = [if (clubs) 'clubs', if (challenges) 'challenges', if (routes) 'routes'];
    final s = parts.join(', ');
    return s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.name, required this.avatarPath, required this.isGuest});
  final String name;
  final String? avatarPath;
  final bool isGuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = isGuest ? null : ref.watch(profileJoinedProvider).value;
    final subtitle = isGuest ? 'Guest' : (joined == null ? null : 'Joined ${DateFormat('MMMM y').format(joined)}');
    return Row(
      children: [
        ProfileAvatar(name: name, path: avatarPath),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.trim().isEmpty ? 'Add your name' : name, style: StrideText.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (subtitle != null) Text(subtitle, style: StrideText.bodySecondary),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(profileStatsProvider);
    final fmt = ref.watch(formatProvider);
    return StrideCard(
      child: stats.when(
        loading: () => const Skeleton(height: 96),
        error: (e, _) => Text('Couldn’t load your stats.', style: StrideText.bodySecondary),
        data: (s) => Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.route_outlined,
                label: 'Lifetime distance',
                value: s.activityCount == 0 ? '0' : NumberFormat('#,##0.#').format(fmt.metersToUnit(s.distanceM)),
                unit: fmt.distanceUnitLabel,
                center: true,
              ),
            ),
            Expanded(
              child: MetricTile(icon: Icons.directions_run, label: 'Total runs', value: '${s.runCount}', unit: s.runCount == 1 ? 'run' : 'runs', center: true),
            ),
            Expanded(
              child: MetricTile(
                icon: Icons.calendar_today_outlined,
                label: 'Active days',
                value: '${s.activeDays}',
                unit: s.activeDays == 1 ? 'day' : 'days',
                center: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
