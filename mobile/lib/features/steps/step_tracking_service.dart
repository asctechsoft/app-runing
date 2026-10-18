import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pedometer/pedometer.dart';

import '../../core/logging/logger.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';

/// Trạng thái adapter cảm biến bước (F01).
enum StepTrackingStatus {
  /// Chưa bắt đầu (chưa có quyền hoặc chưa gọi start).
  idle,

  /// Đang nghe counter.
  running,

  /// Máy không có cảm biến hoặc plugin lỗi.
  unavailable,
}

/// Một giá trị counter tích lũy (Android: tổng từ lúc boot; iOS: tổng từ lúc bắt đầu nghe).
typedef StepCounterReading = ({int counter, int atMs});

/// Nguồn counter có thể thay trong test.
typedef StepCounterStreamFactory = Stream<StepCounterReading> Function();

Stream<StepCounterReading> pedometerCounterStream() => Pedometer.stepCountStream.map((e) => (counter: e.steps, atMs: e.timeStamp.millisecondsSinceEpoch));

/// Nghe counter từ sensor và đẩy vào StepRepository.ingestCounter — repository xử lý baseline/offset/reboot,
/// nên tổng counter kể từ boot không bao giờ bị cộng thành bước hôm nay.
/// Chỉ chạy khi quyền motion đã cấp; không đọc sensor trực tiếp từ UI.
class StepTrackingService {
  StepTrackingService(this._ref, {StepCounterStreamFactory? streamFactory}) : _streamFactory = streamFactory ?? pedometerCounterStream;

  final Ref _ref;
  final StepCounterStreamFactory _streamFactory;
  StreamSubscription<StepCounterReading>? _sub;
  final status = ValueNotifier<StepTrackingStatus>(StepTrackingStatus.idle);

  /// Thời điểm nhận giá trị counter gần nhất (UTC ms) — để hiển thị "last checked".
  int? lastReadingAt;

  bool get isRunning => _sub != null;

  /// Bắt đầu nếu đã có quyền motion. Gọi lặp an toàn (idempotent). Trả trạng thái sau khi gọi.
  Future<StepTrackingStatus> start() async {
    if (_sub != null) return status.value;
    if (status.value == StepTrackingStatus.unavailable) return status.value;
    final perm = await _ref.read(permissionsProvider).status(PermKind.motion);
    if (perm != PermStatus.granted && perm != PermStatus.limited) {
      status.value = StepTrackingStatus.idle;
      return status.value;
    }
    try {
      _sub = _streamFactory().listen(_onReading, onError: _onError, cancelOnError: true);
      status.value = StepTrackingStatus.running;
    } catch (e, st) {
      _onError(e, st);
    }
    return status.value;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (status.value == StepTrackingStatus.running) status.value = StepTrackingStatus.idle;
  }

  /// Chuỗi xử lý tuần tự: ingestCounter đọc-rồi-ghi trạng thái counter, hai sự kiện chạy song song
  /// sẽ cùng thấy baseline cũ và làm mất delta.
  Future<void> _queue = Future.value();

  void _onReading(StepCounterReading r) {
    _queue = _queue.then((_) => _ingest(r));
  }

  Future<void> _ingest(StepCounterReading r) async {
    lastReadingAt = _ref.read(clockProvider).nowMs();
    final owner = _ref.read(ownerProvider).ownerId;
    try {
      await _ref.read(stepRepositoryProvider).ingestCounter(ownerId: owner, counter: r.counter, atMs: r.atMs);
    } catch (e, st) {
      StrideLog.e('steps', e, st);
    }
  }

  void _onError(Object e, [StackTrace? st]) {
    // Plugin báo lỗi khi máy không có TYPE_STEP_COUNTER / CMPedometer → không hiển thị 0 giả.
    StrideLog.e('steps', e, st);
    _sub = null;
    status.value = StepTrackingStatus.unavailable;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    status.dispose();
  }
}

final stepTrackingServiceProvider = Provider<StepTrackingService>((ref) {
  final s = StepTrackingService(ref);
  ref.onDispose(s.dispose);
  return s;
});

/// Trạng thái adapter dưới dạng stream để UI watch.
final stepTrackingStatusProvider = StreamProvider<StepTrackingStatus>((ref) {
  final s = ref.watch(stepTrackingServiceProvider);
  final c = StreamController<StepTrackingStatus>();
  void emit() => c.add(s.status.value);
  emit();
  s.status.addListener(emit);
  ref.onDispose(() {
    s.status.removeListener(emit);
    c.close();
  });
  return c.stream;
});
