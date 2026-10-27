import 'package:asc_common/asc_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/utils/l10n.dart';

/// L04: chọn dạng số nhiều theo quy tắc CLDR của ngôn ngữ app.
void main() {
  tearDown(() => AscLocale.setAppLocale(const Locale('en', 'US')));

  test('en: 1 → _one, 0/2 → _other, có thay tham số', () {
    expect('history_count'.trPlural(1, [1]), 'history_count_one'.tr);
    expect('history_count'.trPlural(2, [2]), 'history_count_other'.trArgs([2]));
    expect('history_count'.trPlural(0, [0]), 'history_count_other'.trArgs([0]));
  });

  test('vi: tiếng Việt chỉ có một dạng (other) theo CLDR → kể cả n = 1', () async {
    await AscLocale.setAppLocale(const Locale('vi', 'VN'));
    expect('history_count'.trPlural(1, [1]), 'history_count_other'.trArgs([1]));
  });

  test('key gốc không có dạng nào → trả key _other (dễ thấy khi test bằng mắt)', () {
    expect('no_such_plural'.trPlural(3), 'no_such_plural_other');
  });
}
