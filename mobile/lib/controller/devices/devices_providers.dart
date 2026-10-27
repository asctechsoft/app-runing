import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repository/device_repository.dart';
import '../../services/application/heart_rate_plugin.dart';
import '../../services/application/heart_rate_transport.dart';
import '../providers.dart';
import '../run_plugins.dart';

/// Lớp BLE thật; test override bằng transport giả.
final heartRateTransportProvider = Provider<HeartRateTransport>((ref) => FlutterBluePlusTransport());

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) => DeviceRepository(ref.watch(databaseProvider), ref.watch(clockProvider)));

/// Danh sách thiết bị đã ghép (chưa revoke) của owner hiện tại; tự làm mới khi repo đổi.
final pairedDevicesProvider = StreamProvider<List<PairedDevice>>((ref) async* {
  final owner = ref.watch(ownerProvider).ownerId;
  final repo = ref.watch(deviceRepositoryProvider);
  yield await repo.list(owner);
  await for (final changed in repo.changes) {
    if (changed == owner) yield await repo.list(owner);
  }
});

class HeartRateStatusNotifier extends Notifier<HeartRateStatus> {
  @override
  HeartRateStatus build() => const HeartRateStatus();

  void set(HeartRateStatus s) => state = s;
}

/// Trạng thái nhịp tim trong phiên chạy: unavailable / connecting / connected / lost (+ bpm & thời điểm cuối).
final heartRateStatusProvider = NotifierProvider<HeartRateStatusNotifier, HeartRateStatus>(HeartRateStatusNotifier.new);

/// Plugin L03 cho engine phiên chạy; null khi flag devices.ble tắt. Integrator ghép vào runPluginsProvider.
final heartRateRunPluginProvider = Provider<RunPlugin?>((ref) {
  if (!ref.watch(flagsProvider).devicesBle) return null;
  return HeartRatePlugin(
    repository: ref.watch(deviceRepositoryProvider),
    transport: ref.watch(heartRateTransportProvider),
    clock: ref.watch(clockProvider),
    onStatus: (s) => ref.read(heartRateStatusProvider.notifier).set(s),
  );
});
