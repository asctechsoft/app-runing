import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../controller/profile/profile_logic.dart';
import 'components/profile_widgets.dart';

final profileDefaultPrivacyProvider = FutureProvider.autoDispose<Privacy>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  return loadDefaultPrivacy(ref.watch(settingsRepositoryProvider), owner);
});

/// Các mức hiển thị có tác dụng thật. Backend chỉ cho người cùng club đã duyệt xem cả "followers" lẫn "public"
/// nên không hiện "Public" riêng để tránh hứa phạm vi rộng hơn thực tế.
List<Privacy> privacyChoices({required bool clubsEnabled}) => [Privacy.onlyMe, if (clubsEnabled) Privacy.followers];

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only me',
  Privacy.followers => 'Club members',
  Privacy.public => 'Public',
};

String privacyHelp(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only you can see new activities.',
  Privacy.followers => 'Members of clubs you’ve joined can see new activities. Start and finish locations stay hidden.',
  Privacy.public => 'Anyone with access can see new activities.',
};

/// Privacy (J04): mặc định Only me; giải thích chia sẻ ảnh tách khỏi quyền xem; vị trí chỉ khi ghi hoạt động.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, Privacy p) async {
    try {
      await saveDefaultPrivacy(ref.read(settingsRepositoryProvider), ref.read(ownerProvider).ownerId, p);
      ref.invalidate(profileDefaultPrivacyProvider);
    } catch (_) {
      if (context.mounted) showStrideSnack(context, 'Couldn’t save this setting. Try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final current = ref.watch(profileDefaultPrivacyProvider);
    final choices = privacyChoices(clubsEnabled: flags.exploreClubs);
    return StrideScreen(
      title: 'Privacy',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          ProfileSection(
            title: 'Default activity visibility',
            subtitle: 'Applies to activities you save from now on. You can change it for each activity.',
            child: current.when(
              loading: () => const Skeleton(height: 56),
              error: (e, _) => TextButton(onPressed: () => ref.invalidate(profileDefaultPrivacyProvider), child: const Text('Couldn’t load. Try again')),
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
          const ProfileSection(
            title: 'Share images',
            child: Text(
              'Sharing an activity image is separate from who can see the activity in STRIDE. Images hide your start and finish by default, and nothing is shared until you choose an app.',
              style: StrideText.bodySecondary,
            ),
          ),
          const ProfileSection(
            title: 'Location data',
            child: Text(
              'STRIDE only records GPS while you’re recording an activity you started. Daily steps use the motion sensor, not your location. Location isn’t sent to analytics.',
              style: StrideText.bodySecondary,
            ),
          ),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.storage_outlined,
                title: 'Export or delete your data',
                subtitle: 'Account & data',
                onTap: () => context.push(Routes.account),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
