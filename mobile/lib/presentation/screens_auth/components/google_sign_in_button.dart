import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common_components/widgets.dart';
import '../../../controller/auth/auth_flow.dart';
import '../../../utils/l10n.dart';

/// "Continue with Google": chỉ hiển thị khi Firebase sẵn sàng (flags.authGoogle). Hủy chọn tài khoản → im lặng.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key, this.primary = false});
  final bool primary;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  final _guard = OnceGuard();
  bool _loading = false;

  Future<void> _go() => _guard.run(() async {
    setState(() => _loading = true);
    try {
      final next = await signInWithGoogleWidget(ref);
      if (!mounted || next == null) return;
      context.go(next);
    } catch (e) {
      if (mounted) showStrideSnack(context, googleSignInErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    if (widget.primary || _loading) {
      return PrimaryButton(label: 'auth_continue_google'.tr, icon: Icons.g_mobiledata, loading: _loading, onPressed: _go);
    }
    return OutlineButton(label: 'auth_continue_google'.tr, icon: Icons.g_mobiledata, onPressed: _go);
  }
}
