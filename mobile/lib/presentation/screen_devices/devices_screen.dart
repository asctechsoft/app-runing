import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controller/devices/devices_controller.dart';
import '../../controller/devices/devices_providers.dart';
import '../../controller/providers.dart';
import '../../repository/device_repository.dart';
import '../../services/application/heart_rate_transport.dart';
import '../../services/native/permission_coordinator.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Profile → Data sources → Connect a device (L01/L02).
/// Ma trận hỗ trợ: chỉ cảm biến Bluetooth LE Heart Rate Service chuẩn (0x180D / 0x2A37); không liệt kê tên hãng.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    if (!flags.devicesBle) {
      return StrideScreen(
        title: 'devices_title'.tr,
        body: EmptyState(icon: Icons.bluetooth_disabled, title: 'devices_unavailable_title'.tr, message: 'devices_unavailable_message'.tr),
      );
    }
    return StrideScreen(
      title: 'devices_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: StrideSpace.s8),
          Text('devices_intro'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: StrideSpace.s16),
          const _SupportCard(),
          const SizedBox(height: StrideSpace.s24),
          const _PairedSection(),
          const SizedBox(height: StrideSpace.s24),
          const _FindSection(),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) => SageCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBadge(icon: Icons.monitor_heart_outlined),
            const SizedBox(width: StrideSpace.s12),
            Expanded(child: Text('devices_support_title'.tr, style: StrideText.subheading)),
          ],
        ),
        const SizedBox(height: StrideSpace.s12),
        Text('devices_support_message'.tr, style: StrideText.body),
        const SizedBox(height: StrideSpace.s8),
        Text('devices_support_unavailable'.tr, style: StrideText.bodySecondary),
      ],
    ),
  );
}

class _PairedSection extends ConsumerWidget {
  const _PairedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = ref.watch(pairedDevicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'devices_your_devices'.tr),
        const SizedBox(height: StrideSpace.s8),
        paired.when(
          loading: () => const LoadingCard(height: 72),
          error: (e, _) => StatusBanner(
            tone: BannerTone.error,
            message: 'devices_load_error'.tr,
            actionLabel: 'devices_try_again'.tr,
            onAction: () => ref.invalidate(pairedDevicesProvider),
          ),
          data: (list) => list.isEmpty
              ? StrideCard(child: Text('devices_none'.tr, style: StrideText.bodySecondary))
              : Column(
                  children: [
                    for (final d in list) ...[_PairedTile(device: d), const SizedBox(height: StrideSpace.s8)],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PairedTile extends ConsumerWidget {
  const _PairedTile({required this.device});
  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(devicesControllerProvider);
    final ctrl = ref.read(devicesControllerProvider.notifier);
    final connectedHere = s.connectedDeviceId == device.id;
    final connecting = s.connectingRemoteId == device.remoteId;
    final String subtitle;
    if (connecting) {
      subtitle = 'devices_connecting'.tr;
    } else if (connectedHere && s.lost) {
      subtitle = 'devices_disconnected'.tr;
    } else if (connectedHere && s.noContact && s.liveBpm == null) {
      subtitle = 'devices_no_contact'.tr;
    } else if (connectedHere) {
      subtitle = 'devices_connected'.tr;
    } else {
      final at = device.connectedAt;
      subtitle = at == null
          ? 'devices_not_connected'.tr
          : 'devices_last_connected'.trArgs([DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(at))]);
    }
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, color: StrideColors.primary),
              const SizedBox(width: StrideSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: StrideText.body.copyWith(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
                  ],
                ),
              ),
              if (connectedHere && !s.lost)
                Semantics(
                  label: 'devices_hr_semantic'.trArgs([s.liveBpm ?? 'devices_hr_unavailable'.tr]),
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: s.liveBpm?.toString() ?? '—', style: StrideText.metricSmall),
                        TextSpan(
                          text: 'devices_bpm_unit'.tr,
                          style: StrideText.label.copyWith(color: StrideColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: StrideSpace.s8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: StrideSpace.s8,
            children: [
              if (connectedHere && !s.lost)
                TextButton(onPressed: ctrl.disconnect, child: Text('devices_disconnect'.tr))
              else
                TextButton(
                  onPressed: s.busy ? null : () => ctrl.connect(remoteId: device.remoteId, name: device.name),
                  child: Text(connectedHere && s.lost ? 'devices_reconnect'.tr : 'devices_connect'.tr),
                ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: StrideColors.error),
                onPressed: connecting ? null : () => _forget(context, ref),
                child: Text('devices_forget'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'devices_forget_title'.trArgs([device.name]),
      message: 'devices_forget_message'.tr,
      confirmLabel: 'devices_forget_confirm'.tr,
      cancelLabel: 'action_cancel'.tr,
      destructive: true,
      icon: Icons.link_off,
    );
    if (!ok) return;
    try {
      await ref.read(devicesControllerProvider.notifier).forget(device);
      if (context.mounted) showStrideSnack(context, 'devices_removed'.trArgs([device.name]));
    } catch (_) {
      if (context.mounted) showStrideSnack(context, 'devices_remove_failed'.trArgs([device.name]), isError: true);
    }
  }
}

class _FindSection extends ConsumerWidget {
  const _FindSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perm = ref.watch(devicesBluetoothPermissionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'devices_find_title'.tr),
        const SizedBox(height: StrideSpace.s8),
        perm.when(
          loading: () => const LoadingCard(height: 96),
          error: (e, _) => StatusBanner(
            tone: BannerTone.error,
            message: 'devices_bt_check_error'.tr,
            actionLabel: 'devices_try_again'.tr,
            onAction: () => ref.invalidate(devicesBluetoothPermissionProvider),
          ),
          data: (status) => switch (status) {
            PermStatus.granted || PermStatus.limited => const _AdapterGate(),
            PermStatus.blocked || PermStatus.restricted => PermissionState(
              icon: Icons.bluetooth_disabled,
              title: 'devices_bt_access_off_title'.tr,
              message: 'devices_bt_access_off_message'.tr,
              actionLabel: 'devices_open_settings'.tr,
              onAction: () => ref.read(permissionsProvider).openSettings(),
            ),
            _ => PermissionState(
              icon: Icons.bluetooth,
              title: 'devices_allow_bt'.tr,
              message: 'devices_allow_bt_message'.tr,
              actionLabel: 'devices_allow_bt'.tr,
              onAction: () async {
                await ref.read(permissionsProvider).request(PermKind.bluetooth);
                ref.invalidate(devicesBluetoothPermissionProvider);
              },
            ),
          },
        ),
      ],
    );
  }
}

