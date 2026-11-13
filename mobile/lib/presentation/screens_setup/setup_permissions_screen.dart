import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../services/native/permission_coordinator.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Yêu cầu quyền truy cập (E05, F04): giải thích rồi xin quyền cảm biến chuyển động để đếm bước. Từ chối vẫn vào app được.
/// Vị trí chỉ xin khi người dùng bấm bắt đầu ở tab Run — không xin sớm vì không theo dõi vị trí cả ngày.
class SetupPermissionsScreen extends ConsumerStatefulWidget {
  const SetupPermissionsScreen({super.key});

  @override
  ConsumerState<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends ConsumerState<SetupPermissionsScreen> {
  final _guard = OnceGuard();
  PermStatus? _motion;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Quay lại từ Cài đặt hệ thống → kiểm tra lại, không tin giá trị cũ.
    _sub = ref.read(permissionsProvider).changes.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(permissionsProvider).status(PermKind.motion);
      if (mounted) setState(() => _motion = s);
    } catch (_) {
      if (mounted) setState(() => _motion = PermStatus.unknown);
    }
  }

  bool get _granted => _motion == PermStatus.granted;

  Future<void> _accept() => _guard.run(() async {
    final p = ref.read(permissionsProvider);
    if (_motion == PermStatus.blocked || _motion == PermStatus.restricted || _motion == PermStatus.limited) {
      await p.openSettings();
      return;
    }
    if (_granted) return;
    final s = await p.request(PermKind.motion);
    if (!mounted) return;
    setState(() => _motion = s);
    if (s != PermStatus.granted) showStrideSnack(context, 'setup_perm_step_off'.tr);
  });

  @override
  Widget build(BuildContext context) {
    final blocked = _motion == PermStatus.blocked || _motion == PermStatus.restricted || _motion == PermStatus.limited;
    return StrideScreen(
      title: 'setup_perm_title'.tr,
      showBack: false,
      bottom: PrimaryButton(label: 'setup_continue'.tr, trailingIcon: Icons.arrow_forward, onPressed: () => context.go(Routes.home)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: StrideSpace.s16),
          Text('setup_perm_subtitle'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
          const SizedBox(height: StrideSpace.s24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('setup_perm_motion_title'.tr, style: StrideText.subheading),
                    const SizedBox(height: StrideSpace.s4),
                    Text('setup_perm_motion_body'.tr, style: StrideText.bodySecondary),
                  ],
                ),
              ),
              const SizedBox(width: StrideSpace.s16),
              _granted
                  ? Semantics(
                      label: 'setup_perm_status_granted'.tr,
                      child: const Icon(Icons.check_circle, color: StrideColors.primary, size: 32),
                    )
                  : PrimaryButton(label: blocked ? 'setup_perm_action_open_settings'.tr : 'setup_perm_accept'.tr, expand: false, onPressed: _accept),
            ],
          ),
          const SizedBox(height: StrideSpace.s24),
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
