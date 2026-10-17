import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class IntervalEditorScreen extends StatelessWidget {
  const IntervalEditorScreen({super.key, this.planId});
  final String? planId;

  @override
  Widget build(BuildContext context) => const TodoScreen('IntervalEditorScreen');
}
