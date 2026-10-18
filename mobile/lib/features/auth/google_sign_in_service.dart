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

/// Lấy Firebase ID token sau khi người dùng chọn tài khoản Google.
/// Backend verify token này rồi cấp JWT STRIDE (auth email/password vẫn giữ nguyên).
abstract class GoogleIdTokenSource {
  /// Ném [GoogleSignInCancelled] khi người dùng hủy, [GoogleSignInFailure] khi lỗi.
  Future<String> signInAndGetIdToken();
  Future<void> signOut();
}

class FirebaseGoogleIdTokenSource implements GoogleIdTokenSource {
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    // Android: serverClientId lấy từ default_web_client_id do plugin google-services sinh ra.
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  @override
  Future<String> signInAndGetIdToken() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null) throw const GoogleSignInFailure('Google did not return an ID token');
      final cred = await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: googleIdToken));
      final token = await cred.user?.getIdToken(true);
      if (token == null) throw const GoogleSignInFailure('Firebase did not return an ID token');
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) throw const GoogleSignInCancelled();
      StrideLog.e('google', 'sign-in failed: ${e.code.name}');
      throw GoogleSignInFailure(e.code.name);
    } on FirebaseAuthException catch (e) {
      StrideLog.e('google', 'firebase sign-in failed: ${e.code}');
      throw GoogleSignInFailure(e.code);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (_initialized) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Đăng xuất Google là best-effort; phiên STRIDE đã bị xóa ở AuthRepository.
    }
  }
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>((ref) => FirebaseGoogleIdTokenSource());

/// true khi Firebase khởi tạo thành công (có google-services.json đúng package). Override trong main().
final googleSignInAvailableProvider = Provider<bool>((ref) => false);
