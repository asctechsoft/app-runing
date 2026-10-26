import 'dart:async';

import 'package:dsp_base/dsp_base.dart';
import 'package:flutter/foundation.dart';

import '../../utils/logger.dart';
import '../../configs/app_figs.dart';

/// Khởi động phần dùng chung từ `dsp_base` theo đúng thứ tự: đăng ký service GetX → Firebase (core, App Check, Crashlytics)
/// → Remote Config (chạy nền). Không bao giờ ném lỗi; bước nào hỏng thì ghi log và bỏ qua để app vẫn chạy offline.
///
/// STRIDE chưa có quảng cáo, nên cố ý KHÔNG gọi `DspAdsController.start` (sẽ bật luồng đồng ý UMP/GDPR và khởi tạo AdMob).
/// Khi sản phẩm quyết định dùng quảng cáo: gọi `DspAdsController.to.start(...)` ở đây và khai ad unit id trong `lib/configs`.
class StrideBase {
  StrideBase._();

  /// Mặc định Remote Config — key do app sở hữu, base không hardcode key nào.
  static const Map<String, Object> remoteConfigDefaults = <String, Object>{};

  /// true khi Firebase core đã sẵn sàng (có `google-services.json` đúng package, đang chạy Android).
  static bool get firebaseReady => DspFirebaseService.isCoreReady;

  static Future<bool> start() async {
    DspBase.register();
    // iOS chưa có GoogleService-Info.plist, web không dùng Firebase: bỏ qua thay vì để initializeApp báo lỗi mỗi lần mở app.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final up = await DspFirebaseService.to
          .start(
            // App Check dùng provider debug ở bản debug — đăng ký token log ra trong Firebase console trước khi bật enforce.
            enableAppCheck: true,
            appCheckDebugProvider: kDebugMode || AppFigs.isShowTestOption,
          )
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (up) {
        // Không await: fetch Remote Config cần mạng, mà khởi động offline-first không được chờ mạng (F01).
        // Giá trị mặc định có sẵn ngay; bản fetch về sẽ đến sau và bump `DspRemoteConfigRepository.revision`.
        unawaited(
          DspRemoteConfigRepository.to.start(defaults: remoteConfigDefaults, minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1)),
        );
      }
      return up;
    } catch (e) {
      StrideLog.e('base', 'start failed: $e');
      return false;
    }
  }
}
