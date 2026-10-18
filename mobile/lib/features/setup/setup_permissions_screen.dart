import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'setup_widgets.dart';

/// Bước 3: giải thích và xin từng quyền riêng (E05, F04). Từ chối vẫn vào app được.
class SetupPermissionsScreen extends ConsumerStatefulWidget {
  const SetupPermissionsScreen({super.key});

  @override
  ConsumerState<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends ConsumerState<SetupPermissionsScreen> {
  final _guard = OnceGuard();
  final Map<PermKind, PermStatus> _status = {};
  StreamSubscription<void>? _sub;
  bool _finishing = false;

  static const _kinds = [PermKind.motion, PermKind.location, PermKind.notification];

  @override
  void initState() {
    super.initState();
    _refresh();
    // Quay lại từ Settings hệ thống → kiểm tra lại, không tin giá trị cũ.
    _sub = ref.read(permissionsProvider).changes.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final p = ref.read(permissionsProvider);
    for (final k in _kinds) {
      try {
        final s = await p.status(k);
        if (mounted) setState(() => _status[k] = s);
      } catch (_) {
        if (mounted) setState(() => _status[k] = PermStatus.unknown);
      }
    }
  }

  Future<void> _handle(PermKind kind) => _guard.run(() async {
    final p = ref.read(permissionsProvider);
    final current = _status[kind];
    if (current == PermStatus.blocked || current == PermStatus.restricted || current == PermStatus.limited) {
      await p.openSettings();
      return;
    }
    if (current == PermStatus.granted) return;
    final s = await p.request(kind);
    if (mounted) setState(() => _status[kind] = s);
  });

  Future<void> _finish({required bool enableSteps}) => _guard.run(() async {
    setState(() => _finishing = true);
    try {
      if (enableSteps && _status[PermKind.motion] != PermStatus.granted) {
        final p = ref.read(permissionsProvider);
        final st = _status[PermKind.motion];
        if (st == PermStatus.blocked || st == PermStatus.restricted) {
          await p.openSettings();
          return;
        }
        final s = await p.request(PermKind.motion);
        if (mounted) setState(() => _status[PermKind.motion] = s);
        if (s != PermStatus.granted && mounted) {
          showStrideSnack(context, 'Step tracking is off. You can turn it on later in Profile → Data sources.');
        }
      }
      final owners = ref.read(ownerRepositoryProvider);
      await owners.markProfileSetupDone(ref.read(ownerProvider).ownerId);
      ref.read(ownerProvider.notifier).reload();
      if (mounted) context.go(Routes.home);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    return StrideScreen(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: _status[PermKind.motion] == PermStatus.granted ? 'Continue' : 'Enable step tracking',
            trailingIcon: Icons.arrow_forward,
            loading: _finishing,
            onPressed: () => _finish(enableSteps: true),
          ),
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(label: 'Set up later', onPressed: _finishing ? null : () => _finish(enableSteps: false)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SetupHeader(step: 2, title: 'Ready to move', subtitle: 'Enable a few permissions to get the most out of STRIDE. You can change them anytime.'),
          _PermRow(
            icon: Icons.directions_walk,
            title: 'Motion & steps',
            badge: 'Needed',
            body: 'Allow access to your motion activity to count steps throughout the day.',
            status: _status[PermKind.motion],
            onTap: () => _handle(PermKind.motion),
          ),
          _PermRow(
            icon: Icons.location_on_outlined,
            title: 'Location',
            badge: 'Needed',
            body: 'Used only while you record an outdoor activity, for distance, pace and your route.',
            status: _status[PermKind.location],
            onTap: () => _handle(PermKind.location),
          ),
          _PermRow(
            icon: Icons.notifications_none,
            title: 'Notifications',
            badge: 'Optional',
            body: 'Get reminders and progress updates you choose to turn on.',
            status: _status[PermKind.notification],
            onTap: () => _handle(PermKind.notification),
          ),
          const SizedBox(height: StrideSpace.s8),
          const StrideCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: StrideColors.primary),
                SizedBox(width: StrideSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your privacy matters', style: StrideText.label),
                      SizedBox(height: 2),
                      Text(
                        'Location is recorded only during activities you start, never all day. Activities are private by default and you control your data in Profile.',
                        style: StrideText.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.icon, required this.title, required this.badge, required this.body, required this.status, required this.onTap});
  final IconData icon;
  final String title;
  final String badge;
  final String body;
  final PermStatus? status;
  final VoidCallback onTap;

  (String, Color, String?) get _statusInfo => switch (status) {
    null => ('Checking…', StrideColors.textMuted, null),
    PermStatus.granted => ('Allowed', StrideColors.primary, null),
    PermStatus.limited => ('Allowed with limits', StrideColors.warning, 'Review'),
    PermStatus.denied => ('Not allowed', StrideColors.warning, 'Allow'),
    PermStatus.blocked => ('Blocked in system settings', StrideColors.error, 'Open settings'),
    PermStatus.restricted => ('Restricted on this device', StrideColors.error, 'Open settings'),
    PermStatus.unknown => ('Not set up yet', StrideColors.textSecondary, 'Allow'),
  };

  @override
  Widget build(BuildContext context) {
    final (text, color, action) = _statusInfo;
    return Padding(
      padding: const EdgeInsets.only(bottom: StrideSpace.s12),
      child: SageCard(
        semanticLabel: '$title, $badge. $text',
        onTap: action == null ? null : onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon),
            const SizedBox(width: StrideSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: StrideText.subheading)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badge == 'Needed' ? StrideColors.lime : StrideColors.surface,
                          borderRadius: BorderRadius.circular(StrideRadius.pill),
                        ),
                        child: Text(
                          badge,
                          style: StrideText.caption.copyWith(color: StrideColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: StrideText.bodySecondary),
                  const SizedBox(height: StrideSpace.s8),
                  Row(
                    children: [
                      Icon(status == PermStatus.granted ? Icons.check_circle : Icons.info_outline, size: 18, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(text, style: StrideText.label.copyWith(color: color)),
                      ),
                      if (action != null) TextButton(onPressed: onTap, child: Text(action)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
