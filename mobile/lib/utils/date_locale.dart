import 'package:asc_common/asc_common.dart';

/// Locale dùng cho `DateFormat` (tên thứ/tháng, AM/PM) — theo ngôn ngữ app đang chọn (`en_US`, `vi_VN`...).
/// Cần `initializeDateFormatting()` lúc khởi động (xem `main.dart` và `test/flutter_test_config.dart`).
String get appDateLocale => AscLocale.getAppLocale().toString();
