import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../repository/auth_repository.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
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
      title: 'auth_forgot_title'.tr,
      subtitle: 'auth_forgot_subtitle'.tr,
      fallback: Routes.login,
      children: [
        if (!available)
          const AccountsUnavailable()
        else if (_sent) ...[
          StatusBanner(tone: BannerTone.success, title: 'auth_check_email'.tr, message: 'auth_reset_sent'.trArgs([_email.text.trim()])),
          const SizedBox(height: StrideSpace.s24),
          PrimaryButton(label: 'auth_back_to_login'.tr, onPressed: () => popOr(context, Routes.login)),
          const SizedBox(height: StrideSpace.s8),
          SecondaryButton(label: 'auth_send_again'.tr, onPressed: () => setState(() => _sent = false)),
        ] else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
                AuthTextField(
                  controller: _email,
                  label: 'auth_email'.tr,
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: validateEmail,
                  enabled: !_busy,
                ),
                const SizedBox(height: StrideSpace.s8),
                PrimaryButton(label: 'auth_send_reset_link'.tr, loading: _busy, onPressed: _submit),
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
      title: 'auth_reset_title'.tr,
      subtitle: 'auth_reset_subtitle'.tr,
      fallback: Routes.login,
      children: [
        if (!available)
          const AccountsUnavailable()
        else if (token == null || token.length < 16) ...[
          StatusBanner(tone: BannerTone.error, message: 'auth_reset_link_invalid'.tr),
          const SizedBox(height: StrideSpace.s16),
          PrimaryButton(label: 'auth_request_new_link'.tr, onPressed: () => context.go(Routes.forgotPassword)),
        ] else if (_done) ...[
          StatusBanner(tone: BannerTone.success, title: 'auth_password_updated'.tr, message: 'auth_password_updated_msg'.tr),
          const SizedBox(height: StrideSpace.s24),
          PrimaryButton(label: 'auth_log_in'.tr, onPressed: () => context.go(Routes.login)),
        ] else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
                AuthTextField(
                  controller: _password,
                  label: 'auth_new_password'.tr,
                  icon: Icons.lock_outline,
                  password: true,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  validator: (v) => passwordValid(v ?? '') ? null : 'auth_err_password_requirements'.tr,
                  enabled: !_busy,
                ),
                AuthTextField(
                  controller: _confirm,
                  label: 'auth_confirm_new_password'.tr,
                  icon: Icons.lock_outline,
                  password: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v == _password.text ? null : 'auth_err_passwords_mismatch'.tr,
                  enabled: !_busy,
                ),
                PasswordRulesList(password: _password.text),
                const SizedBox(height: StrideSpace.s16),
                PrimaryButton(label: 'auth_update_password'.tr, loading: _busy, onPressed: _submit),
              ],
            ),
          ),
      ],
    );
  }
}
