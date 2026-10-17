import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, this.period, this.kind, this.anchor});
  final String? period;
  final String? kind;
  final String? anchor;

  @override
  Widget build(BuildContext context) => const TodoScreen('ProgressScreen');
}
