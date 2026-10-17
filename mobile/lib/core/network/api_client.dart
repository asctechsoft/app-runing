import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../logging/logger.dart';

/// Lỗi API theo error envelope {error:{code,message,details}} (C06).
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details]);
  final int status;
  final String code;
  final String message;
  final Object? details;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;
  bool get isNotFound => status == 404;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Lưu token trong kho bảo mật hệ thống (E02). Không ghi token vào log.
abstract class TokenStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> save({required String access, required String refresh});
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> accessToken() => _s.read(key: 'access_token');
  @override
  Future<String?> refreshToken() => _s.read(key: 'refresh_token');
  @override
  Future<void> save({required String access, required String refresh}) async {
    await _s.write(key: 'access_token', value: access);
    await _s.write(key: 'refresh_token', value: refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: 'access_token');
    await _s.delete(key: 'refresh_token');
  }
}

class MemoryTokenStore implements TokenStore {
  String? _a;
  String? _r;
  @override
  Future<String?> accessToken() async => _a;
  @override
  Future<String?> refreshToken() async => _r;
  @override
  Future<void> save({required String access, required String refresh}) async {
    _a = access;
    _r = refresh;
  }

  @override
  Future<void> clear() async => _a = _r = null;
}

/// HTTP client JSON có tự refresh token một lần khi 401.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client, this.timeout = const Duration(seconds: 20)}) : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  final Duration timeout;
  Future<bool>? _refreshing;

  /// Gọi khi refresh thất bại (phiên hết hạn) để app đưa về màn đăng nhập.
  void Function()? onSessionExpired;

  bool get configured => baseUrl.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Object?> get(String path, {Map<String, String>? query, bool auth = true}) => _send('GET', path, query: query, auth: auth);
  Future<Object?> post(String path, {Object? body, bool auth = true, String? idempotencyKey}) =>
      _send('POST', path, body: body, auth: auth, idempotencyKey: idempotencyKey);
  Future<Object?> put(String path, {Object? body, String? idempotencyKey}) => _send('PUT', path, body: body, idempotencyKey: idempotencyKey);
  Future<Object?> patch(String path, {Object? body, String? idempotencyKey}) => _send('PATCH', path, body: body, idempotencyKey: idempotencyKey);
  Future<Object?> delete(String path, {String? idempotencyKey}) => _send('DELETE', path, idempotencyKey: idempotencyKey);

  /// Upload thô (ảnh, track chunk).
  Future<Object?> putBytes(String urlOrPath, List<int> bytes, {required String contentType, Map<String, String>? headers}) async {
    final uri = urlOrPath.startsWith('http') ? Uri.parse(urlOrPath) : _uri(urlOrPath);
    final token = await tokens.accessToken();
    try {
      final res = await _http
          .put(uri, body: bytes, headers: {'Content-Type': contentType, 'Authorization': ?(token == null ? null : 'Bearer $token'), ...?headers})
          .timeout(timeout);
      return _decode(res);
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Request timed out');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'network', e.message);
    }
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    String? idempotencyKey,
    bool retried = false,
  }) async {
    if (!configured) throw ApiException(0, 'not_configured', 'Server is not configured for this build');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (auth) {
      final t = await tokens.accessToken();
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Request timed out');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'network', e.message);
    } catch (e) {
      throw ApiException(0, 'network', e.toString());
    }
    if (res.statusCode == 401 && auth && !retried) {
      if (await _refresh()) return _send(method, path, query: query, body: body, auth: auth, idempotencyKey: idempotencyKey, retried: true);
      onSessionExpired?.call();
    }
    return _decode(res);
  }

  Object? _decode(http.Response res) {
    Object? json;
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(res.body);
      } catch (_) {
        json = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final err = json is Map ? json['error'] : null;
    final e = ApiException(
      res.statusCode,
      err is Map ? (err['code'] as String? ?? 'error') : 'http_${res.statusCode}',
      err is Map ? (err['message'] as String? ?? 'Request failed') : 'Request failed',
      err is Map ? err['details'] : null,
    );
    StrideLog.d('api', '${res.request?.method} ${res.request?.url.path} -> ${res.statusCode} ${e.code}');
    throw e;
  }

  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final rt = await tokens.refreshToken();
        if (rt == null) return false;
        final res = await _http
            .post(_uri('/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': rt}))
            .timeout(timeout);
        if (res.statusCode != 200) {
          await tokens.clear();
          return false;
        }
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        await tokens.save(access: j['accessToken'] as String, refresh: j['refreshToken'] as String);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }
}
