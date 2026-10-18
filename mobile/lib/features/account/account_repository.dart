import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../data/settings_repository.dart';
import '../auth/auth_repository.dart';

/// Job phía server (export / deleteAccount): queued | running | succeeded | failed (H06).
class AccountJob {
  const AccountJob({required this.id, required this.kind, required this.status, this.createdAt, this.finishedAt, this.expiresAt, this.error});

  final String id;
  final String kind;
  final String status;
  final int? createdAt;
  final int? finishedAt;
  final int? expiresAt;
  final String? error;

  bool get isOpen => status == 'queued' || status == 'running';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';
  bool isExpired(int nowMs) => expiresAt != null && expiresAt! <= nowMs;

  factory AccountJob.fromJson(Map<String, Object?> j) => AccountJob(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? '',
    status: j['status'] as String? ?? 'queued',
    createdAt: (j['createdAt'] as num?)?.toInt(),
    finishedAt: (j['finishedAt'] as num?)?.toInt(),
    expiresAt: (j['expiresAt'] as num?)?.toInt(),
    error: j['error'] as String?,
  );
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(auth: ref.watch(authRepositoryProvider), settings: ref.watch(settingsRepositoryProvider), http: ref.watch(authHttpClientProvider)),
);

/// Export dữ liệu và yêu cầu xóa tài khoản qua API (H06, I07). Không bao giờ báo thành công khi server chưa xác nhận.
class AccountRepository {
  AccountRepository({required this.auth, required SettingsRepository settings, required http.Client http}) : _settings = settings, _http = http;

  final AuthRepository auth;
  final SettingsRepository _settings;
  final http.Client _http;

  ApiClient get _api => auth.api;
  static const _kExportJob = 'account.export_job';

  AccountJob _job(Object? res) {
    if (res is! Map) throw ApiException(500, 'bad_response', 'Unexpected server response');
    return AccountJob.fromJson(res.cast<String, Object?>());
  }

  Future<String?> lastExportId(String owner) => _settings.kvGet(owner, _kExportJob);

  /// Tạo job export toàn tài khoản (server trả job đang mở nếu đã có).
  Future<AccountJob> createExport(String owner) async {
    final key = 'export:${const Uuid().v4()}';
    final job = _job(await auth.authed(() => _api.post('/me/exports', idempotencyKey: key)));
    await _settings.kvSet(owner, _kExportJob, job.id);
    return job;
  }

  Future<AccountJob> getExport(String id) async => _job(await auth.authed(() => _api.get('/me/exports/$id')));

  /// Tải file zip (cần Bearer token, không phải link công khai).
  Future<Uint8List> downloadExport(String id) async {
    Future<http.Response> send() async {
      final token = await auth.tokens.accessToken();
      return _http
          .get(Uri.parse('${_api.baseUrl}/me/exports/$id/download'), headers: {if (token != null) 'Authorization': 'Bearer $token'})
          .timeout(const Duration(minutes: 2));
    }

    if (!_api.configured) throw ApiException(0, 'not_configured', 'Server is not configured for this build');
    await auth.ensureFresh();
    http.Response res;
    try {
      res = await send();
      if (res.statusCode == 401 && await auth.refresh()) res = await send();
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Request timed out');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'network', e.message);
    }
    if (res.statusCode == 200) return res.bodyBytes;
    final code = switch (res.statusCode) {
      409 => 'export_not_ready',
      410 => 'export_expired',
      404 => 'not_found',
      401 => 'unauthorized',
      _ => 'http_${res.statusCode}',
    };
    throw ApiException(res.statusCode, code, 'Download failed');
  }

  /// Xóa tài khoản: xác thực lại bằng mật khẩu rồi gửi yêu cầu. Trả job để theo dõi trạng thái thật.
  Future<AccountJob> requestDeletion(String password) async {
    await auth.reauth(password);
    return _job(await auth.authed(() => _api.post('/me/deletion')));
  }

  /// Trạng thái yêu cầu xóa gần nhất; null nếu chưa từng yêu cầu.
  Future<AccountJob?> deletionStatus() async {
    try {
      return _job(await auth.authed(() => _api.get('/me/deletion')));
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }
}

/// Thông báo lỗi cho các thao tác tài khoản.
String accountErrorMessage(Object e) {
  if (e is ApiException) {
    if (e.code == 'not_configured') return "Accounts aren't available in this build.";
    if (e.isNetwork) return "You're offline. Connect to the internet and try again.";
    switch (e.code) {
      case 'invalid_credentials':
        return 'That password is incorrect.';
      case 'reauth_required':
        return 'Confirm your password again to continue.';
      case 'export_not_ready':
        return 'Your export is still being prepared.';
      case 'export_expired':
        return 'This export has expired. Create a new one.';
      case 'rate_limited':
        return 'Too many attempts. Wait a minute and try again.';
      case 'unauthorized':
      case 'invalid_token':
        return 'Your session has expired. Log in again.';
    }
    if (e.status >= 500) return 'Something went wrong on our side. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}
