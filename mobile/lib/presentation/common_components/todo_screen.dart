import 'package:flutter/material.dart';

/// TẠM THỜI trong lúc dựng khung route (D04). Không được còn trong build phát hành:
/// `grep -r TodoScreen lib/features` phải rỗng.
class TodoScreen extends StatelessWidget {
  const TodoScreen(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: const SizedBox.shrink(),
  );
}
