import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => const TodoScreen('ForgotPasswordScreen');
}

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key, this.token});
  final String? token;

  @override
  Widget build(BuildContext context) => const TodoScreen('ResetPasswordScreen');
}
