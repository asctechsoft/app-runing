import 'package:flutter/foundation.dart';

/// Logger có che dữ liệu nhạy cảm (B04, N01): token, mật khẩu, tọa độ.
class StrideLog {
  static final _patterns = <RegExp, String>{
    RegExp(r'(Bearer\s+)[A-Za-z0-9\-_\.]+'): r'$1[redacted]',
    RegExp(r'("?(password|token|accessToken|refreshToken|authorization)"?\s*[:=]\s*)"?[^",\s}]+"?', caseSensitive: false): r'$1[redacted]',
    RegExp(r'("?(lat|lon|latitude|longitude)"?\s*[:=]\s*)-?\d+(\.\d+)?', caseSensitive: false): r'$1[redacted]',
    RegExp(r'-?\d{1,3}\.\d{4,},\s*-?\d{1,3}\.\d{4,}'): '[coords]',
  };

  static String redact(String input) {
    var out = input;
    _patterns.forEach((re, rep) {
      out = out.replaceAllMapped(re, (m) {
        var r = rep;
        for (var i = 1; i <= m.groupCount; i++) {
          r = r.replaceAll('\$$i', m.group(i) ?? '');
        }
        return r;
      });
    });
    return out;
  }

  static void d(String tag, String message) {
    if (kDebugMode) debugPrint('[$tag] ${redact(message)}');
  }

  static void e(String tag, Object error, [StackTrace? st]) {
    debugPrint('[$tag] ERROR ${redact(error.toString())}');
    if (st != null && kDebugMode) debugPrint(st.toString());
  }
}
