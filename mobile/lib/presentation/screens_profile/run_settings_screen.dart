import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/profile.dart';
import '../../controller/profile/profile_logic.dart';
import 'components/profile_widgets.dart';

/// Run settings / Audio updates (J01, mở từ Profile và Run → Audio updates).
/// Mỗi thay đổi lưu ngay vào settings; phiên đang mở giữ cấu hình lúc bắt đầu.
class RunSettingsScreen extends ConsumerStatefulWidget {
  const RunSettingsScreen({super.key});

  @override
  ConsumerState<RunSettingsScreen> createState() => _RunSettingsScreenState();
}

class _RunSettingsScreenState extends ConsumerState<RunSettingsScreen> {
  bool _testing = false;

  Future<void> _update(UserSettings s, UserSettings Function(UserSettings) change) async {
    try {
      final latest = await ref.read(settingsRepositoryProvider).load(s.ownerId);
      await ref.read(settingsRepositoryProvider).save(change(latest));
    } catch (_) {
      if (mounted) showStrideSnack(context, 'profile_save_setting_error'.tr, isError: true);
    }
  }

  Future<void> _testVoice(UserSettings s, StrideFormat fmt) async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final ok = await ref.read(profileVoiceProvider).speak(voiceTestPhrase(s.audioCues, fmt));
      if (!ok && mounted) showStrideSnack(context, 'profile_run_tts_unavailable'.tr, isError: true);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'profile_run_tts_unavailable'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final fmt = ref.watch(formatProvider);
    final openSession = ref.watch(profileOpenSessionProvider).value ?? false;
    return StrideScreen(
      title: 'profile_run_settings_title'.tr,
      body: settings.when(
        loading: () => const Column(children: [Gap(16), LoadingCard(), Gap(12), LoadingCard()]),
        error: (e, _) =>
            ErrorState(title: 'profile_settings_load_error_title'.tr, message: 'profile_try_again'.tr, onRetry: () => ref.invalidate(settingsProvider)),
        data: (s) {
          final cues = s.audioCues;
          final unit = fmt.distanceUnitLabel;
          final currentInterval = cueIntervalInUnit(cues.everyKm, s.distanceUnit);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Gap(8),
              if (openSession) ...[StatusBanner(tone: BannerTone.info, message: 'profile_run_in_progress'.tr), const Gap(12)],
              SectionHeader(title: 'profile_run_audio_updates'.tr),
              SettingsGroup(
                children: [
                  ProfileSwitchRow(
                    icon: Icons.volume_up_outlined,
                    title: 'profile_run_audio_cues'.tr,
                    subtitle: 'profile_run_audio_cues_subtitle'.tr,
                    value: cues.enabled,
                    onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(enabled: v))),
                  ),
                  if (cues.enabled) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('profile_run_announce_every'.tr, style: StrideText.label),
                          const Gap(4),
                          PresetChips<double>(
                            values: cueIntervalChoices,
                            selected: cueIntervalChoices.contains(currentInterval) ? currentInterval : null,
                            labelOf: (v) => '${v == v.roundToDouble() ? v.toInt() : v} $unit',
                            onSelected: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(everyKm: cueIntervalToKm(v, l.distanceUnit)))),
                          ),
                        ],
                      ),
                    ),
                    ProfileSwitchRow(
                      title: 'profile_run_announce_time'.tr,
                      value: cues.announceTime,
                      onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(announceTime: v))),
                    ),
                    ProfileSwitchRow(
                      title: 'profile_run_announce_pace'.tr,
                      value: cues.announcePace,
                      onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(announcePace: v))),
                    ),
                  ],
                ],
              ),
              if (cues.enabled) ...[
                const Gap(12),
                OutlineButton(
                  label: _testing ? 'profile_run_playing'.tr : 'profile_run_test_voice'.tr,
                  icon: Icons.record_voice_over_outlined,
                  onPressed: _testing ? null : () => _testVoice(s, fmt),
                ),
              ],
              const Gap(16),
              SectionHeader(title: 'profile_run_recording'.tr),
              SettingsGroup(
                children: [
                  ProfileSwitchRow(
                    icon: Icons.pause_circle_outline,
                    title: 'profile_run_auto_pause'.tr,
                    subtitle: 'profile_run_auto_pause_subtitle'.tr,
                    value: s.autoPause,
                    onChanged: (v) => _update(s, (l) => l.copyWith(autoPause: v)),
                  ),
                ],
              ),
              const Gap(12),
              ProfileNote('profile_run_note'.tr),
            ],
          );
        },
      ),
    );
  }
}
