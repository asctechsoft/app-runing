import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context) => const TodoScreen('ChallengesScreen');
}

class ChallengeDetailScreen extends StatelessWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});
  final String challengeId;

  @override
  Widget build(BuildContext context) => const TodoScreen('ChallengeDetailScreen');
}
