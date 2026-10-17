import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key, this.email});
  final String? email;

  @override
  Widget build(BuildContext context) => const TodoScreen('VerifyEmailScreen');
}
