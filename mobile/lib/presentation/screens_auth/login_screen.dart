import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../controller/auth/auth_flow.dart';
import '../../repository/auth_repository.dart';
import 'components/google_sign_in_button.dart';
import 'components/auth_widgets.dart';

/// Đăng nhập email (E02). Lỗi cụ thể; offline báo rõ; hủy quay lại màn trước.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _guard = OnceGuard();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(authRepositoryProvider).login(email: _email.text, password: _password.text);
      final next = await completeSignInWidget(ref, user);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      context.go(next);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e, AuthAction.login));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    final available = ref.watch(authRepositoryProvider).available;
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to continue your running journey.',
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
                  controller: _email,
                  label: 'Email',
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
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password.' : null,
                  enabled: !_busy,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _busy ? null : () => context.push(Routes.forgotPassword), child: const Text('Forgot password?')),
                ),
                const SizedBox(height: StrideSpace.s8),
                PrimaryButton(label: 'Log in', trailingIcon: Icons.arrow_forward, loading: _busy, onPressed: _submit),
                if (flags.authApple || flags.authGoogle) ...[
                  const OrDivider(),
                  if (flags.authApple)
                    OutlineButton(
                      label: 'Continue with Apple',
                      icon: Icons.apple,
                      onPressed: () => showStrideSnack(context, "Sign in with Apple isn't available yet. Use your email instead."),
                    ),
                  if (flags.authApple && flags.authGoogle) const SizedBox(height: StrideSpace.s8),
                  if (flags.authGoogle) const GoogleSignInButton(),
                ],
                const SizedBox(height: StrideSpace.s16),
                InlineLink(prefix: "Don't have an account?", label: 'Create account', onTap: () => context.pushReplacement(Routes.register)),
              ],
            ),
          ),
      ],
    );
  }
}
