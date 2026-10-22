import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lỗi thống nhất cho mọi tầng dữ liệu. Giữ dạng {status, code, message} của API cũ để UI/mapper hiện có không đổi:
/// 0 = mất mạng/không cấu hình, 401 = chưa đăng nhập/hết phiên, 403 = không đủ quyền, 404 = không có,
/// 409 = xung đột, 429 = quá tải, 5xx = lỗi phía dịch vụ.
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

/// Đổi lỗi Firebase (Firestore/Auth) sang [ApiException]. Không bao giờ chứa mật khẩu/token.
ApiException mapFirebaseError(Object e) {
  if (e is ApiException) return e;
  if (e is FirebaseException) {
    final msg = e.message ?? e.code;
    switch (e.code) {
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return ApiException(0, 'network', msg);
      case 'unauthenticated':
      case 'user-token-expired':
      case 'user-not-found':
      case 'invalid-user-token':
        return ApiException(401, 'unauthorized', msg);
      case 'requires-recent-login':
        return ApiException(401, 'reauth_required', msg);
      case 'permission-denied':
        return ApiException(403, 'forbidden', msg);
      case 'not-found':
        return ApiException(404, 'not_found', msg);
      case 'already-exists':
      case 'aborted':
      case 'failed-precondition':
        return ApiException(409, e.code.replaceAll('-', '_'), msg);
      case 'resource-exhausted':
      case 'too-many-requests':
        return ApiException(429, 'rate_limited', msg);
      case 'invalid-argument':
        return ApiException(400, 'validation_error', msg);
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return ApiException(401, 'invalid_credentials', msg);
      case 'email-already-in-use':
        return ApiException(409, 'email_taken', msg);
      case 'weak-password':
      case 'invalid-email':
        return ApiException(400, 'validation_error', msg);
      case 'user-disabled':
        return ApiException(403, 'account_disabled', msg);
      case 'invalid-action-code':
      case 'expired-action-code':
        return ApiException(401, 'invalid_token', msg);
    }
    return ApiException(500, e.code, msg);
  }
  return ApiException(500, 'error', e.toString());
}

/// Chạy [f] và chuẩn hóa mọi lỗi Firebase thành [ApiException].
Future<T> guardFirebase<T>(Future<T> Function() f) async {
  try {
    return await f();
  } on ApiException {
    rethrow;
  } on FirebaseException catch (e) {
    throw mapFirebaseError(e);
  }
}
