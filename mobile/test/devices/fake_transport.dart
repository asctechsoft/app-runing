import 'dart:async';

import 'package:stride/services/application/heart_rate_parser.dart';
import 'package:stride/services/application/heart_rate_transport.dart';

import '../run/run_harness.dart' show hangingOnCancel;

class FakeConnection implements HeartRateConnection {
  FakeConnection(this.remoteId, {this.hangOnCancel = false});

  @override
  final String remoteId;
  final _m = StreamController<HeartRateMeasurement>.broadcast();
  final _lost = Completer<void>();
  bool disconnected = false;

  /// true → `cancel()` của stream đo không bao giờ hoàn thành (kênh BLE không trả lời).
  final bool hangOnCancel;

  @override
  Stream<HeartRateMeasurement> get measurements => hangOnCancel ? hangingOnCancel(_m.stream) : _m.stream;
  @override
  Future<void> get lost => _lost.future;

  void emit(int bpm, {SensorContact contact = SensorContact.detected}) => _m.add(HeartRateMeasurement(bpm: bpm, contact: contact));

  void loseSignal() {
    if (!_lost.isCompleted) _lost.complete();
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    await _m.close();
  }
}

class FakeTransport implements HeartRateTransport {
  BleAdapter adapter = BleAdapter.on;
  List<FoundSensor> scanResult = const [];
  final connectCalls = <String>[];
  final connections = <FakeConnection>[];

  /// Nếu đặt, connect ném lỗi này.
  HeartRateConnectException? failWith;

  /// Kết nối mới tạo có stream đo bị treo khi hủy.
  bool hangOnCancel = false;

  @override
  Stream<BleAdapter> adapterState() => Stream.value(adapter);

  @override
  Stream<List<FoundSensor>> scan({Duration timeout = const Duration(seconds: 15)}) => Stream.value(scanResult);

  @override
  Future<void> stopScan() async {}

  @override
  Future<HeartRateConnection> connect(String remoteId, {Duration timeout = const Duration(seconds: 15)}) async {
    connectCalls.add(remoteId);
    final f = failWith;
    if (f != null) throw f;
    final c = FakeConnection(remoteId, hangOnCancel: hangOnCancel);
    connections.add(c);
    return c;
  }
}
