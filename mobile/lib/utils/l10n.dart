import 'package:get/get.dart' as g;

/// Chuỗi đa ngôn ngữ từ XML (`lib/xml_strings/values*/strings.xml`, nạp bởi asc_common `AscLocale`).
///
/// ```dart
/// Text('home_title'.tr)
/// Text('run_pace_value'.trArgs([pace]))   // XML: <string name="run_pace_value">%1$s /km</string>
/// ```
/// Không import `package:get/get.dart` trực tiếp ở màn hình/logic — dùng file này để không kéo cả GetX vào namespace.
/// Thiếu key thì trả về chính key (dễ thấy khi test bằng mắt).
extension L10n on String {
  String get tr => g.Trans(this).tr;

  /// Thay `%1$s`, `%2$s`... trong chuỗi XML bằng [args] theo thứ tự (asc_common đổi chúng thành `@args1`, `@args2`...).
  String trArgs(List<Object?> args) => g.Trans(this).trParams({for (var i = 0; i < args.length; i++) 'args${i + 1}': '${args[i]}'});
}
