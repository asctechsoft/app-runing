import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class FilteredRunsScreen extends StatelessWidget {
  const FilteredRunsScreen({super.key, this.fromMs, this.toMs, this.title});
  final int? fromMs;
  final int? toMs;
  final String? title;

  @override
  Widget build(BuildContext context) => const TodoScreen('FilteredRunsScreen');
}
