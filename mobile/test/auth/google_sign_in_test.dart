import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/core/theme/stride_theme.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/features/auth/auth_flow.dart';
import 'package:stride/features/auth/auth_repository.dart';
import 'package:stride/features/auth/google_sign_in_button.dart';
import 'package:stride/features/auth/google_sign_in_service.dart';

class _FakeGoogle implements GoogleIdTokenSource {
  _FakeGoogle(this.result);
  final Object result; // String token hoặc exception
  int calls = 0;
  @override
  Future<String> signInAndGetIdToken() async {
    calls++;
    if (result is String) return result as String;
    throw result;
  }

  @override
  Future<void> signOut() async {}
}

const _base = 'http://test.local/api/v1';

void main() {
  late MemoryTokenStore tokens;
  late List<http.Request> requests;

  Future<AuthRepository> repo(Future<http.Response> Function(http.Request) handler) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final client = MockClient((r) async {
      requests.add(r);
      return handler(r);
    });
    return AuthRepository(
      api: buildAuthApiClient(baseUrl: _base, tokens: tokens, client: client),
      tokens: tokens,
      prefs: p,
      clock: FakeClock(),
      http: client,
    );
  }

  setUp(() {
    tokens = MemoryTokenStore();
    requests = [];
  });

  test('loginWithFirebase gửi idToken tới /auth/firebase và lưu token STRIDE', () async {
    final r = await repo(
      (req) async => http.Response(
        jsonEncode({
          'user': {'id': 'u9', 'email': 'g@example.com', 'emailVerified': true},
          'tokens': {'accessToken': 'acc', 'refreshToken': 'ref', 'accessTokenExpiresAt': 99},
        }),
        200,
      ),
    );
    final u = await r.loginWithFirebase('firebase-id-token');
    expect(u.id, 'u9');
    expect(requests.single.url.path, '/api/v1/auth/firebase');
    expect(jsonDecode(requests.single.body), {'idToken': 'firebase-id-token'});
    expect(requests.single.headers['Authorization'], isNull);
    expect(await tokens.accessToken(), 'acc');
    expect(await tokens.refreshToken(), 'ref');
  });

  test('tài khoản email chưa xác minh → thông báo cụ thể, không lưu token', () async {
    final r = await repo(
      (req) async => http.Response(
        jsonEncode({
          'error': {'code': 'account_exists_unverified', 'message': 'x'},
        }),
        409,
      ),
    );
    try {
      await r.loginWithFirebase('t');
      fail('phải ném lỗi');
    } catch (e) {
      expect(googleSignInErrorMessage(e), contains("isn't verified"));
    }
    expect(await tokens.accessToken(), isNull);
  });

  test('lỗi phía Google có thông báo riêng', () {
    expect(googleSignInErrorMessage(const GoogleSignInFailure('network_error')), contains("Couldn't sign in with Google"));
  });

  testWidgets('hủy chọn tài khoản → không gọi backend, không báo lỗi', (tester) async {
    final fake = _FakeGoogle(const GoogleSignInCancelled());
    final r = await repo((req) async => fail('không được gọi backend'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [googleIdTokenSourceProvider.overrideWithValue(fake), authRepositoryProvider.overrideWithValue(r)],
        child: MaterialApp(
          theme: buildStrideTheme(),
          home: const Scaffold(body: Center(child: GoogleSignInButton())),
        ),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    expect(requests, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });
}
