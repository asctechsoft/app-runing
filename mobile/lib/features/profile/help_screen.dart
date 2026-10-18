import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'profile_logic.dart';
import 'profile_widgets.dart';

/// Chia sẻ văn bản qua share sheet hệ thống; override trong test. Trả true khi người dùng chọn app.
abstract class ProfileShareService {
  Future<bool> shareText(String text, {String? subject});
}

class SystemShareService implements ProfileShareService {
  @override
  Future<bool> shareText(String text, {String? subject}) async {
    final r = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return r.status == ShareResultStatus.success;
  }
}

final profileShareProvider = Provider<ProfileShareService>((ref) => SystemShareService());

enum FeedbackResult { sent, unavailable }

/// Gửi feedback lên `POST /feedback` (J06). [FeedbackResult.unavailable] khi build không có server,
/// mất mạng hoặc server cũ chưa có endpoint → UI chuyển sang share sheet. Lỗi khác (422/429...) ném ApiException.
class FeedbackSender {
  FeedbackSender(this._api);
  final ApiClient _api;

  Future<FeedbackResult> send({required String message, String? diagnostics, required String appVersion}) async {
    if (!_api.configured) return FeedbackResult.unavailable;
    try {
      await _api.post('/feedback', body: {'message': message, 'diagnostics': ?diagnostics, 'appVersion': appVersion});
      return FeedbackResult.sent;
    } on ApiException catch (e) {
      if (e.isNetwork || e.isNotFound) return FeedbackResult.unavailable;
      rethrow;
    }
  }
}

final feedbackSenderProvider = Provider<FeedbackSender>((ref) => FeedbackSender(ref.watch(apiClientProvider)));

String _platformName() {
  if (kIsWeb) return 'web';
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'unknown';
  }
}

/// Thu thập chẩn đoán: version, env, flags, quyền, số đếm — không token/tọa độ/email.
Future<String> collectDiagnostics(WidgetRef ref) async {
  final perms = ref.read(permissionsProvider);
  final statuses = <PermKind, PermStatus>{};
  for (final k in [PermKind.motion, PermKind.location, PermKind.notification, PermKind.bluetooth]) {
    try {
      statuses[k] = await perms.status(k);
    } catch (_) {
      statuses[k] = PermStatus.unknown;
    }
  }
  final owner = ref.read(ownerProvider);
  final db = ref.read(databaseProvider).db;
  Future<int> count(String sql) async => ((await db.rawQuery(sql, [owner.ownerId])).first['c'] as num?)?.toInt() ?? 0;
  final saved = await count("SELECT COUNT(*) AS c FROM activities WHERE owner_id = ? AND status = 'saved' AND deleted_at IS NULL");
  final samples = await count('SELECT COUNT(*) AS c FROM step_samples WHERE owner_id = ?');
  final pending = await count("SELECT COUNT(*) AS c FROM sync_outbox WHERE owner_id = ? AND state != 'acked'");
  final settings = ref.read(settingsProvider).value;
  return buildDiagnostics(
    env: ref.read(envProvider).env.name,
    platform: _platformName(),
    flags: ref.read(flagsProvider),
    permissions: statuses,
    isGuest: owner.isGuest,
    savedActivities: saved,
    stepSamples: samples,
    pendingSync: pending,
    distanceUnit: settings?.distanceUnit.name ?? 'km',
  );
}

