import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/time/clock.dart';

/// Người dùng trả về từ backend (`toUserDto`).
class AuthUser {
  const AuthUser({required this.id, required this.email, this.emailVerified = false, this.displayName});

  final String id;
  final String email;
  final bool emailVerified;
  final String? displayName;

  factory AuthUser.fromJson(Map<String, Object?> j) => AuthUser(
    id: j['id'] as String,
    email: j['email'] as String,
    emailVerified: j['emailVerified'] as bool? ?? false,
    displayName: j['displayName'] as String?,
  );
}

/// TokenStore bọc lại nhưng ẩn refresh token khỏi ApiClient lõi.
///
/// Lý do: `ApiClient._refresh` (lib/core) đọc `accessToken` ở cấp gốc, còn backend trả `{user, tokens:{...}}`.
/// Nếu để ApiClient tự refresh, refresh token bị server đánh dấu đã dùng nhưng client không lưu được token mới
/// → lần sau bị coi là reuse và cả phiên bị thu hồi. Vì vậy feature tự refresh (xem [AuthRepository.refresh]).
class _NoAutoRefreshTokens implements TokenStore {
  _NoAutoRefreshTokens(this._inner);
  final TokenStore _inner;
  @override
  Future<String?> accessToken() => _inner.accessToken();
  @override
  Future<String?> refreshToken() async => null;
  @override
  Future<void> save({required String access, required String refresh}) => _inner.save(access: access, refresh: refresh);
  @override
  Future<void> clear() => _inner.clear();
}

/// HTTP client dùng cho auth/sync — override bằng MockClient trong test.
final authHttpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// ApiClient của feature auth/sync: cùng base URL và kho token với apiClientProvider, nhưng không tự refresh sai định dạng.
final authApiClientProvider = Provider<ApiClient>((ref) {
  final base = ref.watch(apiClientProvider);
  return buildAuthApiClient(baseUrl: base.baseUrl, tokens: ref.watch(tokenStoreProvider), client: ref.watch(authHttpClientProvider));
});

/// ApiClient không tự refresh (refresh do [AuthRepository] đảm nhiệm với đúng định dạng phản hồi).
ApiClient buildAuthApiClient({required String baseUrl, required TokenStore tokens, required http.Client client}) =>
    ApiClient(baseUrl: baseUrl, tokens: _NoAutoRefreshTokens(tokens), client: client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(authApiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
    prefs: ref.watch(sharedPrefsProvider),
    clock: ref.watch(clockProvider),
    http: ref.watch(authHttpClientProvider),
  ),
);

/// Client auth theo backend/openapi (base /api/v1). Không bao giờ log mật khẩu/token.
class AuthRepository {
  AuthRepository({required this.api, required this.tokens, required SharedPreferences prefs, required Clock clock, required http.Client http})
    : _prefs = prefs,
      _clock = clock,
      _http = http;

  final ApiClient api;
  final TokenStore tokens;
  final SharedPreferences _prefs;
  final Clock _clock;
  final http.Client _http;
  Future<bool>? _refreshing;

  static const _kAccessExp = 'auth_access_expires_at';

  /// Build không có server → UI hiển thị trạng thái "Accounts aren't available" thay vì giả thành công.
  bool get available => api.configured;

  Future<bool> hasCredentials() async => (await tokens.refreshToken()) != null || (await tokens.accessToken()) != null;

  Future<void> _saveTokens(Object? tokensJson) async {
    if (tokensJson is! Map) throw ApiException(500, 'bad_response', 'Unexpected server response');
    final access = tokensJson['accessToken'];
    final refresh = tokensJson['refreshToken'];
    if (access is! String || refresh is! String) throw ApiException(500, 'bad_response', 'Unexpected server response');
    await tokens.save(access: access, refresh: refresh);
    final exp = tokensJson['accessTokenExpiresAt'];
    final expiresIn = tokensJson['expiresIn'];
    final expMs = exp is num ? exp.toInt() : (expiresIn is num ? _clock.nowMs() + expiresIn.toInt() * 1000 : null);
    if (expMs != null) {
      await _prefs.setInt(_kAccessExp, expMs);
    } else {
      await _prefs.remove(_kAccessExp);
    }
  }

