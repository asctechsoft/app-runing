import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) => const TodoScreen('SavedScreen');
}
