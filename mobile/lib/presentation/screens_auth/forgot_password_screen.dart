import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/auth_repository.dart';
import 'components/auth_widgets.dart';

/// Quên mật khẩu: luôn hiển thị kết quả chung để không lộ email có tài khoản hay không (F02).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _guard = OnceGuard();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).forgotPassword(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e, AuthAction.forgot));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(authRepositoryProvider).available;
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: "Enter the email you use for STRIDE and we'll send you a link to reset your password.",
      fallback: Routes.login,
      children: [
        if (!available)
          const AccountsUnavailable()
        else if (_sent) ...[
          StatusBanner(
            tone: BannerTone.success,
            title: 'Check your email',
            message: 'If an account exists for ${_email.text.trim()}, a reset link is on its way. The link is valid for 30 minutes.',
          ),
          const SizedBox(height: StrideSpace.s24),
          PrimaryButton(label: 'Back to log in', onPressed: () => popOr(context, Routes.login)),
          const SizedBox(height: StrideSpace.s8),
          SecondaryButton(label: 'Send again', onPressed: () => setState(() => _sent = false)),
        ] else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
                AuthTextField(
                  controller: _email,
                  label: 'Email',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: validateEmail,
                  enabled: !_busy,
                ),
                const SizedBox(height: StrideSpace.s8),
                PrimaryButton(label: 'Send reset link', loading: _busy, onPressed: _submit),
              ],
            ),
          ),
      ],
    );
  }
}

/// Đặt mật khẩu mới từ link email (`/auth/reset?token=`).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});
  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _guard = OnceGuard();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(token: widget.token!, newPassword: _password.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e, AuthAction.reset));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final token = widget.token;
    final available = ref.watch(authRepositoryProvider).available;
    return AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Changing your password signs you out on all devices.',
      fallback: Routes.login,
      children: [
        if (!available)
          const AccountsUnavailable()
        else if (token == null || token.length < 16) ...[
          const StatusBanner(tone: BannerTone.error, message: 'This reset link is invalid or has expired. Request a new one.'),
          const SizedBox(height: StrideSpace.s16),
          PrimaryButton(label: 'Request a new link', onPressed: () => context.go(Routes.forgotPassword)),
        ] else if (_done) ...[
          const StatusBanner(tone: BannerTone.success, title: 'Password updated', message: 'Log in with your new password.'),
          const SizedBox(height: StrideSpace.s24),
          PrimaryButton(label: 'Log in', onPressed: () => context.go(Routes.login)),
        ] else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
                AuthTextField(
                  controller: _password,
                  label: 'New password',
                  icon: Icons.lock_outline,
                  password: true,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  validator: (v) => passwordValid(v ?? '') ? null : "Password doesn't meet the requirements below.",
                  enabled: !_busy,
                ),
                AuthTextField(
                  controller: _confirm,
                  label: 'Confirm new password',
                  icon: Icons.lock_outline,
                  password: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v == _password.text ? null : "Passwords don't match.",
                  enabled: !_busy,
                ),
                PasswordRulesList(password: _password.text),
                const SizedBox(height: StrideSpace.s16),
                PrimaryButton(label: 'Update password', loading: _busy, onPressed: _submit),
              ],
            ),
          ),
      ],
    );
  }
}
