import 'dart:ui';

import 'package:asc_common/asc_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/utils/l10n.dart';

void main() {
  test('.tr đọc đúng chuỗi XML en/vi và thiếu key thì trả về key', () async {
    expect('app_tagline'.tr, 'Every step, your way');
    await AscLocale.setAppLocale(const Locale('vi', 'VN'));
    expect('app_tagline'.tr, 'Mỗi bước chân, theo cách của bạn');
    expect('khong_co_key_nay'.tr, 'khong_co_key_nay');
    await AscLocale.setAppLocale(const Locale('en', 'US'));
    expect('app_tagline'.tr, 'Every step, your way');
  });
}