class _AdapterGate extends ConsumerWidget {
  const _AdapterGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(devicesAdapterProvider);
    return adapter.when(
      loading: () => const LoadingCard(height: 96),
      error: (e, _) => StatusBanner(tone: BannerTone.error, message: 'devices_bt_status_error'.tr),
      data: (a) => switch (a) {
        BleAdapter.on => const _ScanPanel(),
        BleAdapter.off => StatusBanner(
          tone: BannerTone.warning,
          icon: Icons.bluetooth_disabled,
          title: 'devices_bt_off_title'.tr,
          message: 'devices_bt_off_message'.tr,
        ),
        BleAdapter.unsupported => StatusBanner(tone: BannerTone.error, message: 'devices_bt_unsupported'.tr),
        BleAdapter.unauthorized => PermissionState(
          icon: Icons.bluetooth_disabled,
          title: 'devices_bt_access_off_title'.tr,
          message: 'devices_bt_unauthorized_message'.tr,
          actionLabel: 'devices_open_settings'.tr,
          onAction: () => ref.read(permissionsProvider).openSettings(),
        ),
        BleAdapter.unknown => const LoadingCard(height: 96),
      },
    );
  }
}

class _ScanPanel extends ConsumerWidget {
  const _ScanPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(devicesControllerProvider);
    final ctrl = ref.read(devicesControllerProvider.notifier);
    final paired = ref.watch(pairedDevicesProvider).value ?? const <PairedDevice>[];
    final pairedIds = {for (final d in paired) d.remoteId};
    final candidates = [
      for (final f in s.found)
        if (!pairedIds.contains(f.remoteId)) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.connectError != null) ...[
          StatusBanner(
            tone: BannerTone.error,
            message: s.connectError!,
            actionLabel: s.connectErrorRemoteId != null ? 'action_retry'.tr : null,
            onAction: s.connectErrorRemoteId != null ? ctrl.retryConnect : null,
          ),
          const SizedBox(height: StrideSpace.s12),
        ],
        if (s.scanError != null) ...[StatusBanner(tone: BannerTone.error, message: s.scanError!), const SizedBox(height: StrideSpace.s12)],
        Text('devices_scan_hint'.tr, style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s12),
        if (s.scan == ScanPhase.scanning)
          SecondaryButton(label: 'devices_stop_scan'.tr, icon: Icons.stop, onPressed: ctrl.stopScan)
        else
          PrimaryButton(label: 'devices_scan'.tr, icon: Icons.bluetooth_searching, onPressed: s.busy ? null : ctrl.startScan),
        if (s.scan == ScanPhase.scanning) ...[
          const SizedBox(height: StrideSpace.s12),
          Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: StrideSpace.s12),
              Expanded(child: Text('devices_scanning'.tr, style: StrideText.body)),
            ],
          ),
        ],
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: StrideSpace.s16),
          SettingsGroup(
            children: [
              for (final f in candidates)
                SettingsRow(
                  icon: Icons.monitor_heart_outlined,
                  title: f.displayName,
                  subtitle: s.connectingRemoteId == f.remoteId ? 'devices_connecting'.tr : 'devices_hr_sensor'.tr,
                  showChevron: false,
                  trailing: s.connectingRemoteId == f.remoteId
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: s.busy ? null : () => ctrl.connect(remoteId: f.remoteId, name: f.displayName),
                          child: Text('devices_connect'.tr),
                        ),
                ),
            ],
          ),
        ] else if (s.scan == ScanPhase.done) ...[
          const SizedBox(height: StrideSpace.s16),
          StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('devices_none_found_title'.tr, style: StrideText.subheading),
                const SizedBox(height: StrideSpace.s4),
                Text(s.found.isEmpty ? 'devices_none_found_message'.tr : 'devices_all_paired'.tr, style: StrideText.bodySecondary),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
