import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/features/profile/help_screen.dart';

ApiClient _api(MockClientHandler h, {String base = 'http://x/api/v1'}) => ApiClient(baseUrl: base, tokens: MemoryTokenStore(), client: MockClient(h));

void main() {
  test('gửi thành công → sent, body đúng hợp đồng', () async {
    late Map<String, dynamic> body;
    final s = FeedbackSender(
      _api((req) async {
        expect(req.url.path, '/api/v1/feedback');
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'f1'}), 201);
      }),
    );
    expect(await s.send(message: 'Map froze', diagnostics: 'env=dev', appVersion: '1.0.0'), FeedbackResult.sent);
    expect(body, {'message': 'Map froze', 'diagnostics': 'env=dev', 'appVersion': '1.0.0'});
  });

  test('server cũ (404) hoặc không có server → unavailable để chuyển share sheet', () async {
    final old = FeedbackSender(_api((req) async => http.Response('Not found', 404)));
    expect(await old.send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
    final none = FeedbackSender(_api((req) async => fail('không được gọi mạng'), base: ''));
    expect(await none.send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
  });

  test('429 → ném lỗi, không báo đã gửi', () async {
    final s = FeedbackSender(
      _api(
        (req) async => http.Response(
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'slow down'},
          }),
          429,
        ),
      ),
    );
    await expectLater(s.send(message: 'x', appVersion: '1'), throwsA(isA<ApiException>()));
  });
}
