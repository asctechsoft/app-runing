import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../services/native/permission_coordinator.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/setup_widgets.dart';
import '../../utils/l10n.dart';

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
          showStrideSnack(context, 'setup_perm_step_off'.tr);
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
            label: _status[PermKind.motion] == PermStatus.granted ? 'setup_continue'.tr : 'setup_perm_enable_steps'.tr,
            trailingIcon: Icons.arrow_forward,
            loading: _finishing,
            onPressed: () => _finish(enableSteps: true),
          ),
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(label: 'setup_perm_later'.tr, onPressed: _finishing ? null : () => _finish(enableSteps: false)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetupHeader(step: 2, title: 'setup_perm_title'.tr, subtitle: 'setup_perm_subtitle'.tr),
          _PermRow(
            icon: Icons.directions_walk,
            title: 'setup_perm_motion_title'.tr,
            badge: 'setup_perm_needed'.tr,
            body: 'setup_perm_motion_body'.tr,
            status: _status[PermKind.motion],
            onTap: () => _handle(PermKind.motion),
          ),
          _PermRow(
            icon: Icons.location_on_outlined,
            title: 'setup_perm_location_title'.tr,
            badge: 'setup_perm_needed'.tr,
            body: 'setup_perm_location_body'.tr,
            status: _status[PermKind.location],
            onTap: () => _handle(PermKind.location),
          ),
          _PermRow(
            icon: Icons.notifications_none,
            title: 'setup_perm_notif_title'.tr,
            badge: 'setup_perm_optional'.tr,
            body: 'setup_perm_notif_body'.tr,
            status: _status[PermKind.notification],
            onTap: () => _handle(PermKind.notification),
          ),
          const SizedBox(height: StrideSpace.s8),
          StrideCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, color: StrideColors.primary),
                const SizedBox(width: StrideSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('setup_perm_privacy_title'.tr, style: StrideText.label),
                      const SizedBox(height: 2),
                      Text('setup_perm_privacy_body'.tr, style: StrideText.bodySecondary),
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
    null => ('setup_perm_status_checking'.tr, StrideColors.textMuted, null),
    PermStatus.granted => ('setup_perm_status_granted'.tr, StrideColors.primary, null),
    PermStatus.limited => ('setup_perm_status_limited'.tr, StrideColors.warning, 'setup_perm_action_review'.tr),
    PermStatus.denied => ('setup_perm_status_denied'.tr, StrideColors.warning, 'setup_perm_action_allow'.tr),
    PermStatus.blocked => ('setup_perm_status_blocked'.tr, StrideColors.error, 'setup_perm_action_open_settings'.tr),
    PermStatus.restricted => ('setup_perm_status_restricted'.tr, StrideColors.error, 'setup_perm_action_open_settings'.tr),
    PermStatus.unknown => ('setup_perm_status_unknown'.tr, StrideColors.textSecondary, 'setup_perm_action_allow'.tr),
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
                          color: badge == 'setup_perm_needed'.tr ? StrideColors.lime : StrideColors.surface,
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
