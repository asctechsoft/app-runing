import 'dart:async';

import 'package:dsp_base/dsp_base.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

typedef AnalyticsEventSink = void Function(String name, Map<String, Object>? parameters);

/// Cổng analytics duy nhất của STRIDE: màn hình và controller không gọi Firebase Analytics trực tiếp.
/// Một chỗ để (1) kiểm tra tên event (Firebase âm thầm bỏ tên sai), (2) chỉ nhận tham số chuỗi (GA4 custom dimension
/// bỏ qua số), (3) đổi sink khi test mà không cần platform channel, (4) là no-op khi Firebase chưa sẵn sàng (offline-first).
///
/// Quyền riêng tư: KHÔNG đưa tọa độ, id hoạt động, email hay nội dung người dùng vào tên/tham số event.
class Analytics {
  Analytics._();

  /// Firebase nhận 1–40 ký tự: bắt đầu bằng chữ, sau đó chữ/số/gạch dưới.
  static final RegExp _validEventName = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$');
  static const List<String> _reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  static AnalyticsEventSink _sink = _sendToFirebase;

  @visibleForTesting
  static set sink(AnalyticsEventSink sink) => _sink = sink;

  @visibleForTesting
  static void resetSink() => _sink = _sendToFirebase;

  static bool isValidEventName(String name) => _validEventName.hasMatch(name) && !_reservedPrefixes.any(name.startsWith);

  static void _log(String name, [Map<String, Object>? params]) {
    assert(isValidEventName(name), 'Invalid Firebase Analytics event name: $name');
    assert(params == null || params.values.every((v) => v is String), 'Analytics params must be String: $name -> $params');
    if (!isValidEventName(name)) return;
    _sink(name, params);
  }

  // Trong test/bản không có Firebase, `Firebase.apps` có thể ném (không có platform channel) — coi như chưa sẵn sàng.
  static bool get _firebaseUp {
    try {
      return DspFirebaseService.isCoreReady && Get.isRegistered<DspAnalytics>();
    } catch (_) {
      return false;
    }
  }

  static void _sendToFirebase(String name, Map<String, Object>? params) {
    if (!_firebaseUp) return;
    unawaited(DspAnalytics.to.log(DspAnalyticsEvent(name, params)).catchError((Object e) => debugPrint('Analytics.log($name) failed: $e')));
  }

  /// Mở app lạnh (cold start).
  static void appOpen({required bool firstOpen}) => _log('app_open', {'first_open': '$firstOpen'});

  /// App quay lại foreground / đi xuống background (vòng đời — xem `AppLifecycle`).
  static void appForeground() => _log('app_foreground');
  static void appBackground() => _log('app_background');

  /// Xem màn hình. [screen] là mẫu đường dẫn (`/home/activity/:id`), không bao giờ là đường dẫn có id thật.
  static void screenView(String screen) => _log('screen_view', {'firebase_screen': screen});
}
