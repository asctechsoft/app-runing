import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context) => const TodoScreen('ClubsScreen');
}

class ClubDetailScreen extends StatelessWidget {
  const ClubDetailScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context) => const TodoScreen('ClubDetailScreen');
}
