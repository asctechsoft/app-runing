import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/auth_repository.dart';
import 'components/auth_widgets.dart';

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
      if (mounted) showStrideSnack(context, 'Verification email sent.');
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
      title: 'Verify your email',
      subtitle: email == null ? 'Open the link we sent to your email to verify your account.' : 'We sent a verification link to $email.',
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
                const StatusBanner(tone: BannerTone.success, title: 'Email verified', message: 'Thanks! Your email address is confirmed.'),
                const SizedBox(height: StrideSpace.s24),
                PrimaryButton(label: 'Continue', onPressed: () => context.go(owner.isGuest ? Routes.login : Routes.home)),
              ],
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_message != null) ...[StatusBanner(tone: BannerTone.error, message: _message!), const SizedBox(height: StrideSpace.s16)],
                const Text(
                  "Didn't get it? Check your spam folder, or send a new link. You can keep using STRIDE while you wait.",
                  style: StrideText.bodySecondary,
                ),
                const SizedBox(height: StrideSpace.s24),
                if (!owner.isGuest) ...[PrimaryButton(label: 'Send a new link', loading: _sending, onPressed: _resend), const SizedBox(height: StrideSpace.s8)],
                SecondaryButton(label: owner.isGuest ? 'Log in' : 'Done', onPressed: () => context.go(owner.isGuest ? Routes.login : Routes.home)),
              ],
            ),
          },
      ],
    );
  }
}
