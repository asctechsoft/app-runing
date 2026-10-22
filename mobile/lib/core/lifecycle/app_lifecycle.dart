import 'package:flutter/widgets.dart';

import '../analytics/analytics.dart';

/// Vòng đời app ở MỘT chỗ: foreground/background, thời điểm resume, và các hook cho tính năng cần phản ứng
/// (quyền cấp lại trong Settings, đồng bộ, nhắc...). Các tính năng đăng ký hook thay vì tự gắn `WidgetsBindingObserver`.
///
/// Luồng chuẩn: `main()` → bootstrap (Firebase/base/locale) → `StrideApp` → `StartupScreen` (chỉ đọc cục bộ) → Home;
/// từ đó `AppLifecycle` theo dõi resume/pause cho tới khi tiến trình bị hệ điều hành thu hồi.
class AppLifecycle with WidgetsBindingObserver {
  AppLifecycle({this.onResumed = const [], this.onPaused = const [], this.logAnalytics = true});

  /// Chạy mỗi khi app ở trạng thái `resumed` (quay lại foreground, hoặc trở về sau hộp thoại hệ thống).
  final List<VoidCallback> onResumed;

  /// Chạy khi app xuống background (đã `paused`, không còn nhận input).
  final List<VoidCallback> onPaused;

  final bool logAnalytics;

  final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);

  /// Thời điểm resume gần nhất; null nếu chưa từng resume sau lần mở lạnh.
  DateTime? lastResumedAt;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    isForeground.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!isForeground.value) {
          isForeground.value = true;
          lastResumedAt = DateTime.now();
          if (logAnalytics) Analytics.appForeground();
        }
        // Hook chạy ở MỌI lần resumed, kể cả sau hộp thoại quyền/Settings (chỉ qua `inactive`, không qua `paused`).
        for (final cb in onResumed) {
          cb();
        }
      case AppLifecycleState.paused:
        if (!isForeground.value) return;
        isForeground.value = false;
        if (logAnalytics) Analytics.appBackground();
        for (final cb in onPaused) {
          cb();
        }
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.detached:
        break;
    }
  }
}
