import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/profile.dart';
import 'profile_logic.dart';
import 'profile_widgets.dart';

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
      if (mounted) showStrideSnack(context, 'Couldn’t save this setting. Try again.', isError: true);
    }
  }

  Future<void> _testVoice(UserSettings s, StrideFormat fmt) async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final ok = await ref.read(profileVoiceProvider).speak(voiceTestPhrase(s.audioCues, fmt));
      if (!ok && mounted) showStrideSnack(context, 'Text-to-speech isn’t available. Check your phone’s voice settings.', isError: true);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'Text-to-speech isn’t available. Check your phone’s voice settings.', isError: true);
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
      title: 'Run settings',
      body: settings.when(
        loading: () => const Column(children: [Gap(16), LoadingCard(), Gap(12), LoadingCard()]),
        error: (e, _) => ErrorState(title: 'Couldn’t load settings', message: 'Try again.', onRetry: () => ref.invalidate(settingsProvider)),
        data: (s) {
          final cues = s.audioCues;
          final unit = fmt.distanceUnitLabel;
          final currentInterval = cueIntervalInUnit(cues.everyKm, s.distanceUnit);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Gap(8),
              if (openSession) ...[
                const StatusBanner(tone: BannerTone.info, message: 'An activity is in progress. Changes apply from your next activity.'),
                const Gap(12),
              ],
              const SectionHeader(title: 'Audio updates'),
              SettingsGroup(
                children: [
                  ProfileSwitchRow(
                    icon: Icons.volume_up_outlined,
                    title: 'Audio cues',
                    subtitle: 'Hear progress updates while you run.',
                    value: cues.enabled,
                    onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(enabled: v))),
                  ),
                  if (cues.enabled) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Announce every', style: StrideText.label),
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
                      title: 'Announce time',
                      value: cues.announceTime,
                      onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(announceTime: v))),
                    ),
                    ProfileSwitchRow(
                      title: 'Announce pace',
                      value: cues.announcePace,
                      onChanged: (v) => _update(s, (l) => l.copyWith(audioCues: l.audioCues.copyWith(announcePace: v))),
                    ),
                  ],
                ],
              ),
              if (cues.enabled) ...[
                const Gap(12),
                OutlineButton(
                  label: _testing ? 'Playing…' : 'Test voice',
                  icon: Icons.record_voice_over_outlined,
                  onPressed: _testing ? null : () => _testVoice(s, fmt),
                ),
              ],
              const Gap(16),
              const SectionHeader(title: 'Recording'),
              SettingsGroup(
                children: [
                  ProfileSwitchRow(
                    icon: Icons.pause_circle_outline,
                    title: 'Auto pause',
                    subtitle: 'Pauses the timer when you stop moving and resumes when you move again. Moving time excludes paused time.',
                    value: s.autoPause,
                    onChanged: (v) => _update(s, (l) => l.copyWith(autoPause: v)),
                  ),
                ],
              ),
              const Gap(12),
              const ProfileNote('Settings are saved on this device and apply when you start an activity.'),
            ],
          );
        },
      ),
    );
  }
}
