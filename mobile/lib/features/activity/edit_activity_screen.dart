import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class EditActivityScreen extends StatelessWidget {
  const EditActivityScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) => const TodoScreen('EditActivityScreen');
}
