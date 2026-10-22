import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../values/routes.dart';
import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';
import '../../../repository/auth_repository.dart';

/// Quay lại màn trước; nếu mở trực tiếp (không có stack) thì về [fallback] (E02: hủy auth quay lại đúng chỗ).
void popOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Khung chung cho các màn auth: back, wordmark, tiêu đề + mô tả.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.fallback = Routes.welcome, this.bottom});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String fallback;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return StrideScreen(
      onBack: () => popOr(context, fallback),
      bottom: bottom,
      body: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: StrideSpace.s8),
            const Align(alignment: Alignment.centerLeft, child: StrideWordmark()),
            const SizedBox(height: StrideSpace.s24),
            Semantics(header: true, child: Text(title, style: StrideText.title)),
            if (subtitle != null) ...[const SizedBox(height: StrideSpace.s8), Text(subtitle!, style: StrideText.bodySecondary)],
            const SizedBox(height: StrideSpace.s24),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Ô nhập có nhãn thật (không dùng placeholder thay nhãn), icon đầu, mật khẩu có show/hide.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.password = false,
    this.keyboardType,
    this.autofillHints,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool password;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: StrideSpace.s12),
      child: TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: widget.password && _obscure,
        enableSuggestions: !widget.password,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        validator: widget.validator,
        inputFormatters: widget.inputFormatters,
        style: StrideText.body,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon, color: StrideColors.textSecondary),
          suffixIcon: widget.password
              ? IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
      ),
    );
  }
}

/// Danh sách quy tắc mật khẩu cập nhật theo từng ký tự gõ — chỉ các quy tắc backend thực sự kiểm tra.
class PasswordRulesList extends StatelessWidget {
  const PasswordRulesList({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final tooLong = passwordTooLong(password);
    return Container(
      padding: const EdgeInsets.all(StrideSpace.s12),
      decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(StrideRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in passwordRules) _RuleRow(label: r.label, met: r.test(password)),
          if (tooLong) const _RuleRow(label: 'Password is too long', met: false, error: true),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.met, this.error = false});
  final String label;
  final bool met;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? StrideColors.error : (met ? StrideColors.primary : StrideColors.textSecondary);
    return Semantics(
      label: '$label, ${met ? 'met' : 'not met'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(error ? Icons.error_outline : (met ? Icons.check_circle : Icons.radio_button_unchecked), size: 18, color: color),
            const SizedBox(width: StrideSpace.s8),
            Expanded(
              child: Text(
                label,
                style: StrideText.label.copyWith(fontWeight: FontWeight.w400, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trạng thái trung thực khi build không có server: không giả lập đăng nhập thành công.
class AccountsUnavailable extends StatelessWidget {
  const AccountsUnavailable({super.key});

  @override
  Widget build(BuildContext context) => const StatusBanner(
    tone: BannerTone.info,
    title: "Accounts aren't available in this build",
    message: 'You can keep using STRIDE without an account. Your activities stay on this device.',
  );
}

/// Dòng "Already have an account? Log in" (link trong câu).
class InlineLink extends StatelessWidget {
  const InlineLink({super.key, required this.prefix, required this.label, required this.onTap});
  final String prefix;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prefix, style: StrideText.bodySecondary),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 6)),
          child: Text(
            label,
            style: StrideText.body.copyWith(color: StrideColors.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: StrideSpace.s12),
    child: Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: StrideText.caption),
        ),
        Expanded(child: Divider()),
      ],
    ),
  );
}
