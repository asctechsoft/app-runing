/// Khóa SharedPreferences dùng chung với base (asc_common). Tập trung một chỗ — không gõ chuỗi rải rác.
class PrefConst {
  PrefConst._();

  /// Ngôn ngữ đã chọn, dạng `vi_VN` (asc_common `AscLocale` ghi/đọc).
  static const String language = 'stride_language';

  /// true khi người dùng chọn "theo hệ thống": mỗi lần mở lại dò ngôn ngữ máy thay vì coi giá trị đã lưu là ghim.
  static const String followSystemLanguage = 'stride_follow_system_language';

  /// L19: đã bấm "Tiếp tục" ở màn chọn ngôn ngữ lần đầu. Theo THIẾT BỊ (không theo tài khoản/khách): đăng xuất không hỏi lại.
  static const String languageChosen = 'stride_language_chosen';

  /// T06: rung phản hồi bật/tắt (theo thiết bị, mặc định bật).
  static const String hapticsEnabled = 'stride_haptics_enabled';

  /// X11: đồng ý gửi analytics ẩn danh + báo lỗi (theo thiết bị, mặc định bật).
  static const String diagnosticsConsent = 'stride_diagnostics_consent';

  /// X23: số buổi đã lưu (đếm cho lời mời đánh giá) và lần hỏi gần nhất (ms).
  static const String reviewSavedRuns = 'stride_review_saved_runs';
  static const String reviewLastAskedMs = 'stride_review_last_asked_ms';
}
