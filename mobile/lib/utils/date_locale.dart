import 'package:asc_common/asc_common.dart';
import 'package:intl/intl.dart';

/// Locale dùng cho `DateFormat` (tên thứ/tháng, AM/PM) — theo ngôn ngữ app đang chọn (`en_US`, `vi_VN`...).
/// Cần `initializeDateFormatting()` lúc khởi động (xem `main.dart` và `test/flutter_test_config.dart`).
String get appDateLocale => AscLocale.getAppLocale().toString();

/// L08: định dạng ngày/giờ theo skeleton của `intl` để thứ tự đúng từng ngôn ngữ ("Thursday, October 22, 2026" /
/// "Thứ Năm, 22 tháng 10, 2026"). Màn hình không ghi mẫu kiểu tiếng Anh (`'EEEE, MMMM d, y'`) — dùng các hàm này.
/// Giờ dùng `jm` (12/24 giờ theo ngôn ngữ).
abstract final class AppDates {
  /// "Thursday, October 22, 2026"
  static String longDate(DateTime d) => DateFormat.yMMMMEEEEd(appDateLocale).format(d);

  /// "Thursday, October 22"
  static String weekdayMonthDay(DateTime d) => DateFormat.MMMMEEEEd(appDateLocale).format(d);

  /// "Thu, Oct 22"
  static String shortWeekdayDate(DateTime d) => DateFormat.MMMEd(appDateLocale).format(d);

  /// "Thu, Oct 22, 2026"
  static String shortWeekdayDateYear(DateTime d) => DateFormat.yMMMEd(appDateLocale).format(d);

  /// "Oct 22"
  static String monthDay(DateTime d) => DateFormat.MMMd(appDateLocale).format(d);

  /// "Oct 22, 2026"
  static String monthDayYear(DateTime d) => DateFormat.yMMMd(appDateLocale).format(d);

  /// "October 2026"
  static String monthYear(DateTime d) => DateFormat.yMMMM(appDateLocale).format(d);

  /// "Thursday"
  static String weekday(DateTime d) => DateFormat.EEEE(appDateLocale).format(d);

  /// "Thu"
  static String weekdayShort(DateTime d) => DateFormat.E(appDateLocale).format(d);

  /// "7:20 AM" / "07:20"
  static String time(DateTime d) => DateFormat.jm(appDateLocale).format(d);

  /// "Oct 22, 7:20 AM"
  static String monthDayTime(DateTime d) => DateFormat.MMMd(appDateLocale).add_jm().format(d);

  /// "Thu, Oct 22 · 7:20 AM"
  static String shortWeekdayDateTime(DateTime d) => '${shortWeekdayDate(d)} · ${time(d)}';
}
