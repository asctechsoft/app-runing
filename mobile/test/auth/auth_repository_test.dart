import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/features/auth/auth_repository.dart';

const _base = 'http://test.local/api/v1';

Map<String, Object?> _tokens(String a, String r) => {
  'accessToken': a,
  'refreshToken': r,
  'accessTokenExpiresAt': 2000000,
  'expiresIn': 900,
  'tokenType': 'Bearer',
};

void main() {
  late MemoryTokenStore tokens;
  late FakeClock clock;
  late List<http.Request> requests;

  Future<AuthRepository> build(Future<http.Response> Function(http.Request) handler, {String baseUrl = _base, Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final client = MockClient((r) async {
      requests.add(r);
      return handler(r);
    });
    return AuthRepository(
      api: buildAuthApiClient(baseUrl: baseUrl, tokens: tokens, client: client),
      tokens: tokens,
      prefs: p,
      clock: clock,
      http: client,
    );
  }

  setUp(() {
    tokens = MemoryTokenStore();
    clock = FakeClock(1000000);
    requests = [];
  });

  group('AuthRepository (E02)', () {
    test('login lưu token từ phản hồi {user, tokens}', () async {
      final repo = await build(
        (r) async => http.Response(
          jsonEncode({
            'user': {'id': 'u1', 'email': 'a@example.com', 'emailVerified': false},
            'tokens': _tokens('acc', 'ref'),
          }),
          200,
        ),
      );
      final u = await repo.login(email: ' a@example.com ', password: 'secret123');
      expect(u.id, 'u1');
      expect(await tokens.accessToken(), 'acc');
      expect(await tokens.refreshToken(), 'ref');
      expect(requests.single.url.path, '/api/v1/auth/login');
      expect(jsonDecode(requests.single.body), {'email': 'a@example.com', 'password': 'secret123'});
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('authed: 401 → refresh đúng định dạng lồng nhau → thử lại một lần', () async {
      await tokens.save(access: 'old', refresh: 'r-old');
      var meCalls = 0;
      final repo = await build((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          expect(jsonDecode(r.body), {'refreshToken': 'r-old'});
          return http.Response(
            jsonEncode({
              'user': {'id': 'u1', 'email': 'a@b.co'},
              'tokens': _tokens('new', 'r-new'),
            }),
            200,
          );
        }
        meCalls++;
        if (r.headers['Authorization'] == 'Bearer old') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'invalid_token', 'message': 'expired'},
            }),
            401,
          );
        }
        return http.Response(jsonEncode({'user': {}, 'profile': {}}), 200);
      }, prefs: {'auth_access_expires_at': 99999999});
      await repo.me();
      expect(meCalls, 2);
      expect(await tokens.accessToken(), 'new');
      expect(await tokens.refreshToken(), 'r-new');
      expect(requests.where((r) => r.url.path.endsWith('/auth/refresh')).length, 1, reason: 'ApiClient lõi không được tự refresh (đốt refresh token)');
    });

    test('refresh bị từ chối 401 → xóa token (phải đăng nhập lại)', () async {
      await tokens.save(access: 'a', refresh: 'r');
      final repo = await build(
        (r) async => http.Response(
          jsonEncode({
            'error': {'code': 'refresh_token_reused', 'message': 'x'},
          }),
          401,
        ),
      );
      expect(await repo.refresh(), isFalse);
      expect(await tokens.refreshToken(), isNull);
      expect(await repo.hasCredentials(), isFalse);
    });

    test('ensureFresh refresh trước khi access token hết hạn', () async {
      await tokens.save(access: 'a', refresh: 'r');
      final repo = await build(
        (r) async => http.Response(
          jsonEncode({
            'user': {'id': 'u', 'email': 'e@x.co'},
            'tokens': _tokens('a2', 'r2'),
          }),
          200,
        ),
        prefs: {'auth_access_expires_at': 1000000 + 30 * 1000},
      );
      await repo.ensureFresh();
      expect(await tokens.accessToken(), 'a2');
    });

    test('logout luôn xóa token kể cả khi offline', () async {
      await tokens.save(access: 'a', refresh: 'r');
      final repo = await build((r) async => throw http.ClientException('offline'), prefs: {'auth_access_expires_at': 99999999});
      await repo.logout();
      expect(await tokens.accessToken(), isNull);
      expect(await tokens.refreshToken(), isNull);
    });

    test('build không có server: available=false, không giả thành công', () async {
      final repo = await build((r) async => http.Response('{}', 200), baseUrl: '');
      expect(repo.available, isFalse);
      await expectLater(repo.login(email: 'a@b.co', password: 'x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_configured')));
      expect(requests, isEmpty);
    });
  });

  group('authErrorMessage', () {
    test('offline khi đăng nhập', () {
      expect(authErrorMessage(ApiException(0, 'network', 'x'), AuthAction.login), "You're offline. Connect to the internet to sign in.");
    });
    test('sai thông tin, email đã có, link hết hạn, rate limit', () {
      expect(authErrorMessage(ApiException(401, 'invalid_credentials', 'x'), AuthAction.login), 'Email or password is incorrect.');
      expect(authErrorMessage(ApiException(401, 'invalid_credentials', 'x'), AuthAction.reauth), 'That password is incorrect.');
      expect(authErrorMessage(ApiException(409, 'email_taken', 'x'), AuthAction.register), contains('already exists'));
      expect(authErrorMessage(ApiException(400, 'invalid_token', 'x'), AuthAction.reset), contains('invalid or has expired'));
      expect(authErrorMessage(ApiException(429, 'rate_limited', 'x'), AuthAction.login), contains('Too many attempts'));
    });
    test('validation dùng message đầu tiên từ server', () {
      final e = ApiException(422, 'validation_error', 'Invalid input', [
        {'path': 'password', 'message': 'Password must contain a number'},
      ]);
      expect(authErrorMessage(e, AuthAction.register), 'Password must contain a number.');
    });
    test('không cấu hình server', () {
      expect(authErrorMessage(ApiException(0, 'not_configured', 'x'), AuthAction.login), "Accounts aren't available in this build.");
    });
    test('5xx không lộ chi tiết kỹ thuật', () {
      expect(authErrorMessage(ApiException(500, 'internal_error', 'stack...'), AuthAction.login), 'Something went wrong on our side. Please try again.');
    });
  });

  group('Quy tắc mật khẩu (khớp backend)', () {
    test('≥ 8 ký tự, có chữ cái, có chữ số', () {
      expect(passwordValid('abcdefg1'), isTrue);
      expect(passwordValid('abcdefgh'), isFalse);
      expect(passwordValid('12345678'), isFalse);
      expect(passwordValid('abc12'), isFalse);
      expect(passwordValid('mậtkhẩu9'), isTrue, reason: 'chữ cái Unicode được tính');
    });
    test('không có quy tắc ký tự đặc biệt (backend không yêu cầu)', () {
      expect(passwordRules.map((r) => r.label), ['At least 8 characters', 'Includes a letter', 'Includes a number']);
    });
    test('quá 72 byte bị từ chối (giới hạn bcrypt)', () {
      expect(passwordValid('a1${'x' * 71}'), isFalse);
      expect(passwordTooLong('ệ' * 25), isTrue);
    });
    test('email', () {
      expect(validateEmail('a@b.co'), isNull);
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('not-an-email'), isNotNull);
    });
  });
}
