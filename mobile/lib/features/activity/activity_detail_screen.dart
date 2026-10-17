import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) => const TodoScreen('ActivityDetailScreen');
}
