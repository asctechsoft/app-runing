import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/run_plugins.dart';
import '../../core/time/clock.dart';
import '../../domain/models/activity.dart';
import 'live_share_models.dart';
import 'live_share_repository.dart';

/// M07: chia sẻ vị trí trực tiếp cho người được chọn trong đúng một phiên chạy.
/// - Chỉ bắt đầu khi cấu hình đã được đồng ý (consent) trước phiên; cấu hình bị xóa ngay khi phiên bắt đầu → mặc định tắt cho run sau.
/// - Gửi tối đa 1 điểm mỗi [publishInterval], chỉ điểm mới nhất; mất mạng → giữ điểm mới nhất, báo "interrupted".
/// - Kết thúc/huỷ phiên → dừng share. Không bao giờ chia sẻ công khai.
class LiveSharePlugin extends RunPlugin {
  LiveSharePlugin({
    required this.repository,
    required this.clock,
    required this.readConfig,
    required this.clearConfig,
    required this.onStatus,
    required this.isGuest,
    this.publishInterval = const Duration(seconds: 10),
  });

  final LiveShareRepository repository;
  final Clock clock;
  final LiveShareConfig Function() readConfig;
  final void Function() clearConfig;
  final void Function(LiveShareStatus) onStatus;
  final bool Function() isGuest;
  final Duration publishInterval;

  @override
  String get id => 'live_share';

  final _uuid = const Uuid();

  Activity? _activity;
  LiveShareConfig? _config;
  String? _shareId;
  int? _expiresAt;
  bool _running = false;
  bool _paused = false;
  bool _inFlight = false;
  bool _ended = false;

  /// Điểm mới nhất chưa gửi được (chỉ giữ một).
  TrackPoint? _pending;
  int? _lastAttemptMono;
  int? _lastSuccessAt;
  String? _startKey;
  var _status = const LiveShareStatus();

  /// Thế hệ phiên: kết quả mạng của phiên cũ không được ghi đè trạng thái phiên mới.
  int _gen = 0;
  final _ops = <Future<void>>{};

  /// Chờ mọi thao tác mạng đang chạy (dùng trong test). Engine không phải chờ mạng.
  Future<void> get idle async {
    while (_ops.isNotEmpty) {
      await Future.wait(_ops.toList());
    }
  }

  void _track(Future<void> f) {
    _ops.add(f);
    f.whenComplete(() => _ops.remove(f));
  }

  LiveShareStatus get status => _status;
  String? get shareId => _shareId;

  void _emit(LiveShareStatus s) {
    _status = s;
    onStatus(s);
  }

  void _reset() {
    _gen++;
    _activity = null;
    _config = null;
    _shareId = null;
    _expiresAt = null;
    _running = false;
    _paused = false;
    _inFlight = false;
    _ended = false;
    _pending = null;
    _lastAttemptMono = null;
    _lastSuccessAt = null;
    _startKey = null;
  }

  @override
  Future<void> onSessionStart(Activity activity) async {
    _reset();
    final config = readConfig();
    // Cấu hình chỉ dùng cho đúng một run.
    clearConfig();
    if (!config.ready || isGuest() || !repository.configured) {
      _emit(const LiveShareStatus());
      return;
    }
    _activity = activity;
    _config = config;
    _running = true;
    _startKey = _uuid.v4();
    _emit(const LiveShareStatus(phase: LiveSharePhase.starting));
    // Không bắt engine chờ mạng khi bắt đầu chạy.
    _track(_tryStart());
  }

  /// Bắt đầu share. Mạng lỗi → thử lại ở lần điểm kế tiếp (theo nhịp throttle).
  Future<bool> _tryStart() async {
    final a = _activity;
    final c = _config;
    final gen = _gen;
    if (a == null || c == null || !_running || _shareId != null) return _shareId != null;
    _lastAttemptMono = clock.monoMs();
    _inFlight = true;
    try {
      LiveShareSession s;
      try {
        s = await _start(a, c);
      } on LiveShareException catch (e) {
        if (e.kind != LiveShareErrorKind.activityNotFound) rethrow;
        // Server chưa có hoạt động đang ghi → tạo rồi thử lại một lần.
        await repository.ensureRemoteActivity(a);
        _startKey = _uuid.v4();
        s = await _start(a, c);
      }
      if (gen != _gen || !_running) {
        // Phiên đã kết thúc / người dùng dừng trong lúc chờ → dừng ngay share vừa tạo.
        await _safeStop(s.id);
        return false;
      }
      _shareId = s.id;
      _expiresAt = s.expiresAt;
      // Điểm đầu tiên sau khi start được gửi ngay, không chờ hết nhịp throttle.
      _lastAttemptMono = null;
      _emit(LiveShareStatus(phase: _paused ? LiveSharePhase.paused : LiveSharePhase.active, expiresAt: s.expiresAt, lastUpdateAt: _lastSuccessAt));
      return true;
    } on LiveShareException catch (e) {
      if (gen != _gen || !_running) return false;
      if (e.isNetwork) {
        _emit(
          LiveShareStatus(
            phase: LiveSharePhase.interrupted,
            message: 'Live sharing couldn\'t start — no connection. Trying again.',
            lastUpdateAt: _lastSuccessAt,
          ),
        );
      } else {
        _running = false;
        _pending = null;
        _emit(LiveShareStatus(phase: LiveSharePhase.failed, message: e.message));
      }
      return false;
    } finally {
      if (gen == _gen) _inFlight = false;
    }
  }

