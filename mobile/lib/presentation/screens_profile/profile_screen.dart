import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../utils/l10n.dart';
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
      (Icons.person_outline, 'profile_edit_title'.tr, 'profile_row_edit_subtitle'.tr, Routes.editProfile),
      (Icons.track_changes, 'profile_goals_title'.tr, 'profile_row_goals_subtitle'.tr, Routes.profileGoals),
      (Icons.settings_outlined, 'profile_run_settings_title'.tr, 'profile_row_run_subtitle'.tr, Routes.runSettings),
      (Icons.notifications_none, 'profile_reminders_title'.tr, 'profile_row_reminders_subtitle'.tr, Routes.reminders),
      (Icons.language, 'profile_units_title'.tr, 'profile_row_units_subtitle'.tr, Routes.units),
      (Icons.link, 'profile_data_sources_title'.tr, 'profile_row_ds_subtitle'.tr, Routes.dataSources),
      if (flags.exploreAny)
        (Icons.map_outlined, 'profile_explore_title'.tr, _exploreSubtitle(flags.exploreClubs, flags.exploreChallenges, flags.exploreRoutes), Routes.explore),
      (Icons.shield_outlined, 'profile_privacy_title'.tr, 'profile_row_privacy_subtitle'.tr, Routes.privacy),
      (Icons.storage_outlined, 'profile_account_title'.tr, 'profile_row_account_subtitle'.tr, Routes.account),
      (Icons.help_outline, 'profile_help_title'.tr, 'profile_row_help_subtitle'.tr, Routes.help),
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
    final parts = [if (clubs) 'profile_explore_clubs'.tr, if (challenges) 'profile_explore_challenges'.tr, if (routes) 'profile_explore_routes'.tr];
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
    final subtitle = isGuest ? 'profile_guest'.tr : (joined == null ? null : 'profile_joined'.trArgs([DateFormat('MMMM y').format(joined)]));
    return Row(
      children: [
        ProfileAvatar(name: name, path: avatarPath),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.trim().isEmpty ? 'profile_add_name'.tr : name, style: StrideText.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
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
        error: (e, _) => Text('profile_stats_error'.tr, style: StrideText.bodySecondary),
        data: (s) => Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.route_outlined,
                label: 'profile_stats_distance'.tr,
                value: s.activityCount == 0 ? '0' : NumberFormat('#,##0.#').format(fmt.metersToUnit(s.distanceM)),
                unit: fmt.distanceUnitLabel,
                center: true,
              ),
            ),
            Expanded(
              child: MetricTile(
                icon: Icons.directions_run,
                label: 'profile_stats_runs'.tr,
                value: '${s.runCount}',
                unit: s.runCount == 1 ? 'profile_unit_run'.tr : 'profile_unit_runs'.tr,
                center: true,
              ),
            ),
            Expanded(
              child: MetricTile(
                icon: Icons.calendar_today_outlined,
                label: 'profile_stats_active_days'.tr,
                value: '${s.activeDays}',
                unit: s.activeDays == 1 ? 'profile_unit_day'.tr : 'profile_unit_days'.tr,
                center: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
