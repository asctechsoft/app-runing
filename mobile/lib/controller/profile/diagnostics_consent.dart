import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/pref_const.dart';
import '../../utils/analytics.dart';
import '../providers.dart';

/// X11: đồng ý chia sẻ dữ liệu sử dụng ẩn danh (Analytics) và báo lỗi (Crashlytics). Theo thiết bị.
/// Mặc định: bật (giữ hành vi hiện tại) — Product/pháp chế chốt có hỏi đồng ý trước ở EEA/UK hay không.
/// Tắt: analytics dừng ngay (cổng `Analytics`); Crashlytics đọc cờ lúc khởi động nên áp dụng từ lần mở app sau.
class DiagnosticsConsent extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(PrefConst.diagnosticsConsent) ?? true;

  Future<void> set(bool enabled) async {
    Analytics.collectionEnabled = enabled;
    state = enabled;
    await ref.read(sharedPrefsProvider).setBool(PrefConst.diagnosticsConsent, enabled);
  }
}

final diagnosticsConsentProvider = NotifierProvider<DiagnosticsConsent, bool>(DiagnosticsConsent.new);
