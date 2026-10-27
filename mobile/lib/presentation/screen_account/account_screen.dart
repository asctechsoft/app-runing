import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../controller/providers.dart';
import '../../controller/sync/sync_providers.dart';
import '../../repository/account_repository.dart';
import '../../repository/auth_repository.dart';
import '../../services/application/google_sign_in_service.dart';
import '../../services/application/sync_service.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Profile → Account & data (J05, H06, I07, F21): tài khoản, đồng bộ, export, đăng xuất, xóa tài khoản.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(ownerProvider);
    final available = ref.watch(authRepositoryProvider).available;
    return StrideScreen(
      title: 'account_title'.tr,
      onBack: () => context.canPop() ? context.pop() : context.go(Routes.profile),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: StrideSpace.s8),
          if (owner.isGuest) ...[
            StrideCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const IconBadge(icon: Icons.phone_iphone),
                      const SizedBox(width: StrideSpace.s12),
                      Expanded(child: Text('account_guest_title'.tr, style: StrideText.subheading)),
                    ],
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  Text('account_guest_body'.tr, style: StrideText.bodySecondary),
                  const SizedBox(height: StrideSpace.s16),
                  if (!available)
                    StatusBanner(tone: BannerTone.info, message: 'auth_err_not_configured'.tr)
                  else ...[
                    PrimaryButton(label: 'auth_create_account'.tr, onPressed: () => context.push(Routes.register)),
                    const SizedBox(height: StrideSpace.s8),
                    SecondaryButton(label: 'auth_log_in'.tr, onPressed: () => context.push(Routes.login)),
                  ],
                ],
              ),
            ),
          ] else ...[
            StrideCard(
              semanticLabel: 'account_signed_in_as_value'.trArgs([owner.email ?? 'account_your_account_lc'.tr]),
              child: Row(
                children: [
                  const IconBadge(icon: Icons.person_outline),
                  const SizedBox(width: StrideSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('account_signed_in_as'.tr, style: StrideText.caption),
                        Text(owner.email ?? 'account_your_account'.tr, style: StrideText.subheading, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: StrideSpace.s24),
            SectionHeader(title: 'account_section_sync'.tr),
            const _SyncSection(),
            const SizedBox(height: StrideSpace.s24),
            SectionHeader(title: 'account_section_data'.tr),
            const _ExportSection(),
            const SizedBox(height: StrideSpace.s24),
            const _DeletionSection(),
            const SizedBox(height: StrideSpace.s8),
            SettingsGroup(
              children: [
                SettingsRow(title: 'account_sign_out'.tr, icon: Icons.logout, showChevron: false, onTap: () => signOutFlow(context, ref)),
                SettingsRow(
                  title: 'account_delete_account'.tr,
                  icon: Icons.delete_outline,
                  destructive: true,
                  showChevron: false,
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _when(int ms) => DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(ms));

// ---------------- Sync ----------------

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? ref.read(syncServiceProvider).status.value;
    final conflicts = ref.watch(syncConflictsProvider).value ?? const <SyncConflict>[];
    final (tone, title, message) = switch (status.phase) {
      SyncPhase.syncing => (BannerTone.info, 'account_sync_syncing_title'.tr, 'account_sync_syncing_msg'.tr),
      SyncPhase.offline => (BannerTone.warning, 'account_sync_waiting_title'.tr, status.lastError ?? 'account_sync_offline_msg'.tr),
      SyncPhase.error => (BannerTone.error, 'account_sync_error_title'.tr, status.lastError ?? 'account_sync_error_msg'.tr),
      SyncPhase.signedOut => (BannerTone.warning, 'account_sync_signed_out_title'.tr, status.lastError ?? 'account_sync_signed_out_msg'.tr),
      SyncPhase.disabled => (BannerTone.info, 'account_sync_off_title'.tr, 'account_sync_off_msg'.tr),
      SyncPhase.idle when status.pending > 0 => (
        BannerTone.warning,
        'account_sync_pending_title'.tr,
        'account_sync_pending'.trPlural(status.pending, [status.pending]),
      ),
      SyncPhase.idle when status.lastSyncedAt != null => (
        BannerTone.success,
        'account_sync_uptodate_title'.tr,
        'account_sync_last_synced'.trArgs([_when(status.lastSyncedAt!)]),
      ),
      SyncPhase.idle => (BannerTone.info, 'account_sync_ready_title'.tr, 'account_sync_ready_msg'.tr),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBanner(
          tone: tone,
          title: title,
          message: status.pending > 0 && status.phase != SyncPhase.idle ? 'account_sync_with_pending'.trArgs([message, status.pending]) : message,
          icon: status.phase == SyncPhase.syncing ? Icons.sync : null,
        ),
        const SizedBox(height: StrideSpace.s8),
        OutlineButton(
          label: 'account_retry_sync'.tr,
          icon: Icons.sync,
          onPressed: status.phase == SyncPhase.syncing || status.phase == SyncPhase.disabled
              ? null
              : () async {
                  final s = await ref.read(syncServiceProvider).syncNow(manual: true);
                  if (!context.mounted) return;
                  if (s.phase == SyncPhase.idle && s.pending == 0) showStrideSnack(context, 'account_sync_all_done'.tr);
                },
        ),
        for (final c in conflicts) ...[const SizedBox(height: StrideSpace.s12), _ConflictCard(conflict: c)],
      ],
    );
  }
}

class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard({required this.conflict});
  final SyncConflict conflict;

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  String _choice = 'local';
  final _guard = OnceGuard();

  String _describe(Map<String, Object?>? m) {
    if (m == null) return '—';
    if (widget.conflict.entity == 'activity') {
      final parts = <String>[
        'account_conflict_field_title'.trArgs([(m['title'] as String?)?.isNotEmpty == true ? m['title'] : '—']),
        if (m['notes'] != null && (m['notes'] as String).isNotEmpty) 'account_conflict_field_notes'.trArgs([m['notes']]),
        if (m['feeling'] != null) 'account_conflict_field_feeling'.trArgs([m['feeling']]),
        'account_conflict_field_privacy'.trArgs([m['privacy'] ?? '—']),
      ];
      return parts.join('\n');
    }
    final name = m['displayName'];
    return '${'account_conflict_field_name'.trArgs([name is String && name.isNotEmpty ? name : '—'])}\n${'account_conflict_field_units'.trArgs([m['distanceUnit'] ?? '—'])}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    final sync = ref.read(syncServiceProvider);
    Widget option(String value, String label, String body) => RadioListTile<String>(
      value: value,
      // ignore: deprecated_member_use
      groupValue: _choice,
      // ignore: deprecated_member_use
      onChanged: (v) => setState(() => _choice = v ?? _choice),
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: StrideText.label),
      subtitle: Text(body, style: StrideText.bodySecondary),
    );
    return StrideCard(
      color: StrideColors.warningBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split, color: StrideColors.warning),
              const SizedBox(width: StrideSpace.s8),
              Expanded(child: Text('account_conflict_title'.trArgs([c.title]), style: StrideText.subheading)),
            ],
          ),
          const SizedBox(height: 4),
          Text('account_conflict_body'.tr, style: StrideText.bodySecondary),
          option('local', 'account_conflict_this_device'.tr, _describe(c.local)),
          option('server', 'account_conflict_other_device'.tr, _describe(c.server)),
          PrimaryButton(
            label: 'account_conflict_keep'.tr,
            onPressed: () => _guard.run(() async {
              if (_choice == 'local') {
                await sync.resolveKeepLocal(c);
              } else {
                await sync.resolveKeepServer(c);
              }
              ref.invalidate(syncConflictsProvider);
            }),
          ),
          TextButton(onPressed: () => showStrideSnack(context, 'account_conflict_later_snack'.tr), child: Text('account_conflict_decide_later'.tr)),
        ],
      ),
    );
  }
}

