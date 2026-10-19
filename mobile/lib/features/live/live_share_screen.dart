import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'live_share_models.dart';
import 'live_share_providers.dart';
import 'live_share_repository.dart';

/// Run → Share live location (M07). Chỉ cấu hình + đồng ý cho buổi chạy kế tiếp; share thật bắt đầu khi phiên bắt đầu.
class LiveShareScreen extends ConsumerWidget {
  const LiveShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final owner = ref.watch(ownerProvider);
    final configured = ref.watch(liveShareRepositoryProvider).configured;

    if (!flags.liveSharing) {
      return const StrideScreen(
        title: 'Share live location',
        body: EmptyState(
          icon: Icons.location_off_outlined,
          title: 'Live sharing isn\'t available',
          message: 'This version of STRIDE doesn\'t include live sharing.',
        ),
      );
    }
    if (owner.isGuest) {
      return StrideScreen(
        title: 'Share live location',
        body: EmptyState(
          icon: Icons.person_outline,
          title: 'Sign in to share live location',
          message: 'Live sharing sends your location to people you choose, so it needs a STRIDE account. Your runs still record without signing in.',
          actionLabel: 'Sign in',
          onAction: () => context.push(Routes.login),
        ),
      );
    }
    if (!configured) {
      return const StrideScreen(
        title: 'Share live location',
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Live sharing isn\'t set up',
          message: 'This build isn\'t connected to STRIDE servers, so live sharing can\'t be used.',
        ),
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
          PrimaryButton(label: 'Start sharing for this run', trailingIcon: Icons.arrow_forward, onPressed: canStart ? () => _confirm(context, ref) : null),
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(
            label: 'Cancel',
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
          const Text('Share live location', style: StrideText.title),
          const SizedBox(height: StrideSpace.s8),
          const Text(
            'Let trusted people follow your run in real time. They\'ll see your live location and activity status while sharing is active.',
            style: StrideText.bodySecondary,
          ),
          const SizedBox(height: StrideSpace.s16),
          const _MapPreview(),
          const SizedBox(height: StrideSpace.s16),
          StrideCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: const Icon(Icons.location_on_outlined, color: StrideColors.primary),
              title: Text('Live sharing', style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Share your live location for this run', style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
              value: config.enabled,
              onChanged: notifier.setEnabled,
            ),
          ),
          if (config.enabled) ...[
            const SizedBox(height: StrideSpace.s16),
            const SectionHeader(title: 'Choose who can follow this run', subtitle: 'Only people you select can view your live location.'),
            const SizedBox(height: StrideSpace.s8),
            SettingsGroup(
              children: [
                for (final v in config.viewers)
                  SettingsRow(
                    icon: Icons.person_outline,
                    title: v.label,
                    subtitle: 'Can follow this run',
                    showChevron: false,
                    trailing: IconButton(tooltip: 'Remove ${v.label}', icon: const Icon(Icons.close), onPressed: () => notifier.removeViewer(v)),
                  ),
                SettingsRow(icon: Icons.person_add_alt_1_outlined, title: 'Add contact', onTap: () => _addContact(context, ref)),
              ],
            ),
            const SizedBox(height: StrideSpace.s16),
            SettingsGroup(
              children: [
                SettingsRow(icon: Icons.schedule, title: 'Sharing expires', subtitle: config.expiry.label, onTap: () => _pickExpiry(context, ref)),
                const SettingsRow(icon: Icons.description_outlined, title: 'Shared data', subtitle: 'Live location and activity status'),
              ],
            ),
            const SizedBox(height: StrideSpace.s16),
            const Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: StrideColors.textSecondary),
                SizedBox(width: StrideSpace.s8),
                Expanded(child: Text('Only selected people can view while sharing is active.', style: StrideText.bodySecondary)),
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
    final until = config.expiry == LiveShareExpiry.whenRunEnds ? 'until this run ends' : config.expiry.label.toLowerCase().replaceFirst('after', 'for');
    final ok = await confirmDialog(
      context,
      icon: Icons.location_on_outlined,
      title: 'Share your live location?',
      message: '$names will see your live location and activity status $until. Sharing starts when you start your run and stops when the run ends.',
      confirmLabel: 'Share for this run',
      cancelLabel: 'Not now',
    );
    if (!ok || !context.mounted) return;
    ref.read(liveShareConfigProvider.notifier).consent(ref.read(clockProvider).nowMs());
    showStrideSnack(context, 'Live sharing will start when your run starts');
    context.pop();
  }

  Future<void> _pickExpiry(BuildContext context, WidgetRef ref) async {
    final current = ref.read(liveShareConfigProvider).expiry;
    final picked = await showStrideSheet<LiveShareExpiry>(
      context,
      title: 'Sharing expires',
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
    final viewer = await showStrideSheet<LiveShareViewer>(context, title: 'Add contact', builder: (_) => const _AddContactSheet());
    if (viewer == null || !context.mounted) return;
    final added = ref.read(liveShareConfigProvider.notifier).addViewer(viewer);
    if (!added) showStrideSnack(context, '${viewer.label} is already added or the list is full (20 people).');
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
          error: (_, _) => placeholder('Your live location will appear here during the run.'),
          data: (p) => p == null
              ? placeholder('Your live location will appear here during the run.')
              : Semantics(
                  label: 'Map preview of your current area',
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: p,
                      initialZoom: 14,
                      backgroundColor: StrideColors.subtle,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(urlTemplate: env.tileUrlTemplate, userAgentPackageName: 'com.asc.app_runing'),
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

/// Thêm người theo dõi bằng email tài khoản STRIDE đã xác minh (backend xác nhận và trả userId).
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
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final mine = ref.read(ownerProvider).email;
    if (mine != null && mine.toLowerCase() == email.toLowerCase()) {
      setState(() => _error = 'You can\'t add yourself.');
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
          _error = e.isNetwork ? 'No connection. Check your internet and try again.' : e.message;
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
        const Text('Enter the email of their STRIDE account. Only verified accounts can follow your run.', style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: 'Email', errorText: _error),
        ),
        const SizedBox(height: StrideSpace.s16),
        PrimaryButton(label: 'Add', loading: _loading, onPressed: _submit),
      ],
    );
  }
}
