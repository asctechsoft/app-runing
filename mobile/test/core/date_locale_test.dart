import 'package:asc_common/asc_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/ui_models/period.dart';
import 'package:stride/utils/date_locale.dart';
import 'package:stride/utils/formatters.dart';

/// L08: ngày/giờ theo skeleton của intl — tiếng Anh giữ nguyên chuỗi như mẫu cũ, tiếng Việt đúng thứ tự "ngày tháng năm".
void main() {
  final d = DateTime(2026, 10, 22, 7, 20);

  tearDown(() => AscLocale.setAppLocale(const Locale('en', 'US')));

  test('en_US: giống mẫu cũ (không đổi giao diện tiếng Anh)', () {
    expect(AppDates.longDate(d), 'Thursday, October 22, 2026');
    expect(AppDates.weekdayMonthDay(d), 'Thursday, October 22');
    expect(AppDates.shortWeekdayDate(d), 'Thu, Oct 22');
    expect(AppDates.monthDayYear(d), 'Oct 22, 2026');
    expect(AppDates.monthYear(d), 'October 2026');
    expect(AppDates.time(d), matches(RegExp(r'^7:20\sAM$')), reason: 'intl có thể dùng khoảng trắng hẹp U+202F trước AM');
  });

  test('vi_VN: ngày đứng trước tháng, không ra "tháng 10 22, 2026"', () async {
    await AscLocale.setAppLocale(const Locale('vi', 'VN'));
    expect(AppDates.longDate(d), contains('22 tháng 10'));
    expect(AppDates.longDate(d), isNot(contains('tháng 10 22')));
    expect(AppDates.monthYear(d), contains('10'));
    expect(AppDates.time(d), '7:20', reason: 'tiếng Việt dùng 24 giờ, không có AM/PM');
  });

  test('periodLabel tuần: en dạng gọn, vi ghi đủ hai đầu theo thứ tự tiếng Việt', () async {
    final week = PeriodRange(ProgressPeriod.week, DateTime(2026, 10, 12), DateTime(2026, 10, 19));
    expect(periodLabel(week), 'Oct 12 – 18, 2026');
    await AscLocale.setAppLocale(const Locale('vi', 'VN'));
    final vi = periodLabel(week);
    expect(vi, contains('12 thg 10'));
    expect(vi, contains('18 thg 10, 2026'));
  });

  test('L09: số theo locale — vi dùng dấu chấm phân tách hàng nghìn và dấu phẩy thập phân', () {
    const en = StrideFormat();
    const vi = StrideFormat(locale: 'vi_VN');
    expect(en.steps(12345), '12,345');
    expect(vi.steps(12345), '12.345');
    expect(vi.distanceValue(5200), '5,20');
    expect(en.distanceValue(5200), '5.20');
  });
}