// ---------------- Export ----------------

class _ExportSection extends ConsumerStatefulWidget {
  const _ExportSection();

  @override
  ConsumerState<_ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<_ExportSection> {
  AccountJob? _job;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _poll;
  final _guard = OnceGuard();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final id = await ref.read(accountRepositoryProvider).lastExportId(ref.read(ownerProvider).ownerId);
      if (id != null) {
        final job = await ref.read(accountRepositoryProvider).getExport(id);
        if (mounted) setState(() => _job = job);
        _schedulePoll();
      }
    } catch (_) {
      // Không có mạng: chỉ hiển thị nút tạo export; không đoán trạng thái.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_job?.isOpen != true) return;
    _poll = Timer(const Duration(seconds: 4), () async {
      try {
        final j = await ref.read(accountRepositoryProvider).getExport(_job!.id);
        if (!mounted) return;
        setState(() => _job = j);
        _schedulePoll();
      } catch (_) {}
    });
  }

  Future<void> _create() => _guard.run(() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await ref.read(accountRepositoryProvider).createExport(ref.read(ownerProvider).ownerId);
      if (mounted) setState(() => _job = j);
      _schedulePoll();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  Future<void> _download() => _guard.run(() async {
    final job = _job;
    if (job == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(accountRepositoryProvider).downloadExport(job.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}stride-export-${job.id}.json');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'account_export_share_subject'.tr,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final now = ref.read(clockProvider).nowMs();
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.download_outlined),
              const SizedBox(width: StrideSpace.s12),
              Expanded(child: Text('account_export_title'.tr, style: StrideText.subheading)),
            ],
          ),
          const SizedBox(height: StrideSpace.s8),
          Text('account_export_body'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: StrideSpace.s12),
          if (_loading)
            const Skeleton(height: 48)
          else ...[
            if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s8)],
            if (job != null && job.isOpen) ...[
              StatusBanner(tone: BannerTone.info, title: 'account_export_preparing_title'.tr, message: 'account_export_preparing_msg'.tr),
              const SizedBox(height: StrideSpace.s8),
            ],
            if (job != null && job.failed) ...[
              StatusBanner(tone: BannerTone.error, title: 'account_export_failed_title'.tr, message: job.error ?? 'account_export_failed_default'.tr),
              const SizedBox(height: StrideSpace.s8),
            ],
            if (job != null && job.succeeded && !job.isExpired(now)) ...[
              StatusBanner(
                tone: BannerTone.success,
                title: 'account_export_ready_title'.tr,
                message: job.expiresAt == null ? 'account_export_download_now'.tr : 'account_export_available_until'.trArgs([_when(job.expiresAt!)]),
              ),
              const SizedBox(height: StrideSpace.s8),
              PrimaryButton(label: 'account_export_download'.tr, icon: Icons.download, loading: _busy, onPressed: _download),
            ] else if (job == null || !job.isOpen)
              OutlineButton(label: job == null ? 'account_export_create'.tr : 'account_export_create_new'.tr, onPressed: _busy ? null : _create),
          ],
        ],
      ),
    );
  }
}

