import 'package:get/get.dart' as g;
import 'package:intl/intl.dart';

import 'date_locale.dart';

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

  /// L04: số nhiều theo quy tắc CLDR của ngôn ngữ app. Key gốc `history_count` → chọn `history_count_one` / `_other`
  /// (và `_zero` / `_two` / `_few` / `_many` nếu ngôn ngữ đó có: ru, ar, pl…). Dạng thiếu → rơi về `_other`.
  /// ```dart
  /// 'history_count'.trPlural(n, [n])   // XML: history_count_one = "1 activity", history_count_other = "%1$s activities"
  /// ```
  String trPlural(num n, [List<Object?> args = const []]) {
    String? form(String suffix) {
      final key = '${this}_$suffix';
      final v = L10n(key).trArgs(args);
      return v == key ? null : v;
    }

    final other = form('other') ?? '${this}_other';
    return Intl.pluralLogic(
      n,
      locale: appDateLocale,
      zero: form('zero'),
      one: form('one'),
      two: form('two'),
      few: form('few'),
      many: form('many'),
      other: other,
    );
  }
}