  AuthUser _userOf(Object? res) {
    if (res is! Map || res['user'] is! Map) throw ApiException(500, 'bad_response', 'Unexpected server response');
    return AuthUser.fromJson((res['user'] as Map).cast<String, Object?>());
  }

  Future<AuthUser> register({required String email, required String password, String? displayName}) async {
    final res = await api.post(
      '/auth/register',
      auth: false,
      body: {'email': email.trim(), 'password': password, if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim()},
    );
    await _saveTokens((res as Map)['tokens']);
    return _userOf(res);
  }

  Future<AuthUser> login({required String email, required String password}) async {
    final res = await api.post('/auth/login', auth: false, body: {'email': email.trim(), 'password': password});
    await _saveTokens((res as Map)['tokens']);
    return _userOf(res);
  }

  /// Đăng nhập bằng Firebase ID token (Google). Backend verify token và cấp JWT STRIDE như /auth/login.
  Future<AuthUser> loginWithFirebase(String idToken) async {
    final res = await api.post('/auth/firebase', auth: false, body: {'idToken': idToken});
    await _saveTokens((res as Map)['tokens']);
    return _userOf(res);
  }

  /// Luôn trả kết quả chung (backend không tiết lộ email tồn tại).
  Future<void> forgotPassword(String email) async {
    await api.post('/auth/forgot-password', auth: false, body: {'email': email.trim()});
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await api.post('/auth/reset-password', auth: false, body: {'token': token, 'newPassword': newPassword});
  }

  Future<AuthUser> verifyEmail(String token) async => _userOf(await api.post('/auth/verify-email', auth: false, body: {'token': token}));

  Future<void> resendVerification() => authed(() => api.post('/auth/resend-verification'));

  /// Xác thực lại bằng mật khẩu → mở cửa sổ 5 phút cho thao tác nhạy cảm (xóa tài khoản).
  Future<void> reauth(String password) => authed(() => api.post('/auth/reauth', body: {'password': password}));

  /// Xác thực lại bằng Google cho tài khoản không có mật khẩu.
  Future<void> reauthWithFirebase(String idToken) => authed(() => api.post('/auth/reauth', body: {'idToken': idToken}));

  /// Hồ sơ trên server: `{user, profile}`.
  Future<Map<String, Object?>> me() async => ((await authed(() => api.get('/me'))) as Map).cast<String, Object?>();

  /// Thu hồi phiên trên server (best-effort) rồi luôn xóa token khỏi máy.
  Future<void> logout() async {
    try {
      if (api.configured && await tokens.accessToken() != null) {
        await authed(() => api.post('/auth/logout')).timeout(const Duration(seconds: 8));
      }
    } catch (_) {
      // Offline/hết hạn: token local vẫn bị xóa; phiên server tự hết hạn.
    } finally {
      await clearLocal();
    }
  }

  Future<void> clearLocal() async {
    await tokens.clear();
    await _prefs.remove(_kAccessExp);
  }

