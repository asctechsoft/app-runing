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

  /// Tên Firebase dành riêng (gửi sẽ bị từ chối: "Event name is reserved"). Đừng đặt event trùng — vd. `app_background` từng dính lỗi này.
  static const Set<String> _reservedNames = {
    'app_background',
    'app_clear_data',
    'app_exception',
    'app_remove',
    'app_store_refund',
    'app_store_subscription_cancel',
    'app_store_subscription_convert',
    'app_store_subscription_renew',
    'app_update',
    'dynamic_link_app_open',
    'dynamic_link_first_open',
    'error',
    'first_open',
    'in_app_purchase',
    'notification_dismiss',
    'notification_foreground',
    'notification_open',
    'notification_receive',
    'os_update',
    'session_start',
    'user_engagement',
  };

  static AnalyticsEventSink _sink = _sendToFirebase;

  /// X11: người dùng tắt "chia sẻ dữ liệu sử dụng" → không gửi event nào (đặt lúc khởi động và khi đổi trong Quyền riêng tư).
  static bool collectionEnabled = true;

  @visibleForTesting
  static set sink(AnalyticsEventSink sink) => _sink = sink;

  @visibleForTesting
  static void resetSink() => _sink = _sendToFirebase;

  static bool isValidEventName(String name) => _validEventName.hasMatch(name) && !_reservedPrefixes.any(name.startsWith) && !_reservedNames.contains(name);

  static void _log(String name, [Map<String, Object>? params]) {
    assert(isValidEventName(name), 'Invalid Firebase Analytics event name: $name');
    assert(params == null || params.values.every((v) => v is String), 'Analytics params must be String: $name -> $params');
    if (!isValidEventName(name) || !collectionEnabled) return;
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
  static void appForeground() => _log('stride_foreground');
  static void appBackground() => _log('stride_background');

  /// Xem màn hình. [screen] là mẫu đường dẫn (`/home/activity/:id`), không bao giờ là đường dẫn có id thật.
  static void screenView(String screen) => _log('screen_view', {'firebase_screen': screen});

  /// Đã gọi popup đánh giá của hệ điều hành (X23) — không biết popup có thực sự hiện hay không.
  static void reviewPrompt() => _log('review_prompt');

  /// Màn chọn ngôn ngữ (L23). [source]: `first_run` | `settings`.
  static void languageScreenView({required String source}) => _log('language_screen_view', {'source': source});

  /// Chọn ngôn ngữ (L23): [code] dạng `vi_VN` hoặc `system`; [source]: `first_run` | `settings` | `system_default`. Không có id/PII.
  static void languageSelect({required String code, required String source}) => _log('language_select', {'code': code, 'source': source});

  // ---- Tính năng nhóm (TM76). Không có id club/thử thách/người dùng — chỉ loại và nguồn.

  /// Tạo club thành công. [visibility]: `public` | `private`.
  static void clubCreate({required String visibility}) => _log('club_create', {'visibility': visibility});

  /// Mở bảng chia sẻ mã mời club (TM03).
  static void clubInviteShare() => _log('club_invite_share');

  /// Vào club. [via]: `public` (vào ngay) | `request` (gửi yêu cầu, chờ duyệt) | `invite_code`.
  static void clubJoin({required String via}) => _log('club_join', {'via': via});

  /// Tham gia thử thách. [metric]: `distance` | `count` | `time`.
  static void challengeJoin({required String metric}) => _log('challenge_join', {'metric': metric});

  /// Mở bảng xếp hạng thử thách (TM30).
  static void leaderboardView() => _log('leaderboard_view');

  /// Nhận huy hiệu (TM40). [kind]: tên loại (`first5k`, `streak7`, `challenge`…) — không id thử thách.
  static void badgeEarned({required String kind}) => _log('badge_earned', {'kind': kind});

  /// Đạt mốc chuỗi cá nhân (TM20). [days]: một trong [streakMilestones].
  static void streakMilestone({required int days}) => _log('streak_milestone', {'days': '$days'});

  /// Mốc chuỗi được ghi analytics (ít mốc để không thành event theo ngày).
  static const List<int> streakMilestones = [3, 7, 14, 30, 60, 100, 365];

  /// Mốc vừa vượt qua khi chuỗi tăng từ [from] lên [to] (null nếu không có).
  static int? crossedStreakMilestone(int from, int to) => streakMilestones.where((m) => from < m && to >= m).lastOrNull;
}
