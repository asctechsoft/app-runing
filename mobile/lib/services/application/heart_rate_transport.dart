import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'heart_rate_parser.dart';

/// Trạng thái adapter Bluetooth đã chuẩn hóa.
enum BleAdapter { unknown, on, off, unauthorized, unsupported }

/// Cảm biến tìm thấy khi quét (đã lọc theo service 0x180D).
class FoundSensor {
  const FoundSensor({required this.remoteId, required this.advertisedName, this.rssi});

  final String remoteId;
  final String advertisedName;
  final int? rssi;

  /// Tên hiển thị: tên quảng bá, nếu trống → "Heart rate sensor" + đuôi id (không bịa tên hãng).
  String get displayName => advertisedName.trim().isNotEmpty ? advertisedName.trim() : 'Heart rate sensor ${idSuffix(remoteId)}';

  static String idSuffix(String id) {
    final clean = id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return clean.length <= 4 ? clean.toUpperCase() : clean.substring(clean.length - 4).toUpperCase();
  }
}

class HeartRateConnectException implements Exception {
  HeartRateConnectException(this.reason, [this.detail]);

  /// timeout | noHeartRateService | failed
  final String reason;
  final String? detail;

  @override
  String toString() => 'HeartRateConnectException($reason, $detail)';
}

/// Kết nối đang mở tới một cảm biến nhịp tim.
abstract class HeartRateConnection {
  String get remoteId;

  /// Giá trị đo đã parse (bỏ gói lỗi).
  Stream<HeartRateMeasurement> get measurements;

  /// Hoàn thành khi kết nối bị mất (không do [disconnect] chủ động).
  Future<void> get lost;

  Future<void> disconnect();
}

/// Lớp trừu tượng trên BLE để test được logic mà không cần phần cứng.
abstract class HeartRateTransport {
  Stream<BleAdapter> adapterState();

  /// Quét có timeout; phát danh sách tích lũy.
  Stream<List<FoundSensor>> scan({Duration timeout = const Duration(seconds: 15)});
  Future<void> stopScan();

  Future<HeartRateConnection> connect(String remoteId, {Duration timeout = const Duration(seconds: 15)});
}

/// Triển khai thật bằng flutter_blue_plus. Cần kiểm chứng trên máy thật với cảm biến thật.
class FlutterBluePlusTransport implements HeartRateTransport {
  static final _service = Guid(heartRateServiceUuid);
  static final _measurement = Guid(heartRateMeasurementUuid);

  @override
  Stream<BleAdapter> adapterState() async* {
    bool supported;
    try {
      supported = await FlutterBluePlus.isSupported;
    } catch (_) {
      supported = false;
    }
    if (!supported) {
      yield BleAdapter.unsupported;
      return;
    }
    yield* FlutterBluePlus.adapterState.map(
      (s) => switch (s) {
        BluetoothAdapterState.on => BleAdapter.on,
        BluetoothAdapterState.off || BluetoothAdapterState.turningOff || BluetoothAdapterState.turningOn => BleAdapter.off,
        BluetoothAdapterState.unauthorized => BleAdapter.unauthorized,
        BluetoothAdapterState.unavailable => BleAdapter.unsupported,
        BluetoothAdapterState.unknown => BleAdapter.unknown,
      },
    );
  }

  @override
  Stream<List<FoundSensor>> scan({Duration timeout = const Duration(seconds: 15)}) {
    late StreamController<List<FoundSensor>> c;
    StreamSubscription<List<ScanResult>>? sub;
    StreamSubscription<bool>? scanning;
    c = StreamController<List<FoundSensor>>(
      onListen: () async {
        sub = FlutterBluePlus.onScanResults.listen(
          (results) => c.add([
            // Hệ điều hành đã lọc theo withServices = Heart Rate Service; khi connect còn kiểm tra lại characteristic 0x2A37.
            for (final r in results) FoundSensor(remoteId: r.device.remoteId.str, advertisedName: r.advertisementData.advName, rssi: r.rssi),
          ]),
          onError: c.addError,
        );
        try {
          await FlutterBluePlus.startScan(withServices: [_service], timeout: timeout);
        } catch (e) {
          c.addError(e);
        }
        // startScan trả về ngay; đóng stream khi hết thời gian quét.
        var started = false;
        scanning = FlutterBluePlus.isScanning.listen((s) {
          if (s) started = true;
          if (started && !s && !c.isClosed) c.close();
        });
        if (!FlutterBluePlus.isScanningNow && !c.isClosed) await c.close();
      },
      onCancel: () async {
        await sub?.cancel();
        await scanning?.cancel();
        await FlutterBluePlus.stopScan();
      },
    );
    return c.stream;
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<HeartRateConnection> connect(String remoteId, {Duration timeout = const Duration(seconds: 15)}) async {
    final device = BluetoothDevice.fromId(remoteId);
    try {
      await device.connect(timeout: timeout, mtu: null);
    } on TimeoutException {
      throw HeartRateConnectException('timeout');
    } on FlutterBluePlusException catch (e) {
      final timeoutLike = (e.description ?? '').toLowerCase().contains('timeout') || e.code == FbpErrorCode.timeout.index;
      throw HeartRateConnectException(timeoutLike ? 'timeout' : 'failed', e.description);
    } catch (e) {
      throw HeartRateConnectException('failed', e.toString());
    }
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? ch;
      for (final s in services) {
        if (s.serviceUuid != _service) continue;
        for (final c in s.characteristics) {
          if (c.characteristicUuid == _measurement) ch = c;
        }
      }
      if (ch == null) {
        await device.disconnect();
        throw HeartRateConnectException('noHeartRateService');
      }
      await ch.setNotifyValue(true);
      return _FbpConnection(device, ch);
    } on HeartRateConnectException {
      rethrow;
    } catch (e) {
      await device.disconnect();
      throw HeartRateConnectException('failed', e.toString());
    }
  }
}

class _FbpConnection implements HeartRateConnection {
  _FbpConnection(this._device, BluetoothCharacteristic ch) {
    _valueSub = ch.onValueReceived.listen((bytes) {
      final m = parseHeartRateMeasurement(bytes);
      if (m != null) _measurements.add(m);
    });
    _device.cancelWhenDisconnected(_valueSub);
    _stateSub = _device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_manual && !_lost.isCompleted) _lost.complete();
    });
  }

  final BluetoothDevice _device;
  final _measurements = StreamController<HeartRateMeasurement>.broadcast();
  final _lost = Completer<void>();
  late final StreamSubscription<List<int>> _valueSub;
  late final StreamSubscription<BluetoothConnectionState> _stateSub;
  bool _manual = false;

  @override
  String get remoteId => _device.remoteId.str;

  @override
  Stream<HeartRateMeasurement> get measurements => _measurements.stream;

  @override
  Future<void> get lost => _lost.future;

  @override
  Future<void> disconnect() async {
    _manual = true;
    await _valueSub.cancel();
    await _stateSub.cancel();
    await _measurements.close();
    try {
      await _device.disconnect();
    } catch (_) {}
  }
}
