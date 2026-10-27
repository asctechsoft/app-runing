import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// T05: một cổng duy nhất cho haptic, theo bảng sự kiện ở `docs/checklist-con-lai.md` mục 8.1. Màn hình/controller không gọi
/// `HapticFeedback` trực tiếp. Haptic không bao giờ là kênh báo duy nhất — luôn có chữ/trạng thái tương ứng.
/// Lỗi plugin (máy không có motor, test không có platform channel) bị nuốt: rung hỏng không được làm hỏng thao tác.
abstract final class StrideHaptics {
  /// Tắt toàn bộ rung (T06: cài đặt rung của người dùng; hệ điều hành tự bỏ qua khi người dùng tắt rung hệ thống).
  static bool enabled = true;

  /// Ghi lại loại haptic trong test (không cần platform channel).
  @visibleForTesting
  static void Function(String kind)? debugSink;

  /// Bấm tab, chip, segmented, công tắc, chọn dòng; nhịp đếm ngược; bắt đầu nhấn giữ.
  static void selection() => _run('selection', HapticFeedback.selectionClick);

  /// Bắt đầu chạy / tiếp tục; lưu thành công.
  static void light() => _run('light', HapticFeedback.lightImpact);

  /// Tạm dừng; đạt mốc/mục tiêu/kỷ lục; chuyển phase interval.
  static void medium() => _run('medium', HapticFeedback.mediumImpact);

  /// Hoàn thành nhấn giữ; bắt đầu sau đếm ngược; lỗi/bị chặn (kèm thông báo chữ).
  static void heavy() => _run('heavy', HapticFeedback.heavyImpact);

  static void _run(String kind, Future<void> Function() fn) {
    if (!enabled) return;
    debugSink?.call(kind);
    try {
      unawaited(fn().catchError((Object _) {}));
    } catch (_) {}
  }
}
