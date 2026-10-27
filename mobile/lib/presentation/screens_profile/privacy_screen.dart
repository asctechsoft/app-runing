import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/profile/diagnostics_consent.dart';
import '../../controller/profile/profile_logic.dart';
import '../../controller/providers.dart';
import '../../models/data_models/activity.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/profile_widgets.dart';

final profileDefaultPrivacyProvider = FutureProvider.autoDispose<Privacy>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  return loadDefaultPrivacy(ref.watch(settingsRepositoryProvider), owner);
});

/// Các mức hiển thị có tác dụng thật. Firestore rules chỉ cho người cùng club đã duyệt xem cả "followers" lẫn "public"
/// nên không hiện "Public" riêng để tránh hứa phạm vi rộng hơn thực tế.
List<Privacy> privacyChoices({required bool clubsEnabled}) => [Privacy.onlyMe, if (clubsEnabled) Privacy.followers];

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'profile_privacy_only_me'.tr,
  Privacy.followers => 'profile_privacy_club_members'.tr,
  Privacy.public => 'profile_privacy_public'.tr,
};

String privacyHelp(Privacy p) => switch (p) {
  Privacy.onlyMe => 'profile_privacy_only_me_help'.tr,
  Privacy.followers => 'profile_privacy_club_members_help'.tr,
  Privacy.public => 'profile_privacy_public_help'.tr,
};

/// Privacy (J04): mặc định Only me; giải thích chia sẻ ảnh tách khỏi quyền xem; vị trí chỉ khi ghi hoạt động.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, Privacy p) async {
    try {
      await saveDefaultPrivacy(ref.read(settingsRepositoryProvider), ref.read(ownerProvider).ownerId, p);
      ref.invalidate(profileDefaultPrivacyProvider);
    } catch (_) {
      if (context.mounted) showStrideSnack(context, 'profile_save_setting_error'.tr, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final current = ref.watch(profileDefaultPrivacyProvider);
    final choices = privacyChoices(clubsEnabled: flags.exploreClubs);
    return StrideScreen(
      title: 'profile_privacy_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          ProfileSection(
            title: 'profile_privacy_default_title'.tr,
            subtitle: 'profile_privacy_default_subtitle'.tr,
            child: current.when(
              loading: () => const Skeleton(height: 56),
              error: (e, _) => TextButton(onPressed: () => ref.invalidate(profileDefaultPrivacyProvider), child: Text('profile_load_retry'.tr)),
              data: (value) {
                final selected = choices.contains(value) ? value : Privacy.onlyMe;
                return RadioGroup<Privacy>(
                  groupValue: selected,
                  onChanged: (p) {
                    if (p != null) _set(context, ref, p);
                  },
                  child: Column(
                    children: [
                      for (final p in choices)
                        RadioListTile<Privacy>(
                          value: p,
                          contentPadding: EdgeInsets.zero,
                          activeColor: StrideColors.primary,
                          title: Text(privacyLabel(p), style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text(privacyHelp(p), style: StrideText.caption.copyWith(fontSize: 13)),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          ProfileSection(
            title: 'profile_privacy_share_title'.tr,
            child: Text('profile_privacy_share_text'.tr, style: StrideText.bodySecondary),
          ),
          ProfileSection(
            title: 'profile_privacy_location_title'.tr,
            child: Text('profile_privacy_location_text'.tr, style: StrideText.bodySecondary),
          ),
          SettingsGroup(
            children: [
              ProfileSwitchRow(
                icon: Icons.insights_outlined,
                title: 'profile_privacy_diagnostics_title'.tr,
                subtitle: 'profile_privacy_diagnostics_subtitle'.tr,
                value: ref.watch(diagnosticsConsentProvider),
                onChanged: (v) => ref.read(diagnosticsConsentProvider.notifier).set(v),
              ),
            ],
          ),
          const Gap(12),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.storage_outlined,
                title: 'profile_privacy_export_title'.tr,
                subtitle: 'profile_account_title'.tr,
                onTap: () => context.push(Routes.account),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
