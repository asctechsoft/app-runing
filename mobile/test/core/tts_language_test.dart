import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/run/engine/run_audio.dart';

/// L07: giọng đọc theo ngôn ngữ app (tag BCP-47), lùi tiếng Anh khi máy không có giọng (kiểm chứng trên máy thật — mục 3).
void main() {
  test('locale app → tag BCP-47 cho TTS', () {
    expect(ttsLanguageTag(const Locale('vi', 'VN')), 'vi-VN');
    expect(ttsLanguageTag(const Locale('en', 'US')), 'en-US');
    expect(ttsLanguageTag(const Locale('ja')), 'ja');
    expect(ttsFallbackLanguage, 'en-US');
  });
}
