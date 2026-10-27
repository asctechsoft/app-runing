import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../controller/live/live_share_providers.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/live_share_models.dart';
import '../../repository/live_share_repository.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/map_tiles.dart';
import '../common_components/widgets.dart';

/// Run → Share live location (M07). Chỉ cấu hình + đồng ý cho buổi chạy kế tiếp; share thật bắt đầu khi phiên bắt đầu.
class LiveShareScreen extends ConsumerWidget {
  const LiveShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final owner = ref.watch(ownerProvider);
    final configured = ref.watch(liveShareRepositoryProvider).configured;

    if (!flags.liveSharing) {
      return StrideScreen(
        title: 'live_title'.tr,
        body: EmptyState(icon: Icons.location_off_outlined, title: 'live_unavailable_title'.tr, message: 'live_unavailable_message'.tr),
      );
    }
    if (owner.isGuest) {
      return StrideScreen(
        title: 'live_title'.tr,
        body: EmptyState(
          icon: Icons.person_outline,
          title: 'live_signin_title'.tr,
          message: 'live_signin_message'.tr,
          actionLabel: 'live_signin'.tr,
          onAction: () => context.push(Routes.login),
        ),
      );
    }
    if (!configured) {
      return StrideScreen(
        title: 'live_title'.tr,
        body: EmptyState(icon: Icons.cloud_off_outlined, title: 'live_not_setup_title'.tr, message: 'live_not_setup_message'.tr),
      );
    }
    return const _LiveShareForm();
  }
}

class _LiveShareForm extends ConsumerWidget {
  const _LiveShareForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(liveShareConfigProvider);
    final notifier = ref.read(liveShareConfigProvider.notifier);
    final canStart = config.enabled && config.viewers.isNotEmpty;

