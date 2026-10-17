import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ShareActivityScreen extends StatelessWidget {
  const ShareActivityScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context) => const TodoScreen('ShareActivityScreen');
}
