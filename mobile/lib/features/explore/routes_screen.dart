import 'package:flutter/material.dart';
import '../../core/widgets/todo_screen.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) => const TodoScreen('RoutesScreen');
}

class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({super.key, required this.routeId});
  final String routeId;

  @override
  Widget build(BuildContext context) => const TodoScreen('RouteDetailScreen');
}