  Future<LiveShareSession> _start(Activity a, LiveShareConfig c) =>
      repository.start(activityId: a.id, viewerIds: [for (final v in c.viewers) v.userId], ttlMinutes: c.expiry.ttlMinutes, idempotencyKey: _startKey);

  bool get _expired => _expiresAt != null && clock.nowMs() >= _expiresAt!;

  @override
  Future<void> onPoint(Activity activity, TrackPoint point) async {
    if (!_running || _ended) return;
    _pending = point;
    final now = clock.monoMs();
    if (_inFlight) return;
    if (_lastAttemptMono != null && now - _lastAttemptMono! < publishInterval.inMilliseconds) return;
    _track(_flush());
  }

  Future<void> _flush({String? status}) async {
    if (!_running || _ended || _inFlight) return;
    if (_shareId == null) {
      final ok = await _tryStart();
      if (!ok) return;
    }
    if (_expired) {
      _markEnded('Live sharing has ended.');
      return;
    }
    final p = _pending;
    if (p == null) return;
    final gen = _gen;
    _inFlight = true;
    _lastAttemptMono = clock.monoMs();
    try {
      final s = await repository.publishPoint(_shareId!, LivePoint.fromTrack(p), status: status ?? (_paused ? 'paused' : 'active'));
      if (gen != _gen) return;
      if (identical(_pending, p)) _pending = null;
      _lastSuccessAt = s.lastUpdateAt ?? clock.nowMs();
      if (!_running) return;
      _emit(LiveShareStatus(phase: _paused ? LiveSharePhase.paused : LiveSharePhase.active, lastUpdateAt: _lastSuccessAt, expiresAt: _expiresAt));
    } on LiveShareException catch (e) {
      if (gen != _gen) return;
      if (e.kind == LiveShareErrorKind.ended) {
        _markEnded(e.message);
      } else if (_running) {
        // Giữ điểm mới nhất để gửi lần sau; không xếp hàng cả lịch sử.
        _emit(LiveShareStatus(phase: LiveSharePhase.interrupted, lastUpdateAt: _lastSuccessAt, expiresAt: _expiresAt, message: e.message));
      }
    } finally {
      if (gen == _gen) _inFlight = false;
    }
  }

  void _markEnded(String message) {
    _ended = true;
    _pending = null;
    _emit(LiveShareStatus(phase: LiveSharePhase.ended, lastUpdateAt: _lastSuccessAt, message: message));
  }

  @override
  Future<void> onPause(Activity activity) async {
    if (!_running) return;
    _paused = true;
    if (_shareId != null && !_ended) {
      _emit(LiveShareStatus(phase: LiveSharePhase.paused, lastUpdateAt: _lastSuccessAt, expiresAt: _expiresAt));
      // Gửi trạng thái tạm dừng kèm vị trí mới nhất (nếu có), bỏ qua throttle.
      if (_pending != null && !_inFlight) _track(_flush(status: 'paused'));
    }
  }

  @override
  Future<void> onResume(Activity activity) async {
    if (!_running) return;
    _paused = false;
    if (_shareId != null && !_ended) _emit(LiveShareStatus(phase: LiveSharePhase.active, lastUpdateAt: _lastSuccessAt, expiresAt: _expiresAt));
  }

  /// Dừng chia sẻ giữa phiên theo yêu cầu người dùng (phiên chạy vẫn tiếp tục).
  Future<void> stopSharing() async {
    final id = _shareId;
    final wasRunning = _running;
    _running = false;
    _pending = null;
    if (id != null) _track(_safeStop(id));
    if (wasRunning) _emit(LiveShareStatus(phase: LiveSharePhase.ended, lastUpdateAt: _lastSuccessAt, message: 'You stopped live sharing.'));
  }

  Future<void> _safeStop(String id) async {
    try {
      await repository.stop(id);
    } catch (_) {
      // Không dừng được qua mạng: server tự hết hạn theo TTL và dừng khi hoạt động được lưu/huỷ.
    }
  }

  @override
  Future<void> onSessionEnd(Activity activity, {required bool discarded}) async {
    final id = _shareId;
    final had = _running || id != null;
    _running = false;
    _pending = null;
    // Không bắt việc kết thúc run chờ mạng; nếu share đang được tạo, _tryStart tự dừng khi trả về.
    if (id != null) _track(_safeStop(id));
    _reset();
    _emit(
      had
          ? LiveShareStatus(phase: LiveSharePhase.ended, message: discarded ? 'Run discarded. Live sharing stopped.' : 'Run ended. Live sharing stopped.')
          : const LiveShareStatus(),
    );
  }
}
