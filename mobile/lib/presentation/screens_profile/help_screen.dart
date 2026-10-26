import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../services/application/firebase_providers.dart';
import '../../utils/l10n.dart';
import '../../services/application/api_client.dart';
import '../../services/native/permission_coordinator.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/profile/profile_logic.dart';
import 'components/profile_widgets.dart';

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

/// Ghi một document `feedback/{id}` (test thay bằng bản in-memory).
typedef FeedbackWriter = Future<void> Function(String id, Map<String, Object?> data);

/// Gửi feedback vào Firestore `feedback/{id}` (J06). [FeedbackResult.unavailable] khi Firebase chưa sẵn sàng, chưa đăng nhập
/// hoặc mất mạng (quá [timeout]) → UI chuyển sang share sheet. Lỗi khác (quyền, quá tải...) ném ApiException.
class FeedbackSender {
  FeedbackSender({
    required FeedbackWriter write,
    required bool Function() ready,
    required String? Function() uid,
    int Function()? nowMs,
    String Function()? newId,
    this.timeout = const Duration(seconds: 10),
  }) : _write = write,
       _ready = ready,
       _uid = uid,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _newId = newId ?? (() => const Uuid().v4());

  final FeedbackWriter _write;
  final bool Function() _ready;
  final String? Function() _uid;
  final int Function() _nowMs;
  final String Function() _newId;
  final Duration timeout;

  Future<FeedbackResult> send({required String message, String? diagnostics, required String appVersion}) async {
    final uid = _uid();
    if (!_ready() || uid == null) return FeedbackResult.unavailable;
    try {
      await _write(_newId(), {'uid': uid, 'message': message, 'diagnostics': diagnostics, 'appVersion': appVersion, 'createdAt': _nowMs()}).timeout(timeout);
      return FeedbackResult.sent;
    } on TimeoutException {
      return FeedbackResult.unavailable;
    } on FirebaseException catch (e) {
      final mapped = mapFirebaseError(e);
      if (mapped.isNetwork || mapped.isNotFound || mapped.isUnauthorized) return FeedbackResult.unavailable;
      throw mapped;
    } on ApiException catch (e) {
      if (e.isNetwork || e.isNotFound || e.isUnauthorized) return FeedbackResult.unavailable;
      rethrow;
    }
  }
}

final feedbackSenderProvider = Provider<FeedbackSender>((ref) {
  bool ready() => ref.read(firebaseReadyProvider);
  return FeedbackSender(
    write: (id, data) => ref.read(firestoreProvider).collection('feedback').doc(id).set(data),
    ready: ready,
    uid: () => ready() ? ref.read(firebaseAuthProvider).currentUser?.uid : null,
  );
});

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
      if (mounted) showStrideSnack(context, 'profile_help_diag_copied'.tr);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'profile_help_diag_error'.tr, isError: true);
    }
  });

  Future<void> _shareFeedback() => _guard.run(() async {
    final text = _feedback.text.trim();
    if (text.isEmpty) {
      setState(() => _feedbackError = 'profile_help_feedback_empty'.tr);
      return;
    }
    try {
      final diagnostics = _includeDiagnostics ? await collectDiagnostics(ref) : null;
      final result = await ref.read(feedbackSenderProvider).send(message: text, diagnostics: diagnostics, appVersion: profileAppVersion);
      if (!mounted) return;
      if (result == FeedbackResult.sent) {
        _feedback.clear();
        showStrideSnack(context, 'profile_help_feedback_sent'.tr);
        return;
      }
      // Không gửi được lên server: để người dùng tự chọn app gửi (không báo "đã gửi" khi chưa chắc).
      final body = diagnostics == null ? text : '$text\n\n---\n$diagnostics';
      final shared = await ref.read(profileShareProvider).shareText(body, subject: 'profile_help_feedback_subject'.tr);
      if (!mounted) return;
      if (shared) {
        _feedback.clear();
        showStrideSnack(context, 'profile_help_feedback_handed'.tr);
      }
    } on ApiException catch (e) {
      if (mounted) showStrideSnack(context, e.status == 429 ? 'profile_help_too_many'.tr : 'profile_help_send_error'.tr, isError: true);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'profile_help_send_error_copy'.tr, isError: true);
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
      label: 'profile_help_open_settings'.tr,
      icon: Icons.settings_outlined,
      onPressed: () => ref.read(permissionsProvider).openSettings(),
    );
    return StrideScreen(
      title: 'profile_help_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          SectionHeader(title: 'profile_help_guides'.tr),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.gps_fixed,
                title: 'profile_help_gps_title'.tr,
                subtitle: 'profile_help_gps_subtitle'.tr,
                onTap: () =>
                    _guide('profile_help_gps_title'.tr, ['profile_help_gps_p1'.tr, 'profile_help_gps_p2'.tr, 'profile_help_gps_p3'.tr], action: openSettings),
              ),
              SettingsRow(
                icon: Icons.directions_walk,
                title: 'profile_help_steps_title'.tr,
                subtitle: 'profile_help_steps_subtitle'.tr,
                onTap: () => _guide('profile_help_steps_title'.tr, [
                  'profile_help_steps_p1'.tr,
                  'profile_help_steps_p2'.tr,
                  'profile_help_steps_p3'.tr,
                ], action: openSettings),
              ),
              SettingsRow(
                icon: Icons.battery_alert_outlined,
                title: 'profile_help_battery_title'.tr,
                subtitle: 'profile_help_battery_subtitle'.tr,
                onTap: () => _guide('profile_help_battery_title'.tr, [
                  if (isAndroid) ...['profile_help_battery_android_p1'.tr, 'profile_help_battery_android_p2'.tr] else 'profile_help_battery_ios'.tr,
                  'profile_help_battery_common'.tr,
                ], action: openSettings),
              ),
            ],
          ),
          const Gap(16),
          ProfileSection(
            title: 'profile_help_send_feedback'.tr,
            subtitle: 'profile_help_send_subtitle'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('help-feedback'),
                  controller: _feedback,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: 'profile_help_what_happened'.tr, errorText: _feedbackError),
                  onChanged: (_) {
                    if (_feedbackError != null) setState(() => _feedbackError = null);
                  },
                ),
                ProfileSwitchRow(
                  title: 'profile_help_include_diag'.tr,
                  subtitle: 'profile_help_include_diag_subtitle'.tr,
                  value: _includeDiagnostics,
                  onChanged: (v) => setState(() => _includeDiagnostics = v),
                ),
                const Gap(8),
                PrimaryButton(label: 'profile_help_send_feedback'.tr, icon: Icons.send_outlined, onPressed: _shareFeedback),
              ],
            ),
          ),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.content_copy,
                title: 'profile_help_copy_diag'.tr,
                subtitle: 'profile_help_copy_diag_subtitle'.tr,
                showChevron: false,
                onTap: _copyDiagnostics,
              ),
              SettingsRow(icon: Icons.info_outline, title: 'profile_help_app_version'.tr, subtitle: profileVersionLabel, showChevron: false),
            ],
          ),
        ],
      ),
    );
  }
}
