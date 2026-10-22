import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/native/permission_coordinator.dart';
import '../providers.dart';
import '../../repository/device_repository.dart';
import 'devices_providers.dart';
import '../../services/application/heart_rate_parser.dart';
import '../../services/application/heart_rate_transport.dart';

enum ScanPhase { idle, scanning, done, error }

class DevicesState {
  const DevicesState({
    this.scan = ScanPhase.idle,
    this.found = const [],
    this.scanError,
    this.connectingRemoteId,
    this.connectError,
    this.connectErrorRemoteId,
    this.connectErrorName,
    this.connectedDeviceId,
    this.connectedRemoteId,
    this.liveBpm,
    this.noContact = false,
    this.lost = false,
  });

  final ScanPhase scan;
  final List<FoundSensor> found;
  final String? scanError;
  final String? connectingRemoteId;
  final String? connectError;
  final String? connectErrorRemoteId;
  final String? connectErrorName;

  /// Thiết bị đang kết nối trong màn này (PairedDevice.id).
  final String? connectedDeviceId;
  final String? connectedRemoteId;

  /// bpm đo thật gần nhất; null → hiển thị "—".
  final int? liveBpm;
  final bool noContact;

  /// Kết nối vừa bị mất (cảm biến tắt / ra xa).
  final bool lost;

  bool get busy => connectingRemoteId != null;

  DevicesState copyWith({
    ScanPhase? scan,
    List<FoundSensor>? found,
    String? Function()? scanError,
    String? Function()? connectingRemoteId,
    String? Function()? connectError,
    String? Function()? connectErrorRemoteId,
    String? Function()? connectErrorName,
    String? Function()? connectedDeviceId,
    String? Function()? connectedRemoteId,
    int? Function()? liveBpm,
    bool? noContact,
    bool? lost,
  }) => DevicesState(
    scan: scan ?? this.scan,
    found: found ?? this.found,
    scanError: scanError != null ? scanError() : this.scanError,
    connectingRemoteId: connectingRemoteId != null ? connectingRemoteId() : this.connectingRemoteId,
    connectError: connectError != null ? connectError() : this.connectError,
    connectErrorRemoteId: connectErrorRemoteId != null ? connectErrorRemoteId() : this.connectErrorRemoteId,
    connectErrorName: connectErrorName != null ? connectErrorName() : this.connectErrorName,
    connectedDeviceId: connectedDeviceId != null ? connectedDeviceId() : this.connectedDeviceId,
    connectedRemoteId: connectedRemoteId != null ? connectedRemoteId() : this.connectedRemoteId,
    liveBpm: liveBpm != null ? liveBpm() : this.liveBpm,
    noContact: noContact ?? this.noContact,
    lost: lost ?? this.lost,
  );
}

/// Quản lý quét / kết nối / quên thiết bị cho DevicesScreen (L01/L02). Rời màn → ngắt kết nối tạm.
class DevicesController extends Notifier<DevicesState> {
  static const scanTimeout = Duration(seconds: 15);
  static const connectTimeout = Duration(seconds: 15);

  StreamSubscription<List<FoundSensor>>? _scanSub;
  HeartRateConnection? _conn;
  StreamSubscription<HeartRateMeasurement>? _measureSub;
  bool _disposed = false;

  HeartRateTransport get _transport => ref.read(heartRateTransportProvider);
  DeviceRepository get _repo => ref.read(deviceRepositoryProvider);