    return StrideScreen(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: 'live_start'.tr, trailingIcon: Icons.arrow_forward, onPressed: canStart ? () => _confirm(context, ref) : null),
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(
            label: 'action_cancel'.tr,
            onPressed: () {
              notifier.clear();
              context.pop();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('live_title'.tr, style: StrideText.title),
          const SizedBox(height: StrideSpace.s8),
          Text('live_intro'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: StrideSpace.s16),
          const _MapPreview(),
          const SizedBox(height: StrideSpace.s16),
          StrideCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: const Icon(Icons.location_on_outlined, color: StrideColors.primary),
              title: Text('live_switch_title'.tr, style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('live_switch_subtitle'.tr, style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
              value: config.enabled,
              onChanged: notifier.setEnabled,
            ),
          ),
          if (config.enabled) ...[
            const SizedBox(height: StrideSpace.s16),
            SectionHeader(title: 'live_choose_title'.tr, subtitle: 'live_choose_subtitle'.tr),
            const SizedBox(height: StrideSpace.s8),
            SettingsGroup(
              children: [
                for (final v in config.viewers)
                  SettingsRow(
                    icon: Icons.person_outline,
                    title: v.label,
                    subtitle: 'live_viewer_subtitle'.tr,
                    showChevron: false,
                    trailing: IconButton(
                      tooltip: 'live_remove_viewer'.trArgs([v.label]),
                      icon: const Icon(Icons.close),
                      onPressed: () => notifier.removeViewer(v),
                    ),
                  ),
                SettingsRow(icon: Icons.person_add_alt_1_outlined, title: 'live_add_contact'.tr, onTap: () => _addContact(context, ref)),
              ],
            ),
            const SizedBox(height: StrideSpace.s16),
            SettingsGroup(
              children: [
                SettingsRow(icon: Icons.schedule, title: 'live_expires'.tr, subtitle: config.expiry.label, onTap: () => _pickExpiry(context, ref)),
                SettingsRow(icon: Icons.description_outlined, title: 'live_shared_data'.tr, subtitle: 'live_shared_data_value'.tr),
              ],
            ),
            const SizedBox(height: StrideSpace.s16),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 18, color: StrideColors.textSecondary),
                const SizedBox(width: StrideSpace.s8),
                Expanded(child: Text('live_privacy_note'.tr, style: StrideText.bodySecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final config = ref.read(liveShareConfigProvider);
    final names = config.viewers.map((v) => v.label).join(', ');
    final until = config.expiry.untilPhrase;
    final ok = await confirmDialog(
      context,
      icon: Icons.location_on_outlined,
      title: 'live_confirm_title'.tr,
      message: 'live_confirm_message'.trArgs([names, until]),
      confirmLabel: 'live_confirm_share'.tr,
      cancelLabel: 'live_not_now'.tr,
    );
    if (!ok || !context.mounted) return;
    ref.read(liveShareConfigProvider.notifier).consent(ref.read(clockProvider).nowMs());
    showStrideSnack(context, 'live_will_start'.tr);
    context.pop();
  }

  Future<void> _pickExpiry(BuildContext context, WidgetRef ref) async {
    final current = ref.read(liveShareConfigProvider).expiry;
    final picked = await showStrideSheet<LiveShareExpiry>(
      context,
      title: 'live_expires'.tr,
      builder: (ctx) => RadioGroup<LiveShareExpiry>(
        groupValue: current,
        onChanged: (v) => Navigator.of(ctx).pop(v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in LiveShareExpiry.values)
              RadioListTile<LiveShareExpiry>(
                value: e,
                title: Text(e.label, style: StrideText.body),
              ),
          ],
        ),
      ),
    );
    if (picked != null) ref.read(liveShareConfigProvider.notifier).setExpiry(picked);
  }

  Future<void> _addContact(BuildContext context, WidgetRef ref) async {
    final viewer = await showStrideSheet<LiveShareViewer>(context, title: 'live_add_contact'.tr, builder: (_) => const _AddContactSheet());
    if (viewer == null || !context.mounted) return;
    final added = ref.read(liveShareConfigProvider.notifier).addViewer(viewer);
    if (!added) showStrideSnack(context, 'live_add_failed'.trArgs([viewer.label]));
  }
}

class _MapPreview extends ConsumerWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(liveSharePreviewPositionProvider);
    final env = ref.watch(envProvider);
    Widget placeholder(String text) => Container(
      color: StrideColors.subtle,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(StrideSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: StrideColors.primary, size: 36),
          const SizedBox(height: StrideSpace.s8),
          Text(text, style: StrideText.bodySecondary, textAlign: TextAlign.center),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(StrideRadius.card),
      child: SizedBox(
        height: 180,
        child: pos.when(
          loading: () => const Skeleton(height: 180, radius: StrideRadius.card),
          error: (_, _) => placeholder('live_map_placeholder'.tr),
          data: (p) => p == null
              ? placeholder('live_map_placeholder'.tr)
              : Semantics(
                  label: 'live_map_semantic'.tr,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: p,
                      initialZoom: 14,
                      maxZoom: mapMaxZoom,
                      backgroundColor: StrideColors.subtle,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      StrideTileLayer(env: env),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(p.latitude, p.longitude),
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: StrideColors.mapCurrent,
                                shape: BoxShape.circle,
                                border: Border.all(color: StrideColors.surface, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SimpleAttributionWidget(source: Text(env.tileAttribution, style: StrideText.caption)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Thêm người theo dõi bằng email tài khoản STRIDE đã xác minh (tra cứu `userLookup` trên Firestore để lấy userId).
class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _email = TextEditingController();
  final _guard = OnceGuard();
  bool _loading = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() => _guard.run(() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'live_err_invalid_email'.tr);
      return;
    }
    final mine = ref.read(ownerProvider).email;
    if (mine != null && mine.toLowerCase() == email.toLowerCase()) {
      setState(() => _error = 'live_err_add_self'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await ref.read(liveShareRepositoryProvider).lookupViewerByEmail(email);
      if (mounted) Navigator.of(context).pop(v);
    } on LiveShareException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.isNetwork ? 'live_err_no_connection'.tr : e.message;
        });
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('live_add_hint'.tr, style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: 'live_email'.tr, errorText: _error),
        ),
        const SizedBox(height: StrideSpace.s16),
        PrimaryButton(label: 'live_add'.tr, loading: _loading, onPressed: _submit),
      ],
    );
  }
}