/// Help (J06): hướng dẫn GPS/bước/pin, phản hồi (POST /feedback, share sheet khi không có server), chẩn đoán.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _feedback = TextEditingController();
  bool _includeDiagnostics = true;
  String? _feedbackError;
  final _guard = OnceGuard();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _copyDiagnostics() => _guard.run(() async {
    try {
      final text = await collectDiagnostics(ref);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showStrideSnack(context, 'Diagnostics copied');
    } catch (_) {
      if (mounted) showStrideSnack(context, 'Couldn’t collect diagnostics. Try again.', isError: true);
    }
  });

  Future<void> _shareFeedback() => _guard.run(() async {
    final text = _feedback.text.trim();
    if (text.isEmpty) {
      setState(() => _feedbackError = 'Tell us what happened');
      return;
    }
    try {
      final diagnostics = _includeDiagnostics ? await collectDiagnostics(ref) : null;
      final result = await ref.read(feedbackSenderProvider).send(message: text, diagnostics: diagnostics, appVersion: profileAppVersion);
      if (!mounted) return;
      if (result == FeedbackResult.sent) {
        _feedback.clear();
        showStrideSnack(context, 'Feedback sent. Thank you!');
        return;
      }
      // Không gửi được lên server: để người dùng tự chọn app gửi (không báo "đã gửi" khi chưa chắc).
      final body = diagnostics == null ? text : '$text\n\n---\n$diagnostics';
      final shared = await ref.read(profileShareProvider).shareText(body, subject: 'STRIDE feedback');
      if (!mounted) return;
      if (shared) {
        _feedback.clear();
        showStrideSnack(context, 'Feedback handed to the app you chose');
      }
    } on ApiException catch (e) {
      if (mounted) showStrideSnack(context, e.status == 429 ? 'Too many messages. Try again later.' : 'Couldn’t send feedback. Try again.', isError: true);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'Couldn’t send feedback. Copy diagnostics instead.', isError: true);
    }
  });

  void _guide(String title, List<String> paragraphs, {Widget? action}) {
    showStrideSheet<void>(
      context,
      title: title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(p, style: StrideText.body),
            ),
          ?action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final openSettings = OutlineButton(
      label: 'Open app settings',
      icon: Icons.settings_outlined,
      onPressed: () => ref.read(permissionsProvider).openSettings(),
    );
    return StrideScreen(
      title: 'Help',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          const SectionHeader(title: 'Guides'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.gps_fixed,
                title: 'GPS accuracy',
                subtitle: 'Get a better signal before you start',
                onTap: () => _guide('GPS accuracy', const [
                  'Wait for the GPS indicator to show a good signal before you start. Open sky gives the best results.',
                  'Tall buildings, tunnels and dense trees can make distance jump or drop. STRIDE filters inaccurate points and leaves gaps instead of guessing.',
                  'Allow precise location while using the app. Approximate location can’t record a route.',
                ], action: openSettings),
              ),
              SettingsRow(
                icon: Icons.directions_walk,
                title: 'Step counting',
                subtitle: 'How daily steps are counted',
                onTap: () => _guide('Step counting', const [
                  'Daily steps come from your phone’s motion sensor and are separate from recorded runs.',
                  'Carry your phone for steps to count. If motion access is off, STRIDE shows no data instead of zero.',
                  'Distance and calories from steps are estimated.',
                ], action: openSettings),
              ),
              SettingsRow(
                icon: Icons.battery_alert_outlined,
                title: 'Battery optimization',
                subtitle: 'Keep recording when the screen is off',
                onTap: () => _guide('Battery optimization', [
                  if (isAndroid) ...[
                    'Some Android phones stop apps in the background to save battery. This can pause GPS recording or step updates when the screen is off.',
                    'In app settings, open Battery and choose Unrestricted (or turn off battery optimization) for STRIDE. The name varies by phone maker.',
                  ] else
                    'Keep Background App Refresh on for STRIDE and allow location while using the app so recording continues when the screen is locked.',
                  'STRIDE only uses GPS while you’re recording an activity.',
                ], action: openSettings),
              ),
            ],
          ),
          const Gap(16),
          ProfileSection(
            title: 'Send feedback',
            subtitle: 'Opens your share sheet so you can send it by email or another app. Nothing is sent until you choose.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('help-feedback'),
                  controller: _feedback,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: 'What happened?', errorText: _feedbackError),
                  onChanged: (_) {
                    if (_feedbackError != null) setState(() => _feedbackError = null);
                  },
                ),
                ProfileSwitchRow(
                  title: 'Include diagnostics',
                  subtitle: 'App version, settings and permission status. No location or account tokens.',
                  value: _includeDiagnostics,
                  onChanged: (v) => setState(() => _includeDiagnostics = v),
                ),
                const Gap(8),
                PrimaryButton(label: 'Send feedback', icon: Icons.send_outlined, onPressed: _shareFeedback),
              ],
            ),
          ),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.content_copy,
                title: 'Copy diagnostics',
                subtitle: 'No location, email or account tokens',
                showChevron: false,
                onTap: _copyDiagnostics,
              ),
              SettingsRow(icon: Icons.info_outline, title: 'App version', subtitle: profileVersionLabel, showChevron: false),
            ],
          ),
        ],
      ),
    );
  }
}
