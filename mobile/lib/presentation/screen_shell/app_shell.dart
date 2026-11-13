import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/tour/tour_controller.dart';
import '../../utils/haptics.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/tour_anchor.dart';

/// App shell 5 tab: Home → Progress → Run → History → Profile (D03).
/// Nút Run nổi bật 64 nhưng chỉ selected khi thực sự ở tab Run.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;
  late final TourController _tour = ref.read(tourControllerProvider);

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'shell_tab_home'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'shell_tab_progress'),
    (Icons.directions_run, Icons.directions_run, 'shell_tab_run'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'shell_tab_history'),
    (Icons.person_outline, Icons.person, 'shell_tab_profile'),
  ];

  @override
  void initState() {
    super.initState();
    // Lần đầu vào app: tour chờ anchor đầu tiên rồi tự hiện.
    _tour.selectTab = (tab) => shell.goBranch(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tour.start());
  }

  @override
  void dispose() {
    _tour.selectTab = null;
    super.dispose();
  }

  void _go(int i) {
    StrideHaptics.selection();
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

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
    final tab = Semantics(
      selected: selected,
      button: true,
      label: 'shell_tab_semantic'.trArgs([label.tr]),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label.tr,
              style: StrideText.caption.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
    return i == 4 ? TourAnchor(id: TourAnchors.profileTab, child: tab) : tab;
  }

  Widget _runButton(int i) {
    final selected = shell.currentIndex == i;
    return TourAnchor(id: TourAnchors.runButton, child: _runButtonBody(i, selected));
  }

  Widget _runButtonBody(int i, bool selected) {
    return Semantics(
      selected: selected,
      button: true,
      label: 'shell_tab_semantic'.trArgs(['shell_tab_run'.tr]),
      excludeSemantics: true,
      child: Center(
        child: Material(
          color: StrideColors.primary,
          shape: CircleBorder(side: BorderSide(color: selected ? StrideColors.lime : StrideColors.surface, width: 3)),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _go(i),
            child: SizedBox(
              width: 58,
              height: 58,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.directions_run, color: Colors.white, size: 24),
                  Text(
                    'shell_tab_run'.tr,
                    style: const TextStyle(fontFamily: StrideText.fontFamily, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