// ---------------- Deletion ----------------

final _deletionStatusProvider = FutureProvider.autoDispose<AccountJob?>((ref) async {
  ref.watch(ownerProvider);
  return ref.watch(accountRepositoryProvider).deletionStatus();
});

class _DeletionSection extends ConsumerWidget {
  const _DeletionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(_deletionStatusProvider).value;
    if (job == null) return const SizedBox.shrink();
    if (job.succeeded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: StrideSpace.s16),
        child: StatusBanner(
          tone: BannerTone.success,
          title: 'account_deleted_title'.tr,
          message: 'account_deleted_msg'.tr,
          actionLabel: 'account_sign_out'.tr,
          onAction: () => _localSignOut(context, ref),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: StrideSpace.s16),
      child: StatusBanner(
        tone: job.failed ? BannerTone.error : BannerTone.warning,
        title: job.failed ? 'account_deletion_failed_title'.tr : 'account_deletion_requested_title'.tr,
        message: job.failed ? 'account_deletion_failed_msg'.tr : 'account_deletion_requested_msg'.trArgs([job.createdAt == null ? '' : _when(job.createdAt!)]),
        actionLabel: 'account_refresh'.tr,
        onAction: () => ref.invalidate(_deletionStatusProvider),
      ),
    );
  }
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await confirmDialog(
    context,
    title: 'account_delete_confirm_title'.tr,
    message: 'account_delete_confirm_msg'.tr,
    confirmLabel: 'account_continue'.tr,
    cancelLabel: 'action_cancel'.tr,
    destructive: true,
    icon: Icons.delete_outline,
  );
  if (!ok || !context.mounted) return;
  final job = await showStrideSheet<AccountJob>(context, title: 'account_reauth_title'.tr, builder: (_) => _ReauthDeleteForm());
  if (job == null || !context.mounted) return;
  if (job.succeeded) {
    // Tài khoản Firebase đã bị xóa → đăng xuất cục bộ (dữ liệu trên máy giữ nguyên dưới owner cũ).
    await _localSignOut(context, ref);
    return;
  }
  ref.invalidate(_deletionStatusProvider);
  showStrideSnack(context, 'account_deletion_requested_snack'.tr);
}

