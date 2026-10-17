import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stride/core/network/api_client.dart';

void main() {
  test('401 → refresh với response {tokens:{...}} → lưu cặp token mới và gọi lại', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'old', refresh: 'r1');
    var meCalls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/auth/refresh')) {
        expect(jsonDecode(req.body)['refreshToken'], 'r1');
        return http.Response(
          jsonEncode({
            'user': {'id': 'u'},
            'tokens': {'accessToken': 'new', 'refreshToken': 'r2'},
          }),
          200,
        );
      }
      meCalls++;
      if (req.headers['Authorization'] == 'Bearer new') return http.Response(jsonEncode({'id': 'u'}), 200);
      return http.Response(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'expired'},
        }),
        401,
      );
    });
    final api = ApiClient(baseUrl: 'http://x/api/v1', tokens: tokens, client: client);
    final r = await api.get('/me');
    expect((r as Map)['id'], 'u');
    expect(meCalls, 2);
    expect(await tokens.accessToken(), 'new');
    expect(await tokens.refreshToken(), 'r2');
  });

  test('refresh thất bại → xóa token và báo hết phiên', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'old', refresh: 'r1');
    var expired = false;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/auth/refresh')) return http.Response('{}', 401);
      return http.Response(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'expired'},
        }),
        401,
      );
    });
    final api = ApiClient(baseUrl: 'http://x/api/v1', tokens: tokens, client: client)..onSessionExpired = () => expired = true;
    await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', true)));
    expect(expired, isTrue);
    expect(await tokens.refreshToken(), isNull);
  });
}
