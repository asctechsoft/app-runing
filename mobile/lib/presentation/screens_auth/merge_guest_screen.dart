import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/sync/sync_providers.dart';
import '../../controller/auth/auth_flow.dart';
import '../../utils/l10n.dart';

/// Hỏi chuyển dữ liệu khách vào tài khoản vừa đăng nhập (E03). Không bao giờ tự gộp.
class MergeGuestScreen extends ConsumerStatefulWidget {
  const MergeGuestScreen({super.key});

  @override
  ConsumerState<MergeGuestScreen> createState() => _MergeGuestScreenState();
}

class _MergeGuestScreenState extends ConsumerState<MergeGuestScreen> {
  late Future<int> _count;
  final _guard = OnceGuard();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _count = _load();
  }

  Future<int> _load() => ref.read(activityRepositoryProvider).countSaved(ref.read(ownerRepositoryProvider).guestId());

  Future<void> _move() => _guard.run(() async {
    final owner = ref.read(ownerProvider);
    if (owner.isGuest) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(guestTransferProvider).transfer(guestId: ref.read(ownerRepositoryProvider).guestId(), userId: owner.ownerId);
      ref.read(ownerProvider.notifier).reload();
      unawaited(ref.read(syncServiceProvider).syncNow());
      if (!mounted) return;
      showStrideSnack(context, 'auth_merge_moved_snack'.tr);
      context.go(routeAfterMerge(ref.read(ownerProvider)));
    } catch (e) {
      if (mounted) setState(() => _error = 'auth_merge_move_error'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  void _keepSeparate() {
    // Dữ liệu khách giữ nguyên owner khách; tài khoản không thấy chúng.
    context.go(routeAfterMerge(ref.read(ownerProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(ownerProvider);
    return StrideScreen(
      showBack: false,
      body: FutureBuilder<int>(
        future: _count,
        builder: (context, snap) {
          if (owner.isGuest) {
            return EmptyState(
              icon: Icons.person_outline,
              title: 'auth_merge_login_first_title'.tr,
              message: 'auth_merge_login_first_msg'.tr,
              actionLabel: 'auth_log_in'.tr,
              onAction: () => context.go(Routes.login),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard());
          }
          if (snap.hasError) {
            return ErrorState(title: 'auth_merge_read_error_title'.tr, message: 'auth_try_again'.tr, onRetry: () => setState(() => _count = _load()));
          }
          final n = snap.data ?? 0;
          if (n == 0) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              title: 'auth_merge_nothing_title'.tr,
              message: 'auth_merge_nothing_msg'.tr,
              actionLabel: 'auth_continue'.tr,
              onAction: _keepSeparate,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: StrideSpace.s32),
              const Center(child: IconBadge(icon: Icons.move_down, size: 64)),
              const SizedBox(height: StrideSpace.s24),
              Semantics(
                header: true,
                child: Text('auth_merge_title'.tr, style: StrideText.title, textAlign: TextAlign.center),
              ),
              const SizedBox(height: StrideSpace.s8),
              Text(
                (n == 1 ? 'auth_merge_body_one' : 'auth_merge_body_other').trArgs([n, owner.email ?? 'auth_merge_this_account'.tr]),
                style: StrideText.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: StrideSpace.s16),
              StatusBanner(tone: BannerTone.info, message: 'auth_merge_keep_note'.tr),
              if (_error != null) ...[const SizedBox(height: StrideSpace.s12), StatusBanner(tone: BannerTone.error, message: _error!)],
              const SizedBox(height: StrideSpace.s32),
              PrimaryButton(label: 'auth_merge_move'.tr, loading: _busy, onPressed: _move),
              const SizedBox(height: StrideSpace.s8),
              SecondaryButton(label: 'auth_merge_keep_separate'.tr, onPressed: _busy ? null : _keepSeparate),
            ],
          );
        },
      ),
    );
  }
}
