import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/auth_repository.dart';
import 'components/auth_widgets.dart';
import '../../utils/l10n.dart';

/// Xác minh email. Route `/auth/verify?email=` (hiển thị hướng dẫn + gửi lại) hoặc `?token=` từ link email.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});
  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

enum _VerifyState { idle, verifying, verified, failed }

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _guard = OnceGuard();
  _VerifyState _state = _VerifyState.idle;
  bool _sending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = GoRouterState.of(context).uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) _verify(token);
    });
  }

  Future<void> _verify(String token) => _guard.run(() async {
    setState(() {
      _state = _VerifyState.verifying;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyEmail(token);
      if (mounted) setState(() => _state = _VerifyState.verified);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _VerifyState.failed;
          _message = authErrorMessage(e, AuthAction.verify);
        });
      }
    }
  });

  Future<void> _resend() => _guard.run(() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerification();
      if (mounted) showStrideSnack(context, 'auth_verify_resent'.tr);
    } catch (e) {
      if (mounted) setState(() => _message = authErrorMessage(e, AuthAction.other));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(ownerProvider);
    final email = widget.email ?? owner.email;
    final available = ref.watch(authRepositoryProvider).available;
    return AuthScaffold(
      title: 'auth_verify_title'.tr,
      subtitle: email == null ? 'auth_verify_subtitle_no_email'.tr : 'auth_snack_verification_sent'.trArgs([email]),
      fallback: Routes.home,
      children: [
        if (!available)
          const AccountsUnavailable()
        else
          switch (_state) {
            _VerifyState.verifying => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            _VerifyState.verified => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusBanner(tone: BannerTone.success, title: 'auth_verified_title'.tr, message: 'auth_verified_msg'.tr),
                const SizedBox(height: StrideSpace.s24),
                PrimaryButton(label: 'auth_continue'.tr, onPressed: () => context.go(owner.isGuest ? Routes.login : Routes.home)),
              ],
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_message != null) ...[StatusBanner(tone: BannerTone.error, message: _message!), const SizedBox(height: StrideSpace.s16)],
                Text('auth_verify_hint'.tr, style: StrideText.bodySecondary),
                const SizedBox(height: StrideSpace.s24),
                if (!owner.isGuest) ...[PrimaryButton(label: 'auth_send_new_link'.tr, loading: _sending, onPressed: _resend), SizedBox(height: StrideSpace.s8)],
                SecondaryButton(
                  label: owner.isGuest ? 'auth_log_in'.tr : 'auth_done'.tr,
                  onPressed: () => context.go(owner.isGuest ? Routes.login : Routes.home),
                ),
              ],
            ),
          },
      ],
    );
  }
}
