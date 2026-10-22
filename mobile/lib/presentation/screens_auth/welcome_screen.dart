import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/auth_repository.dart';
import 'components/google_sign_in_button.dart';
import 'components/auth_widgets.dart';

/// Chọn cách bắt đầu: email / đăng nhập / dùng thử (F02). Apple/Google chỉ hiện khi flag bật.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  void _guest(BuildContext context, WidgetRef ref) {
    // Dùng thử: owner khách ổn định trên máy, không cần mạng.
    ref.read(ownerRepositoryProvider).guestId();
    ref.read(ownerProvider.notifier).reload();
    final owner = ref.read(ownerProvider);
    context.go(owner.profileSetupDone ? Routes.home : Routes.setupProfile);
  }

  void _social(BuildContext context, String provider) {
    // Apple: flag bật nhưng chưa có endpoint → báo thật, không giả thành công.
    showStrideSnack(context, 'Sign in with $provider isn\'t available yet. Continue with email instead.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final available = ref.watch(authRepositoryProvider).available && flags.authEmail;
    return Scaffold(
      backgroundColor: StrideColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: StrideSpace.gutter, vertical: StrideSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: StrideWordmark()),
                  const SizedBox(height: StrideSpace.s16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(StrideRadius.card),
                    child: Semantics(
                      label: 'Runner smiling during a run in the park',
                      image: true,
                      child: Image.asset(
                        'assets/images/onboarding_steps.jpg',
                        height: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(height: 200, color: StrideColors.subtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  Semantics(
                    header: true,
                    child: const Text('Find your stride', style: StrideText.title, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  const Text(
                    'Track your runs, build healthy habits and discover a more active you.',
                    style: StrideText.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  if (!available) ...[
                    const AccountsUnavailable(),
                    const SizedBox(height: StrideSpace.s16),
                    PrimaryButton(label: 'Continue without an account', trailingIcon: Icons.arrow_forward, onPressed: () => _guest(context, ref)),
                  ] else ...[
                    if (flags.authApple) ...[
                      PrimaryButton(label: 'Continue with Apple', icon: Icons.apple, onPressed: () => _social(context, 'Apple')),
                      const SizedBox(height: StrideSpace.s8),
                    ],
                    if (flags.authGoogle) ...[const GoogleSignInButton(), const SizedBox(height: StrideSpace.s8)],
                    (flags.authApple || flags.authGoogle)
                        ? OutlineButton(label: 'Continue with email', icon: Icons.mail_outline, onPressed: () => context.push(Routes.register))
                        : PrimaryButton(label: 'Continue with email', icon: Icons.mail_outline, onPressed: () => context.push(Routes.register)),
                    const OrDivider(),
                    InlineLink(prefix: 'Already have an account?', label: 'Log in', onTap: () => context.push(Routes.login)),
                    const SizedBox(height: StrideSpace.s8),
                    OutlineButton(label: 'Try without an account', onPressed: () => _guest(context, ref)),
                  ],
                  const SizedBox(height: StrideSpace.s16),
                  const Text(
                    "By continuing, you agree to STRIDE's Terms of Service and Privacy Policy. Without an account, your data stays on this device.",
                    style: StrideText.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