class _ReauthDeleteForm extends ConsumerStatefulWidget {
  const _ReauthDeleteForm();

  @override
  ConsumerState<_ReauthDeleteForm> createState() => _ReauthDeleteFormState();
}

class _ReauthDeleteFormState extends ConsumerState<_ReauthDeleteForm> {
  final _password = TextEditingController();
  final _guard = OnceGuard();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'auth_err_password_empty'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await ref.read(accountRepositoryProvider).requestDeletion(_password.text);
      if (mounted) Navigator.of(context).pop(job);
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  /// Tài khoản Google không có mật khẩu: xác thực lại bằng chính tài khoản Google đã liên kết.
  Future<void> _confirmWithGoogle() => _guard.run(() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = await ref.read(googleCredentialSourceProvider).pickCredential();
      final job = await ref.read(accountRepositoryProvider).requestDeletionWithGoogle(credential);
      if (mounted) Navigator.of(context).pop(job);
    } on GoogleSignInCancelled {
      // Người dùng hủy: giữ nguyên form.
    } catch (e) {
      if (mounted) setState(() => _error = e is GoogleSignInFailure ? 'account_reauth_google_failed'.tr : accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('account_reauth_intro'.tr, style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s16),
        if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
        TextField(
          controller: _password,
          obscureText: _obscure,
          enabled: !_busy,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'auth_password'.tr,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'auth_show_password'.tr : 'auth_hide_password'.tr,
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: StrideSpace.s16),
        DestructiveButton(label: 'account_delete_account'.tr, loading: _busy, onPressed: _submit),
        if (ref.watch(flagsProvider).authGoogle) ...[
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(label: 'account_reauth_google'.tr, icon: Icons.g_mobiledata, onPressed: _busy ? null : _confirmWithGoogle),
        ],
      ],
    );
  }
}

// ---------------- Sign out (J05) ----------------

/// Đăng xuất: chặn khi đang ghi; cảnh báo dữ liệu chưa đồng bộ; dữ liệu local vẫn gắn đúng owner.
Future<void> signOutFlow(BuildContext context, WidgetRef ref) async {
  final owner = ref.read(ownerProvider);
  if (owner.isGuest) return;
  final open = await ref.read(activityRepositoryProvider).openSession(owner.ownerId);
  if (!context.mounted) return;
  if (open != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('account_signout_busy_title'.tr),
        content: Text('account_signout_busy_msg'.tr),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('action_ok'.tr))],
      ),
    );
    return;
  }
  final sync = ref.read(syncServiceProvider);
  final pending = await sync.pendingCount(owner.ownerId);
  if (!context.mounted) return;
  if (pending > 0) {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('account_signout_unsynced_title'.tr),
        content: Text('account_signout_unsynced'.trPlural(pending, [pending])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('action_cancel'.tr)),
          TextButton(onPressed: () => Navigator.pop(ctx, 'anyway'), child: Text('account_signout_anyway'.tr)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'sync'), child: Text('account_sync_now'.tr)),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'sync') {
      final s = await sync.syncNow(manual: true);
      if (!context.mounted) return;
      if (s.pending > 0) {
        showStrideSnack(context, s.lastError ?? 'account_sync_still_waiting'.tr, isError: true);
        return;
      }
    }
  } else {
    final ok = await confirmDialog(
      context,
      title: 'account_signout_confirm_title'.tr,
      message: 'account_signout_confirm_msg'.tr,
      confirmLabel: 'account_sign_out'.tr,
      cancelLabel: 'action_cancel'.tr,
    );
    if (!ok || !context.mounted) return;
  }
  await _localSignOut(context, ref);
}

Future<void> _localSignOut(BuildContext context, WidgetRef ref) async {
  await ref.read(authRepositoryProvider).logout();
  await ref.read(googleCredentialSourceProvider).signOut();
  await ref.read(ownerRepositoryProvider).signOut();
  ref.read(ownerProvider.notifier).reload();
  await ref.read(syncServiceProvider).refreshStatus();
  if (context.mounted) context.go(Routes.welcome);
}
