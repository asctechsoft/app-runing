import 'dart:ui';

import 'package:asc_common/asc_common.dart';
import 'package:get/get.dart' as g;
import 'package:shared_preferences/shared_preferences.dart';

import 'pref_const.dart';

/// Cấu hình ngôn ngữ của app cho [AscLocale]: mỗi locale ứng một thư mục `lib/xml_strings/values*/` (XML kiểu Android,
/// giữ nguyên quy trình dịch của công ty — xem `tool/translate.py`).
class AppLocaleConfig {
  AppLocaleConfig._();

  static const List<Locale> supportedLocales = <Locale>[Locale('en', 'US'), Locale('vi', 'VN')];

  /// Gọi một lần lúc khởi động, trước mọi lần dùng [AscLocale].
  static void configure() =>
      AscLocale.configure(supportedLocales: supportedLocales, languagePrefKey: PrefConst.language, followSystemPrefKey: PrefConst.followSystemLanguage);

  /// Chọn locale lúc khởi động: ngôn ngữ đã ghim (nếu còn được hỗ trợ), nếu không thì ngôn ngữ của thiết bị.
  /// [AscLocale.setAppLocale] tự lưu lựa chọn nên không cần ghi pref thêm.
  static Future<void> ensureConfigured() async {
    // Không có GetMaterialApp nên tự đặt locale dự phòng: key thiếu ở ngôn ngữ hiện tại rơi về tiếng Anh.
    g.Get.fallbackLocale = const Locale('en', 'US');
    final prefs = await SharedPreferences.getInstance();
    final followSystem = prefs.getBool(PrefConst.followSystemLanguage) ?? false;

    if (!followSystem) {
      final saved = prefs.getString(PrefConst.language) ?? '';
      if (saved.isNotEmpty) {
        final parts = saved.split('_');
        final locale = parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
        final supported = AscLocale.supportedLocales.any((l) => l.languageCode == locale.languageCode && (l.countryCode ?? '') == (locale.countryCode ?? ''));
        if (supported) {
          await AscLocale.setAppLocale(locale);
          return;
        }
      }
    }
    await AscLocale.setAppLocale(AscLocale.bestSupportedMatchFor(AscLocale.getSystemLocale()));
  }
}
