import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'device_repository.dart';
import 'devices_controller.dart';
import 'devices_providers.dart';
import 'heart_rate_transport.dart';

/// Profile → Data sources → Connect a device (L01/L02).
/// Ma trận hỗ trợ: chỉ cảm biến Bluetooth LE Heart Rate Service chuẩn (0x180D / 0x2A37); không liệt kê tên hãng.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    if (!flags.devicesBle) {
      return const StrideScreen(
        title: 'Connect a device',
        body: EmptyState(
          icon: Icons.bluetooth_disabled,
          title: 'Device connections aren\'t available',
          message: 'This version of STRIDE can\'t connect to sensors. Your runs still record with your phone.',
        ),
      );
    }
    return StrideScreen(
      title: 'Connect a device',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SizedBox(height: StrideSpace.s8),
          Text('Add a heart rate sensor to see your heart rate while you run.', style: StrideText.bodySecondary),
          SizedBox(height: StrideSpace.s16),
          _SupportCard(),
          SizedBox(height: StrideSpace.s24),
          _PairedSection(),
          SizedBox(height: StrideSpace.s24),
          _FindSection(),
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
      children: const [
        Row(
          children: [
            IconBadge(icon: Icons.monitor_heart_outlined),
            SizedBox(width: StrideSpace.s12),
            Expanded(child: Text('Bluetooth heart rate sensors', style: StrideText.subheading)),
          ],
        ),
        SizedBox(height: StrideSpace.s12),
        Text(
          'STRIDE works with sensors that use the standard Bluetooth heart rate service, such as many chest straps and armbands. '
          'Many watches don\'t share heart rate this way.',
          style: StrideText.body,
        ),
        SizedBox(height: StrideSpace.s8),
        Text('Not available yet: watch accounts, fitness tracker apps and file import.', style: StrideText.bodySecondary),
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
        const SectionHeader(title: 'Your devices'),
        const SizedBox(height: StrideSpace.s8),
        paired.when(
          loading: () => const LoadingCard(height: 72),
          error: (e, _) => StatusBanner(
            tone: BannerTone.error,
            message: 'Couldn\'t load your devices.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(pairedDevicesProvider),
          ),
          data: (list) => list.isEmpty
              ? const StrideCard(child: Text('No devices connected yet. Scan below to add a sensor.', style: StrideText.bodySecondary))
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
      subtitle = 'Connecting…';
    } else if (connectedHere && s.lost) {
      subtitle = 'Disconnected. Check that the sensor is worn and nearby.';
    } else if (connectedHere && s.noContact && s.liveBpm == null) {
      subtitle = 'Connected · sensor isn\'t detecting skin contact';
    } else if (connectedHere) {
      subtitle = 'Connected · used automatically on your next run';
    } else {
      final at = device.connectedAt;
      subtitle = at == null ? 'Not connected yet' : 'Last connected ${DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(at))}';
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
                  label: 'Heart rate ${s.liveBpm ?? 'not available'} bpm',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: s.liveBpm?.toString() ?? '—', style: StrideText.metricSmall),
                        TextSpan(
                          text: ' bpm',
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
                TextButton(onPressed: ctrl.disconnect, child: const Text('Disconnect'))
              else
                TextButton(
                  onPressed: s.busy ? null : () => ctrl.connect(remoteId: device.remoteId, name: device.name),
                  child: Text(connectedHere && s.lost ? 'Reconnect' : 'Connect'),
                ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: StrideColors.error),
                onPressed: connecting ? null : () => _forget(context, ref),
                child: const Text('Forget'),
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
      title: 'Forget ${device.name}?',
      message: 'STRIDE will stop using this sensor. Heart rate already saved in your activities stays.',
      confirmLabel: 'Forget device',
      cancelLabel: 'Cancel',
      destructive: true,
      icon: Icons.link_off,
    );
    if (!ok) return;
    try {
      await ref.read(devicesControllerProvider.notifier).forget(device);
      if (context.mounted) showStrideSnack(context, '${device.name} removed');
    } catch (_) {
      if (context.mounted) showStrideSnack(context, 'Couldn\'t remove ${device.name}. Try again.', isError: true);
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
        const SectionHeader(title: 'Find a sensor'),
        const SizedBox(height: StrideSpace.s8),
        perm.when(
          loading: () => const LoadingCard(height: 96),
          error: (e, _) => StatusBanner(
            tone: BannerTone.error,
            message: 'Couldn\'t check Bluetooth access.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(devicesBluetoothPermissionProvider),
          ),
          data: (status) => switch (status) {
            PermStatus.granted || PermStatus.limited => const _AdapterGate(),
            PermStatus.blocked || PermStatus.restricted => PermissionState(
              icon: Icons.bluetooth_disabled,
              title: 'Bluetooth access is off',
              message: 'Turn on Bluetooth access for STRIDE in your phone settings to find your sensor. Your runs still record without it.',
              actionLabel: 'Open phone settings',
              onAction: () => ref.read(permissionsProvider).openSettings(),
            ),
            _ => PermissionState(
              icon: Icons.bluetooth,
              title: 'Allow Bluetooth',
              message: 'STRIDE uses Bluetooth only to find and connect your heart rate sensor.',
              actionLabel: 'Allow Bluetooth',
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
      error: (e, _) => const StatusBanner(tone: BannerTone.error, message: 'Couldn\'t read Bluetooth status on this phone.'),
      data: (a) => switch (a) {
        BleAdapter.on => const _ScanPanel(),
        BleAdapter.off => const StatusBanner(
          tone: BannerTone.warning,
          icon: Icons.bluetooth_disabled,
          title: 'Bluetooth is off',
          message: 'Turn on Bluetooth in your phone settings to find sensors.',
        ),
        BleAdapter.unsupported => const StatusBanner(tone: BannerTone.error, message: 'This phone doesn\'t support Bluetooth LE sensors.'),
        BleAdapter.unauthorized => PermissionState(
          icon: Icons.bluetooth_disabled,
          title: 'Bluetooth access is off',
          message: 'Turn on Bluetooth access for STRIDE in your phone settings to find your sensor.',
          actionLabel: 'Open phone settings',
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
            actionLabel: s.connectErrorRemoteId != null ? 'Retry' : null,
            onAction: s.connectErrorRemoteId != null ? ctrl.retryConnect : null,
          ),
          const SizedBox(height: StrideSpace.s12),
        ],
        if (s.scanError != null) ...[StatusBanner(tone: BannerTone.error, message: s.scanError!), const SizedBox(height: StrideSpace.s12)],
        const Text('Wear your sensor so it wakes up, keep it close to your phone and disconnect it from other apps.', style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s12),
        if (s.scan == ScanPhase.scanning)
          SecondaryButton(label: 'Stop scanning', icon: Icons.stop, onPressed: ctrl.stopScan)
        else
          PrimaryButton(label: 'Scan for sensors', icon: Icons.bluetooth_searching, onPressed: s.busy ? null : ctrl.startScan),
        if (s.scan == ScanPhase.scanning) ...[
          const SizedBox(height: StrideSpace.s12),
          const Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: StrideSpace.s12),
              Expanded(child: Text('Looking for heart rate sensors…', style: StrideText.body)),
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
                  subtitle: s.connectingRemoteId == f.remoteId ? 'Connecting…' : 'Heart rate sensor',
                  showChevron: false,
                  trailing: s.connectingRemoteId == f.remoteId
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: s.busy ? null : () => ctrl.connect(remoteId: f.remoteId, name: f.displayName),
                          child: const Text('Connect'),
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
                const Text('No new sensors found', style: StrideText.subheading),
                const SizedBox(height: StrideSpace.s4),
                Text(
                  s.found.isEmpty
                      ? 'Make sure your sensor is worn, nearby and not connected to another app, then scan again.'
                      : 'The sensors nearby are already in your devices.',
                  style: StrideText.bodySecondary,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
