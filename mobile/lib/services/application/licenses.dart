import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// X13: bổ sung vào trang giấy phép (`showLicensePage`) những thứ không đi kèm package Dart: font Inter (SIL OFL 1.1) và dữ liệu
/// bản đồ OpenStreetMap (ODbL). Văn bản pháp lý giữ nguyên tiếng Anh (bản gốc có hiệu lực), không đưa vào XML dịch.
void registerExtraLicenses() {
  LicenseRegistry.addLicense(() async* {
    final inter = await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter (font)'], inter);
    yield const LicenseEntryWithLineBreaks(['OpenStreetMap (map data)'], _osm);
  });
}

const _osm =
    'Map data © OpenStreetMap contributors, available under the Open Database License (ODbL) v1.0.\n'
    'https://www.openstreetmap.org/copyright\n\n'
    'Map tiles are provided by the configured tile provider and are subject to its terms of use.';

@visibleForTesting
const osmLicenseText = _osm;
