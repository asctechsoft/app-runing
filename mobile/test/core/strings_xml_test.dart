import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Map<String, String> _load(String path) {
  final doc = XmlDocument.parse(File(path).readAsStringSync());
  return {for (final n in doc.findAllElements('string')) n.getAttribute('name')!: n.innerText};
}

final _placeholder = RegExp(r'%(\d+)\$s');

void main() {
  final en = _load('lib/xml_strings/values/strings.xml');
  final vi = _load('lib/xml_strings/values-vi/strings.xml');

  test('en và vi có cùng tập key (thiếu bản dịch là lỗi)', () {
    expect(vi.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'key chỉ có ở vi');
    expect(en.keys.toSet().difference(vi.keys.toSet()), isEmpty, reason: 'key chưa dịch sang vi');
  });

  test('placeholder %n\$s của en và vi khớp nhau, không có chuỗi rỗng', () {
    for (final k in en.keys) {
      expect(en[k]!.trim(), isNotEmpty, reason: k);
      expect(vi[k]!.trim(), isNotEmpty, reason: k);
      final a = _placeholder.allMatches(en[k]!).map((m) => m.group(1)).toList()..sort();
      final b = _placeholder.allMatches(vi[k]!).map((m) => m.group(1)).toList()..sort();
      expect(b, a, reason: 'placeholder lệch ở $k');
    }
  });

  test('mọi key dùng trong code (cú pháp \'key\'.tr / .trArgs) đều có trong XML', () {
    final used = <String>{};
    final pattern = RegExp(r'''['"]([a-z][a-z0-9_]*)['"]\s*\.(?:tr|trArgs)\b''');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('l10n.dart')) continue;
      used.addAll(pattern.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    }
    expect(used.difference(en.keys.toSet()), isEmpty);
  });

  // L04: 'base'.trPlural(n) cần ít nhất `base_other` ở mọi ngôn ngữ (dạng thiếu rơi về _other).
  test('mọi key số nhiều (base.trPlural) có dạng _other ở en và vi', () {
    final bases = <String>{};
    final pattern = RegExp(r'''['"]([a-z][a-z0-9_]*)['"]\s*\.trPlural\b''');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart')) bases.addAll(pattern.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    }
    expect(bases, isNotEmpty);
    final missing = [
      for (final b in bases)
        for (final (lang, map) in [('en', en), ('vi', vi)])
          if (!map.containsKey('${b}_other')) '$lang:${b}_other',
    ];
    expect(missing, isEmpty);
  });

  // L17: chặn chuỗi giao diện viết cứng tái phát (Text('…'), label:/title:/hintText:/tooltip:… là literal có chữ, không qua .tr).
  // Ngoại lệ có chủ đích: tên thương hiệu STRIDE.
  test('không có chuỗi giao diện viết cứng trong lib/', () {
    const allowed = {'STRIDE'};
    final pattern = RegExp(
      r'''(?:\bText|label:|title:|hintText:|labelText:|helperText:|tooltip:|semanticLabel:|message:|semanticsLabel:)\s*\(?\s*'([^'$\\]*[A-Za-z]{2,}[^'$\\]*)'\s*[,)]''',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          if (!allowed.contains(m.group(1))) offenders.add('${f.path}:${i + 1}: ${m.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Thêm key vào values/strings.xml + values-vi/strings.xml và dùng .tr (CLAUDE.md)');
  });
}