  @override
  DevicesState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _scanSub?.cancel();
      _measureSub?.cancel();
      final c = _conn;
      _conn = null;
      if (c != null) unawaited(c.disconnect().catchError((_) {}));
    });
    return const DevicesState();
  }

  void _set(DevicesState s) {
    if (!_disposed) state = s;
  }

  Future<void> startScan() async {
    if (state.scan == ScanPhase.scanning || state.busy) return;
    await _scanSub?.cancel();
    _set(state.copyWith(scan: ScanPhase.scanning, found: const [], scanError: () => null, connectError: () => null));
    final done = Completer<void>();
    _scanSub = _transport
        .scan(timeout: scanTimeout)
        .listen(
          (list) {
            // Gộp theo remoteId, giữ thứ tự xuất hiện.
            final byId = <String, FoundSensor>{for (final f in state.found) f.remoteId: f};
            for (final f in list) {
              byId[f.remoteId] = f;
            }
            _set(state.copyWith(found: byId.values.toList()));
          },
          onError: (Object e) {
            _set(state.copyWith(scan: ScanPhase.error, scanError: () => 'Couldn\'t scan for sensors. Check that Bluetooth is on and try again.'));
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (state.scan == ScanPhase.scanning) _set(state.copyWith(scan: ScanPhase.done));
            if (!done.isCompleted) done.complete();
          },
        );
    await done.future;
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _transport.stopScan();
    } catch (_) {}
    if (state.scan == ScanPhase.scanning) _set(state.copyWith(scan: ScanPhase.done));
  }

  Future<void> connect({required String remoteId, required String name}) async {
    if (state.busy) return;
    await stopScan();
    await _closeConnection();
    _set(
      state.copyWith(
        connectingRemoteId: () => remoteId,
        connectError: () => null,
        connectErrorRemoteId: () => null,
        connectErrorName: () => null,
        connectedDeviceId: () => null,
        connectedRemoteId: () => null,
        liveBpm: () => null,
        lost: false,
        noContact: false,
      ),
    );
    try {
      final conn = await _transport.connect(remoteId, timeout: connectTimeout);
      if (_disposed) {
        await conn.disconnect();
        return;
      }
      final owner = ref.read(ownerProvider).ownerId;
      final saved = await _repo.savePaired(ownerId: owner, name: name, remoteId: remoteId);
      _conn = conn;
      _measureSub = conn.measurements.listen((m) {
        if (m.isReliable) {
          _set(state.copyWith(liveBpm: () => m.bpm, noContact: false));
        } else {
          _set(state.copyWith(noContact: true));
        }
      });
      unawaited(
        conn.lost.then((_) {
          if (!identical(_conn, conn)) return;
          _measureSub?.cancel();
          _conn = null;
          _set(state.copyWith(lost: true, liveBpm: () => null));
        }),
      );
      _set(state.copyWith(connectingRemoteId: () => null, connectedDeviceId: () => saved.id, connectedRemoteId: () => remoteId));
    } on HeartRateConnectException catch (e) {
      final msg = switch (e.reason) {
        'timeout' => 'Couldn\'t connect to $name. Make sure the sensor is worn and nearby, then try again.',
        'noHeartRateService' => '$name doesn\'t provide the standard Bluetooth heart rate service, so STRIDE can\'t use it.',
        _ => 'Couldn\'t connect to $name. Try again.',
      };
      _set(
        state.copyWith(
          connectingRemoteId: () => null,
          connectError: () => msg,
          connectErrorRemoteId: () => e.reason == 'noHeartRateService' ? null : remoteId,
          connectErrorName: () => name,
        ),
      );
    } catch (_) {
      _set(
        state.copyWith(
          connectingRemoteId: () => null,
          connectError: () => 'Couldn\'t connect to $name. Try again.',
          connectErrorRemoteId: () => remoteId,
          connectErrorName: () => name,
        ),
      );
    }
  }

  Future<void> retryConnect() async {
    final id = state.connectErrorRemoteId;
    final name = state.connectErrorName;
    if (id == null || name == null) return;
    await connect(remoteId: id, name: name);
  }

  Future<void> _closeConnection() async {
    await _measureSub?.cancel();
    _measureSub = null;
    final c = _conn;
    _conn = null;
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
    }
  }

  /// Ngắt kết nối nhưng vẫn giữ thiết bị trong danh sách (sẽ dùng cho lần chạy sau).
  Future<void> disconnect() async {
    await _closeConnection();
    _set(state.copyWith(connectedDeviceId: () => null, connectedRemoteId: () => null, liveBpm: () => null, lost: false, noContact: false));
  }

  /// Quên thiết bị: revoke → ngừng nhập dữ liệu từ thiết bị này.
  Future<void> forget(PairedDevice d) async {
    if (state.connectedDeviceId == d.id) await disconnect();
    await _repo.revoke(d.id);
  }

  void dismissError() => _set(state.copyWith(connectError: () => null, connectErrorRemoteId: () => null, connectErrorName: () => null));
}

final devicesControllerProvider = NotifierProvider.autoDispose<DevicesController, DevicesState>(DevicesController.new);

/// Quyền Bluetooth (kiểm tra lại khi PermissionCoordinator báo đổi, vd. app resume).
final devicesBluetoothPermissionProvider = StreamProvider.autoDispose<PermStatus>((ref) async* {
  final p = ref.watch(permissionsProvider);
  yield await p.status(PermKind.bluetooth);
  await for (final _ in p.changes) {
    yield await p.status(PermKind.bluetooth);
  }
});

final devicesAdapterProvider = StreamProvider.autoDispose<BleAdapter>((ref) => ref.watch(heartRateTransportProvider).adapterState());
