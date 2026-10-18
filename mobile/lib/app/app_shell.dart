import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';

/// App shell 5 tab: Home → Progress → Run → History → Profile (D03).
/// Nút Run nổi bật 64 nhưng chỉ selected khi thực sự ở tab Run.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Progress'),
    (Icons.directions_run, Icons.directions_run, 'Run'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'History'),
    (Icons.person_outline, Icons.person, 'Profile'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: StrideColors.surface,
          border: Border(top: BorderSide(color: StrideColors.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(children: [for (var i = 0; i < _tabs.length; i++) Expanded(child: i == 2 ? _runButton(i) : _tab(i))]),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final (icon, selIcon, label) = _tabs[i];
    final selected = shell.currentIndex == i;
    final color = selected ? StrideColors.primary : StrideColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label tab',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: StrideText.caption.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runButton(int i) {
    final selected = shell.currentIndex == i;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Run tab',
      excludeSemantics: true,
      child: Center(
        child: Material(
          color: StrideColors.primary,
          shape: CircleBorder(side: BorderSide(color: selected ? StrideColors.lime : StrideColors.surface, width: 3)),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _go(i),
            child: const SizedBox(
              width: 58,
              height: 58,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_run, color: Colors.white, size: 24),
                  Text(
                    'Run',
                    style: TextStyle(fontFamily: StrideText.fontFamily, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
