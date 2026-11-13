import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// Cầu nối tới thông báo đang chạy ở native Android (`OngoingService`, `OngoingNotifications`): số bước hôm nay luôn hiện
/// và thẻ buổi chạy đang ghi. Chỉ vẽ lại khi nội dung đổi; nền tảng khác Android là no-op. Lỗi native chỉ ghi log —
/// thông báo là tiện ích, không được làm hỏng đếm bước hay ghi chạy.
class OngoingNotificationService {
  OngoingNotificationService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('stride/ongoing');

  final MethodChannel _channel;

  bool _stepsOn = false;
  Map<String, Object?>? _lastSteps;
  Map<String, Object?>? _lastRun;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Bật (hoặc cập nhật) thông báo số bước. [progress] 0..100, null = chưa đặt mục tiêu.
  Future<void> showSteps({required String channel, required String title, required String text, int? progress}) async {
    if (!_supported) return;
    final args = {'channel': channel, 'title': title, 'text': text, 'progress': progress};
    if (_stepsOn && mapEquals(_lastSteps, args)) return;
    final method = _stepsOn ? 'updateSteps' : 'startSteps';
    _lastSteps = args;
    _stepsOn = true;
    await _invoke(method, args);
  }

  Future<void> hideSteps() async {
    if (!_supported || !_stepsOn) return;
    _stepsOn = false;
    _lastSteps = null;
    await _invoke('stopSteps');
  }

  /// Thẻ buổi chạy đang ghi. [movingMs]: thời gian di chuyển; [running] false khi tạm dừng (đồng hồ dừng).
  Future<void> showRun({
    required String channel,
    required String title,
    required String subtitle,
    required String timeLabel,
    required String distanceLabel,
    required String distance,
    required int movingMs,
    required bool running,
  }) async {
    if (!_supported) return;
    final args = {
      'channel': channel,
      'title': title,
      'subtitle': subtitle,
      'timeLabel': timeLabel,
      'distanceLabel': distanceLabel,
      'distance': distance,
      'movingMs': movingMs,
      'running': running,
    };
    // Đồng hồ chạy tự động: chỉ gửi lại khi chữ/trạng thái đổi, không gửi vì movingMs tăng.
    final sig = {...args}..remove('movingMs');
    if (_lastRun != null && mapEquals(_lastRun, sig)) return;
    _lastRun = sig;
    await _invoke('showRun', args);
  }

  Future<void> hideRun() async {
    if (!_supported || _lastRun == null) return;
    _lastRun = null;
    await _invoke('hideRun');
  }

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e, st) {
      StrideLog.e('ongoing', e, st);
    }
  }
}
