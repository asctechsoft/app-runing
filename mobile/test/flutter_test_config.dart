import 'dart:async';
import 'dart:ui';

import 'package:asc_common/asc_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' as g;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/locale_config.dart';

/// Chạy trước MỖI file test: nạp chuỗi XML (en_US) để `'key'.tr` ra đúng chữ như app thật — test vẫn so khớp văn bản tiếng Anh.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  AppLocaleConfig.configure();
  g.Get.fallbackLocale = const Locale('en', 'US');
  await AscLocale.setAppLocale(const Locale('en', 'US'));
  await initializeDateFormatting();
  await testMain();
}
