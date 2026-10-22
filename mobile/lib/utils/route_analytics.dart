import 'package:go_router/go_router.dart';

import 'analytics.dart';

/// Ghi screen_view cho mọi lần điều hướng từ MỘT chỗ (thay vì gắn tay từng màn), kể cả chuyển tab trong shell.
/// Dùng mẫu đường dẫn (`/home/activity/:id`), không dùng đường dẫn thật → không rò id hoạt động/câu lạc bộ lên analytics.
class RouteAnalytics {
  RouteAnalytics._();

  static String? _last;

  static void attach(GoRouter router) {
    void onChange() {
      final config = router.routerDelegate.currentConfiguration;
      if (config.isEmpty) return;
      final screen = config.fullPath;
      if (screen.isEmpty || screen == _last) return;
      _last = screen;
      Analytics.screenView(screen);
    }

    router.routerDelegate.addListener(onChange);
  }
}
