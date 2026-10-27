import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/application/licenses.dart';

/// X13: trang giấy phép có font Inter (OFL) và ghi công OpenStreetMap (ODbL).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('đăng ký giấy phép Inter + OpenStreetMap', () async {
    registerExtraLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, containsAll(['Inter (font)', 'OpenStreetMap (map data)']));
    final inter = entries.firstWhere((e) => e.packages.contains('Inter (font)'));
    expect(inter.paragraphs.map((p) => p.text).join(' '), contains('SIL Open Font License'));
    expect(osmLicenseText, contains('ODbL'));
  });
}
