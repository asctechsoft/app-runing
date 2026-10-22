import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/auth/auth_flow.dart';
import '../../repository/auth_repository.dart';
import 'components/auth_widgets.dart';

/// Đăng ký email (E02). Quy tắc mật khẩu hiển thị trực tiếp, đúng quy tắc backend.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _guard = OnceGuard();
  bool _agreed = false;
  bool _busy = false;
  bool _showAgreeError = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    final ok = _form.currentState?.validate() ?? false;
    setState(() => _showAgreeError = !_agreed);
    if (!ok || !_agreed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final user = await ref.read(authRepositoryProvider).register(email: email, password: _password.text, displayName: _name.text);
      final next = await completeSignInWidget(ref, user);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      context.go(next);
      if (!user.emailVerified) {
        showStrideSnack(context, 'We sent a verification link to $email.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e, AuthAction.register));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(authRepositoryProvider).available;
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Back up your activities and use STRIDE on more than one device.',
      children: [
        if (!available)
          const AccountsUnavailable()
        else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[StatusBanner(tone: BannerTone.error, message: _error!), const SizedBox(height: StrideSpace.s12)],
                AuthTextField(
                  controller: _name,
                  label: 'Full name',
                  icon: Icons.person_outline,
                  autofillHints: const [AutofillHints.name],
                  enabled: !_busy,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Enter your name.';
                    if (s.length > 60) return 'Use 60 characters or fewer.';
                    return null;
                  },
                ),
                AuthTextField(
                  controller: _email,
                  label: 'Email address',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: validateEmail,
                  enabled: !_busy,
                ),
                AuthTextField(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  password: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  validator: (v) => passwordValid(v ?? '') ? null : 'Password doesn\'t meet the requirements below.',
                ),
                PasswordRulesList(password: _password.text),
                const SizedBox(height: StrideSpace.s12),
                MergeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(value: _agreed, onChanged: _busy ? null : (v) => setState(() => _agreed = v ?? false)),
                      Expanded(
                        child: GestureDetector(
                          onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
                          child: const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('I agree to the Terms of Service and Privacy Policy.', style: StrideText.body),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showAgreeError && !_agreed)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                    child: Text('Agree to the terms to create an account.', style: StrideText.label.copyWith(color: StrideColors.error)),
                  ),
                const SizedBox(height: StrideSpace.s12),
                PrimaryButton(label: 'Create account', trailingIcon: Icons.arrow_forward, loading: _busy, onPressed: _submit),
                const SizedBox(height: StrideSpace.s16),
                InlineLink(prefix: 'Already have an account?', label: 'Log in', onTap: () => context.pushReplacement(Routes.login)),
              ],
            ),
          ),
      ],
    );
  }
}
