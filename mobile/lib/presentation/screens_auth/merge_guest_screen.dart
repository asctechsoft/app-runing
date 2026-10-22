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
      showStrideSnack(context, 'Activities moved to your account. They will sync when you are online.');
      context.go(routeAfterMerge(ref.read(ownerProvider)));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't move your activities. Nothing was changed — try again.");
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
              title: 'Log in first',
              message: 'Log in to an account to move activities saved on this device.',
              actionLabel: 'Log in',
              onAction: () => context.go(Routes.login),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard());
          }
          if (snap.hasError) {
            return ErrorState(title: "Couldn't read this device's activities", message: 'Try again.', onRetry: () => setState(() => _count = _load()));
          }
          final n = snap.data ?? 0;
          if (n == 0) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nothing to move',
              message: 'There are no activities saved without an account on this device.',
              actionLabel: 'Continue',
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
                child: Text('Move your activities?', style: StrideText.title, textAlign: TextAlign.center),
              ),
              const SizedBox(height: StrideSpace.s8),
              Text(
                'You have $n ${n == 1 ? 'activity' : 'activities'} saved on this device without an account. '
                'Move ${n == 1 ? 'it' : 'them'} to ${owner.email ?? 'this account'} to back ${n == 1 ? 'it' : 'them'} up and see ${n == 1 ? 'it' : 'them'} on other devices.',
                style: StrideText.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: StrideSpace.s16),
              const StatusBanner(
                tone: BannerTone.info,
                message: 'If you keep them separate, they stay on this device and are only visible when you use STRIDE without an account.',
              ),
              if (_error != null) ...[const SizedBox(height: StrideSpace.s12), StatusBanner(tone: BannerTone.error, message: _error!)],
              const SizedBox(height: StrideSpace.s32),
              PrimaryButton(label: 'Move to this account', loading: _busy, onPressed: _move),
              const SizedBox(height: StrideSpace.s8),
              SecondaryButton(label: 'Keep separate', onPressed: _busy ? null : _keepSeparate),
            ],
          );
        },
      ),
    );
  }
}
