import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ActivityMapScreen extends StatelessWidget {
  const ActivityMapScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) => const TodoScreen('ActivityMapScreen');
}
