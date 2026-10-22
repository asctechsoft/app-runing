/// Khóa SharedPreferences dùng chung với base (asc_common). Tập trung một chỗ — không gõ chuỗi rải rác.
class PrefConst {
  PrefConst._();

  /// Ngôn ngữ đã chọn, dạng `vi_VN` (asc_common `AscLocale` ghi/đọc).
  static const String language = 'stride_language';

  /// true khi người dùng chọn "theo hệ thống": mỗi lần mở lại dò ngôn ngữ máy thay vì coi giá trị đã lưu là ghim.
  static const String followSystemLanguage = 'stride_follow_system_language';
}
