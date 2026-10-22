import 'dart:async';
import 'dart:io';

import '../../services/application/google_sign_in_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/auth_repository.dart';
import '../../controller/sync/sync_providers.dart';
import '../../services/application/sync_service.dart';
import '../../repository/account_repository.dart';

/// Profile → Account & data (J05, H06, I07, F21): tài khoản, đồng bộ, export, đăng xuất, xóa tài khoản.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(ownerProvider);
    final available = ref.watch(authRepositoryProvider).available;
    return StrideScreen(
      title: 'Account & data',
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
                  const Row(
                    children: [
                      IconBadge(icon: Icons.phone_iphone),
                      SizedBox(width: StrideSpace.s12),
                      Expanded(child: Text('Guest — data saved on this device', style: StrideText.subheading)),
                    ],
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  const Text(
                    'Your activities are stored only on this phone. Create an account to back them up and use them on other devices.',
                    style: StrideText.bodySecondary,
                  ),
                  const SizedBox(height: StrideSpace.s16),
                  if (!available)
                    const StatusBanner(tone: BannerTone.info, message: "Accounts aren't available in this build.")
                  else ...[
                    PrimaryButton(label: 'Create account', onPressed: () => context.push(Routes.register)),
                    const SizedBox(height: StrideSpace.s8),
                    SecondaryButton(label: 'Log in', onPressed: () => context.push(Routes.login)),
                  ],
                ],
              ),
            ),
          ] else ...[
            StrideCard(
              semanticLabel: 'Signed in as ${owner.email ?? 'your account'}',
              child: Row(
                children: [
                  const IconBadge(icon: Icons.person_outline),
                  const SizedBox(width: StrideSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Signed in as', style: StrideText.caption),
                        Text(owner.email ?? 'Your account', style: StrideText.subheading, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: StrideSpace.s24),
            const SectionHeader(title: 'Sync'),
            const _SyncSection(),
            const SizedBox(height: StrideSpace.s24),
            const SectionHeader(title: 'Your data'),
            const _ExportSection(),
            const SizedBox(height: StrideSpace.s24),
            const _DeletionSection(),
            const SizedBox(height: StrideSpace.s8),
            SettingsGroup(
              children: [
                SettingsRow(title: 'Sign out', icon: Icons.logout, showChevron: false, onTap: () => signOutFlow(context, ref)),
                SettingsRow(
                  title: 'Delete account',
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
      SyncPhase.syncing => (BannerTone.info, 'Syncing…', 'Sending your changes.'),
      SyncPhase.offline => (BannerTone.warning, 'Waiting for connection', status.lastError ?? "You're offline."),
      SyncPhase.error => (BannerTone.error, 'Sync error', status.lastError ?? "Some changes couldn't be synced."),
      SyncPhase.signedOut => (BannerTone.warning, 'Not syncing', status.lastError ?? 'Log in again to sync.'),
      SyncPhase.disabled => (BannerTone.info, 'Sync is off', 'Sync is turned off in this build.'),
      SyncPhase.idle when status.pending > 0 => (
        BannerTone.warning,
        'Waiting to sync',
        '${status.pending} ${status.pending == 1 ? 'change' : 'changes'} not uploaded yet.',
      ),
      SyncPhase.idle when status.lastSyncedAt != null => (BannerTone.success, 'Up to date', 'Last synced ${_when(status.lastSyncedAt!)}.'),
      SyncPhase.idle => (BannerTone.info, 'Ready to sync', 'Tap Retry sync to check for changes.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBanner(
          tone: tone,
          title: title,
          message: status.pending > 0 && status.phase != SyncPhase.idle ? '$message ${status.pending} pending.' : message,
          icon: status.phase == SyncPhase.syncing ? Icons.sync : null,
        ),
        const SizedBox(height: StrideSpace.s8),
        OutlineButton(
          label: 'Retry sync',
          icon: Icons.sync,
          onPressed: status.phase == SyncPhase.syncing || status.phase == SyncPhase.disabled
              ? null
              : () async {
                  final s = await ref.read(syncServiceProvider).syncNow(manual: true);
                  if (!context.mounted) return;
                  if (s.phase == SyncPhase.idle && s.pending == 0) showStrideSnack(context, 'Everything is synced.');
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
        'Title: ${(m['title'] as String?)?.isNotEmpty == true ? m['title'] : '—'}',
        if (m['notes'] != null && (m['notes'] as String).isNotEmpty) 'Notes: ${m['notes']}',
        if (m['feeling'] != null) 'Feeling: ${m['feeling']}',
        'Privacy: ${m['privacy'] ?? '—'}',
      ];
      return parts.join('\n');
    }
    final name = m['displayName'];
    return 'Name: ${name is String && name.isNotEmpty ? name : '—'}\nUnits: ${m['distanceUnit'] ?? '—'}';
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
              Expanded(child: Text('Conflict: ${c.title}', style: StrideText.subheading)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('This was changed on another device too. Both versions are kept until you choose.', style: StrideText.bodySecondary),
          option('local', 'This device', _describe(c.local)),
          option('server', 'Other device', _describe(c.server)),
          PrimaryButton(
            label: 'Keep selected version',
            onPressed: () => _guard.run(() async {
              if (_choice == 'local') {
                await sync.resolveKeepLocal(c);
              } else {
                await sync.resolveKeepServer(c);
              }
              ref.invalidate(syncConflictsProvider);
            }),
          ),
          TextButton(onPressed: () => showStrideSnack(context, 'Both versions are kept. You can decide later here.'), child: const Text('Decide later')),
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
          subject: 'STRIDE data export',
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
          const Row(
            children: [
              IconBadge(icon: Icons.download_outlined),
              SizedBox(width: StrideSpace.s12),
              Expanded(child: Text('Export my data', style: StrideText.subheading)),
            ],
          ),
          const SizedBox(height: StrideSpace.s8),
          const Text(
            'A JSON file with your activities, GPS routes, profile and goals. Routes include your recorded locations — share the file carefully.',
            style: StrideText.bodySecondary,
          ),
          const SizedBox(height: StrideSpace.s12),
          if (_loading)
            const Skeleton(height: 48)
          else ...[
            if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s8)],
            if (job != null && job.isOpen) ...[
              const StatusBanner(tone: BannerTone.info, title: 'Preparing your export', message: 'This can take a few minutes. You can leave this screen.'),
              const SizedBox(height: StrideSpace.s8),
            ],
            if (job != null && job.failed) ...[
              StatusBanner(tone: BannerTone.error, title: 'Export failed', message: job.error ?? 'Please try again.'),
              const SizedBox(height: StrideSpace.s8),
            ],
            if (job != null && job.succeeded && !job.isExpired(now)) ...[
              StatusBanner(
                tone: BannerTone.success,
                title: 'Export ready',
                message: job.expiresAt == null ? 'Download it now.' : 'Available until ${_when(job.expiresAt!)}.',
              ),
              const SizedBox(height: StrideSpace.s8),
              PrimaryButton(label: 'Download export', icon: Icons.download, loading: _busy, onPressed: _download),
            ] else if (job == null || !job.isOpen)
              OutlineButton(label: job == null ? 'Create export' : 'Create a new export', onPressed: _busy ? null : _create),
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
          title: 'Account deleted',
          message: 'Your account and its data were deleted from our cloud storage.',
          actionLabel: 'Sign out',
          onAction: () => _localSignOut(context, ref),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: StrideSpace.s16),
      child: StatusBanner(
        tone: job.failed ? BannerTone.error : BannerTone.warning,
        title: job.failed ? 'Deletion failed' : 'Deletion requested',
        message: job.failed
            ? "We couldn't delete your account. Try again or contact support."
            : 'Requested ${job.createdAt == null ? '' : _when(job.createdAt!)}. Your account is not deleted until this finishes.',
        actionLabel: 'Refresh',
        onAction: () => ref.invalidate(_deletionStatusProvider),
      ),
    );
  }
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await confirmDialog(
    context,
    title: 'Delete your account?',
    message:
        'This permanently deletes your account, activities, routes, photos and goals from our cloud storage. It can\'t be undone. '
        'Export your data first if you want a copy.',
    confirmLabel: 'Continue',
    cancelLabel: 'Cancel',
    destructive: true,
    icon: Icons.delete_outline,
  );
  if (!ok || !context.mounted) return;
  final job = await showStrideSheet<AccountJob>(context, title: 'Confirm your password', builder: (_) => const _ReauthDeleteForm());
  if (job == null || !context.mounted) return;
  if (job.succeeded) {
    // Tài khoản Firebase đã bị xóa → đăng xuất cục bộ (dữ liệu trên máy giữ nguyên dưới owner cũ).
    await _localSignOut(context, ref);
    return;
  }
  ref.invalidate(_deletionStatusProvider);
  showStrideSnack(context, 'Deletion requested. We\'ll show the status here.');
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
      setState(() => _error = 'Enter your password.');
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
      if (mounted) setState(() => _error = e is GoogleSignInFailure ? "Couldn't confirm with Google. Try again." : accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('For your security, enter your password to request account deletion.', style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s16),
        if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
        TextField(
          controller: _password,
          obscureText: _obscure,
          enabled: !_busy,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: StrideSpace.s16),
        DestructiveButton(label: 'Delete account', loading: _busy, onPressed: _submit),
        if (ref.watch(flagsProvider).authGoogle) ...[
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(label: 'Signed up with Google? Confirm with Google', icon: Icons.g_mobiledata, onPressed: _busy ? null : _confirmWithGoogle),
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
        title: const Text('Finish your activity first'),
        content: const Text('You have an activity that is still recording or not saved yet. Save or discard it before signing out.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
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
        title: const Text('Some changes aren\'t synced'),
        content: Text(
          '$pending ${pending == 1 ? 'change hasn\'t' : 'changes haven\'t'} been uploaded yet. '
          'If you sign out now, ${pending == 1 ? 'it stays' : 'they stay'} on this device with your account and will sync next time you log in.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'anyway'), child: const Text('Sign out anyway')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'sync'), child: const Text('Sync now')),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'sync') {
      final s = await sync.syncNow(manual: true);
      if (!context.mounted) return;
      if (s.pending > 0) {
        showStrideSnack(context, s.lastError ?? 'Some changes are still waiting to sync.', isError: true);
        return;
      }
    }
  } else {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your activities stay on this device under your account. Log in again to see them.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Cancel',
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
