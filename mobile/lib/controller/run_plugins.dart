import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/data_models/activity.dart';

/// Điểm móc để module mở rộng (live sharing M07, nhịp tim L03) nghe vòng đời phiên chạy
/// mà engine không phụ thuộc trực tiếp vào chúng. Plugin không được làm hỏng phiên: engine bắt mọi lỗi.
abstract class RunPlugin {
  String get id;

  Future<void> onSessionStart(Activity activity) async {}

  /// Điểm GPS đã được chấp nhận (accepted).
  Future<void> onPoint(Activity activity, TrackPoint point) async {}

  Future<void> onPause(Activity activity) async {}
  Future<void> onResume(Activity activity) async {}

  /// Finish hoặc discard — plugin phải dừng mọi chia sẻ/thu thập.
  Future<void> onSessionEnd(Activity activity, {required bool discarded}) async {}
}

/// Danh sách plugin đang bật. Được override/ghép ở tầng app khi feature flag bật.
final runPluginsProvider = Provider<List<RunPlugin>>((ref) => const []);
