import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class DailyStepsScreen extends StatelessWidget {
  const DailyStepsScreen({super.key, this.date});
  final String? date;

  @override
  Widget build(BuildContext context) => const TodoScreen('DailyStepsScreen');
}
