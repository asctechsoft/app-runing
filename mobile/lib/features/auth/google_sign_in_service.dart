import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/logging/logger.dart';

/// Người dùng đóng hộp chọn tài khoản Google — không phải lỗi, không báo gì.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Lỗi phía Google/Firebase (cấu hình SHA-1 sai, Play services thiếu, mạng...).
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure(this.message);
  final String message;
  @override
  String toString() => 'GoogleSignInFailure($message)';
}

/// Cho người dùng chọn tài khoản Google và trả [AuthCredential] của Firebase.
/// Nguồn này KHÔNG tự đăng nhập Firebase: [AuthRepository] dùng credential để đăng nhập hoặc xác thực lại.
abstract class GoogleCredentialSource {
  /// Ném [GoogleSignInCancelled] khi người dùng hủy, [GoogleSignInFailure] khi lỗi.
  Future<AuthCredential> pickCredential();

  /// Đăng xuất phía Google (best-effort).
  Future<void> signOut();
}

class FirebaseGoogleCredentialSource implements GoogleCredentialSource {
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    // Android: serverClientId lấy từ default_web_client_id do plugin google-services sinh ra.
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  @override
  Future<AuthCredential> pickCredential() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null) throw const GoogleSignInFailure('Google did not return an ID token');
      return GoogleAuthProvider.credential(idToken: googleIdToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) throw const GoogleSignInCancelled();
      StrideLog.e('google', 'sign-in failed: ${e.code.name}');
      throw GoogleSignInFailure(e.code.name);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_initialized) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Đăng xuất Google là best-effort; phiên Firebase đã bị xóa ở AuthRepository.
    }
  }
}

final googleCredentialSourceProvider = Provider<GoogleCredentialSource>((ref) => FirebaseGoogleCredentialSource());

/// true khi Firebase khởi tạo thành công (có google-services.json đúng package). Override trong main().
final googleSignInAvailableProvider = Provider<bool>((ref) => false);