  /// Refresh xoay vòng, tuần tự hóa (một request tại một thời điểm). Trả false khi phiên không còn hợp lệ.
  Future<bool> refresh() {
    return _refreshing ??= () async {
      try {
        final rt = await tokens.refreshToken();
        if (rt == null || !api.configured) return false;
        final res = await _http
            .post(
              Uri.parse('${api.baseUrl}/auth/refresh'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({'refreshToken': rt}),
            )
            .timeout(api.timeout);
        if (res.statusCode == 401) {
          // Refresh token không hợp lệ/đã thu hồi → phải đăng nhập lại.
          await clearLocal();
          return false;
        }
        if (res.statusCode != 200) return false;
        final j = jsonDecode(res.body);
        await _saveTokens(j is Map ? j['tokens'] : null);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// Refresh trước khi access token hết hạn (biên 60 s) để không chạm nhánh 401.
  Future<void> ensureFresh() async {
    final exp = _prefs.getInt(_kAccessExp);
    final hasAccess = await tokens.accessToken() != null;
    if (!hasAccess || (exp != null && exp - _clock.nowMs() < 60 * 1000)) await refresh();
  }

  /// Gọi API cần đăng nhập: làm tươi token, gặp 401 thì refresh một lần rồi thử lại.
  Future<T> authed<T>(Future<T> Function() call) async {
    await ensureFresh();
    try {
      return await call();
    } on ApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      if (!await refresh()) rethrow;
      return call();
    }
  }
}

/// Ngữ cảnh lỗi để chọn câu thông báo cụ thể (E02).
enum AuthAction { login, register, forgot, reset, verify, reauth, other }

/// Map lỗi API → thông báo cụ thể cho người dùng; không lộ chi tiết kỹ thuật.
String authErrorMessage(Object error, AuthAction action) {
  if (error is! ApiException) return 'Something went wrong. Please try again.';
  if (error.code == 'not_configured') return "Accounts aren't available in this build.";
  if (error.isNetwork) {
    return switch (action) {
      AuthAction.login => "You're offline. Connect to the internet to sign in.",
      AuthAction.register => "You're offline. Connect to the internet to create an account.",
      _ => "You're offline. Connect to the internet and try again.",
    };
  }
  switch (error.code) {
    case 'invalid_credentials':
      return action == AuthAction.reauth ? 'That password is incorrect.' : 'Email or password is incorrect.';
    case 'email_taken':
      return 'An account with this email already exists. Try logging in instead.';
    case 'invalid_token':
      return action == AuthAction.verify || action == AuthAction.reset
          ? 'This link is invalid or has expired. Request a new one.'
          : 'Your session has expired. Please log in again.';
    case 'invalid_refresh_token':
    case 'refresh_token_reused':
    case 'unauthorized':
      return 'Your session has expired. Please log in again.';
    case 'rate_limited':
      return 'Too many attempts. Wait a minute and try again.';
    case 'account_exists_unverified':
      return "An account with this email already exists but isn't verified. Log in with your password and verify your email first.";
    case 'email_not_verified':
      return 'Your Google account email isn\'t verified. Verify it with Google or use your email instead.';
    case 'account_disabled':
      return 'This account is being deleted or has been deleted.';
    case 'invalid_id_token':
      return "Couldn't confirm your Google sign-in. Please try again.";
    case 'provider_not_configured':
      return "Sign in with Google isn't available on this server yet. Use your email instead.";
    case 'account_deletion_pending':
      return 'This account is being deleted.';
    case 'account_deleted':
      return 'This account has been deleted.';
    case 'validation_error':
      return _validationMessage(error.details) ?? 'Some details are not valid. Check and try again.';
  }
  if (error.status >= 500) return 'Something went wrong on our side. Please try again.';
  return error.message.isNotEmpty ? error.message : 'Something went wrong. Please try again.';
}

String? _validationMessage(Object? details) {
  if (details is List && details.isNotEmpty && details.first is Map) {
    final m = (details.first as Map)['message'];
    if (m is String && m.isNotEmpty) return m.endsWith('.') ? m : '$m.';
  }
  return null;
}

/// Quy tắc mật khẩu mà backend thực sự kiểm tra (validators/auth.ts): ≥ 8 ký tự, có chữ cái, có chữ số, ≤ 72 byte.
class PasswordRule {
  const PasswordRule(this.label, this.test);
  final String label;
  final bool Function(String) test;
}

final passwordRules = <PasswordRule>[
  PasswordRule('At least 8 characters', (p) => p.length >= 8),
  PasswordRule('Includes a letter', (p) => RegExp(r'\p{L}', unicode: true).hasMatch(p)),
  PasswordRule('Includes a number', (p) => RegExp(r'\p{N}', unicode: true).hasMatch(p)),
];

bool passwordTooLong(String p) => utf8.encode(p).length > 72;

bool passwordValid(String p) => !passwordTooLong(p) && passwordRules.every((r) => r.test(p));

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email address.';
  if (s.length > 254 || !_emailRe.hasMatch(s)) return 'Enter a valid email address, like name@example.com.';
  return null;
}
