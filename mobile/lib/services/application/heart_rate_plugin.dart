import 'dart:async';

import '../../controller/run_plugins.dart';
import '../../utils/clock.dart';
import '../../models/data_models/activity.dart';
import '../../repository/device_repository.dart';
import 'heart_rate_parser.dart';
import 'heart_rate_transport.dart';

enum HeartRatePhase {
  /// Không có cảm biến đã ghép (hoặc không có phiên) → không hiển thị nhịp tim.
  unavailable,
  connecting,
  connected,

  /// Mất cảm biến giữa phiên: phiên trên điện thoại vẫn ghi, plugin thử kết nối lại.
  lost,
}

class HeartRateStatus {
  const HeartRateStatus({this.phase = HeartRatePhase.unavailable, this.deviceName, this.lastBpm, this.lastAt});

  final HeartRatePhase phase;
  final String? deviceName;

  /// bpm cuối cùng đo thật; null = chưa có (hiển thị "—", không suy từ pace).
  final int? lastBpm;
  final int? lastAt;

  HeartRateStatus copyWith({HeartRatePhase? phase, String? deviceName, int? lastBpm, int? lastAt}) =>
      HeartRateStatus(phase: phase ?? this.phase, deviceName: deviceName ?? this.deviceName, lastBpm: lastBpm ?? this.lastBpm, lastAt: lastAt ?? this.lastAt);
}

/// L03: ghi nhịp tim từ cảm biến BLE vào heart_rate_samples trong phiên chạy.
/// - Chỉ dùng thiết bị chưa revoke, kết nối gần nhất.
/// - Mẫu có timestamp thật; mất kết nối → khoảng trống được giữ nguyên (không nội suy).
/// - Không bao giờ tính nhịp tim từ pace.
class HeartRatePlugin extends RunPlugin {
  HeartRatePlugin({
    required this.repository,
    required this.transport,
    required this.clock,
    required this.onStatus,
    this.connectTimeout = const Duration(seconds: 15),
    this.reconnectDelay = const Duration(seconds: 10),
  });

  final DeviceRepository repository;
  final HeartRateTransport transport;
  final Clock clock;
  final void Function(HeartRateStatus) onStatus;
  final Duration connectTimeout;
  final Duration reconnectDelay;

  @override
  String get id => 'heart_rate';

  String? _activityId;
  PairedDevice? _device;
  HeartRateConnection? _conn;
  StreamSubscription<HeartRateMeasurement>? _sub;
  StreamSubscription<String>? _devicesSub;
  Timer? _reconnect;
  bool _active = false;
  var _status = const HeartRateStatus();

  HeartRateStatus get status => _status;

  void _emit(HeartRateStatus s) {
    _status = s;
    onStatus(s);
  }

  @override
  Future<void> onSessionStart(Activity activity) async {
    await _teardown();
    _activityId = activity.id;
    _active = true;
    _device = await repository.mostRecentActive(activity.ownerId);
    if (_device == null) {
      _emit(const HeartRateStatus());
      return;
    }
    // Người dùng "Forget" thiết bị giữa phiên → ngừng nhập ngay.
    _devicesSub = repository.changes.listen((_) => _checkRevoked());
    await _connect();
  }

  Future<void> _checkRevoked() async {
    final d = _device;
    if (d == null || !_active) return;
    final fresh = await repository.byId(d.id);
    if (fresh == null || fresh.revoked) {
      _device = null;
      await _closeConnection();
      _reconnect?.cancel();
      _emit(const HeartRateStatus());
    }
  }

  Future<void> _connect() async {
    final d = _device;
    if (!_active || d == null) return;
    final fresh = await repository.byId(d.id);
    if (fresh == null || fresh.revoked) {
      _device = null;
      _emit(const HeartRateStatus());
      return;
    }
    _emit(_status.copyWith(phase: _status.lastBpm == null ? HeartRatePhase.connecting : HeartRatePhase.lost, deviceName: d.name));
    try {
      final conn = await transport.connect(d.remoteId, timeout: connectTimeout);
      if (!_active || _device == null) {
        await conn.disconnect();
        return;
      }
      _conn = conn;
      await repository.markConnected(d.id);
      _emit(_status.copyWith(phase: HeartRatePhase.connected, deviceName: d.name));
      _sub = conn.measurements.listen((m) => _onMeasurement(d, conn, m));
      unawaited(conn.lost.then((_) => _onLost(conn)));
    } catch (_) {
      if (!_active) return;
      _emit(_status.copyWith(phase: HeartRatePhase.lost, deviceName: d.name));
      _scheduleReconnect();
    }
  }

  Future<void> _onMeasurement(PairedDevice d, HeartRateConnection conn, HeartRateMeasurement m) async {
    final activityId = _activityId;
    if (!_active || activityId == null || _device?.id != d.id || !identical(conn, _conn)) return;
    // Không tiếp xúc da / bpm 0 → bỏ, để lại khoảng trống thay vì ghi số sai.
    if (!m.isReliable) return;
    final t = clock.nowMs();
    await repository.addSample(HeartRateSample(activityId: activityId, t: t, bpm: m.bpm, deviceId: d.id));
    // Kết nối đã mất trong lúc ghi → không ghi đè trạng thái "lost".
    if (!_active || !identical(conn, _conn)) return;
    _emit(_status.copyWith(phase: HeartRatePhase.connected, lastBpm: m.bpm, lastAt: t, deviceName: d.name));
  }

  Future<void> _onLost(HeartRateConnection conn) async {
    if (!_active || !identical(conn, _conn)) return;
    await _sub?.cancel();
    _sub = null;
    _conn = null;
    _emit(_status.copyWith(phase: HeartRatePhase.lost));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    if (!_active || _device == null) return;
    _reconnect = Timer(reconnectDelay, () => _connect());
  }

  Future<void> _closeConnection() async {
    await _sub?.cancel();
    _sub = null;
    final c = _conn;
    _conn = null;
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _teardown() async {
    _active = false;
    _reconnect?.cancel();
    _reconnect = null;
    await _devicesSub?.cancel();
    _devicesSub = null;
    await _closeConnection();
    _activityId = null;
    _device = null;
  }

  @override
  Future<void> onSessionEnd(Activity activity, {required bool discarded}) async {
    await _teardown();
    _emit(const HeartRateStatus());
  }
}
