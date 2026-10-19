import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_providers.dart';
import '../../core/logging/logger.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/time/clock.dart';

/// Người dùng đăng nhập; [id] là Firebase uid.
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

  Map<String, Object?> toJson() => {'id': id, 'email': email, 'emailVerified': emailVerified, 'displayName': displayName};

  factory AuthUser.fromFirebase(User u) => authUserFromParts(uid: u.uid, email: u.email, emailVerified: u.emailVerified, displayName: u.displayName);
}

/// Mapper thuần (test được không cần Firebase). Email null → chuỗi rỗng, tên rỗng → null.
AuthUser authUserFromParts({required String uid, String? email, bool emailVerified = false, String? displayName}) {
  final name = displayName?.trim();
  return AuthUser(id: uid, email: email ?? '', emailVerified: emailVerified, displayName: (name == null || name.isEmpty) ? null : name);
}

/// Khóa `userLookup/{emailLower}`: email chuẩn hóa chữ thường, bỏ khoảng trắng.
String emailLowerOf(String email) => email.trim().toLowerCase();

/// Dữ liệu tạo `users/{uid}` lần đầu (schema: displayName, email, emailLower, createdAt).
Map<String, Object?> newUserDoc({required String email, String? displayName, required int nowMs}) => {
  'displayName': displayName ?? '',
  'email': email,
  'emailLower': emailLowerOf(email),
  'createdAt': nowMs,
};

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ready: ref.watch(firebaseReadyProvider),
    auth: () => ref.read(firebaseAuthProvider),
    firestore: () => ref.read(firestoreProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Auth qua Firebase Auth + hồ sơ trong Firestore `users/{uid}`. Không bao giờ log mật khẩu/token.
class AuthRepository {
  AuthRepository({required bool ready, required FirebaseAuth Function() auth, required FirebaseFirestore Function() firestore, required Clock clock})
    : _ready = ready,
      _authFn = auth,
      _fsFn = firestore,
      _clock = clock;

  final bool _ready;
  final FirebaseAuth Function() _authFn;
  final FirebaseFirestore Function() _fsFn;
  final Clock _clock;

  /// Firebase chưa khởi tạo (thiếu google-services.json) → UI hiển thị "Accounts aren't available" thay vì giả thành công.
  bool get available => _ready;

  FirebaseAuth get _auth {
    if (!_ready) throw ApiException(0, 'not_configured', 'Firebase is not configured for this build');
    return _authFn();
  }

  FirebaseFirestore get _fs => _fsFn();

  User _requireUser() {
    final u = _auth.currentUser;
    if (u == null) throw ApiException(401, 'unauthorized', 'Not signed in');
    return u;
  }

  /// uid hiện tại hoặc null.
  String? get uid => _ready ? _authFn().currentUser?.uid : null;

  Future<bool> hasCredentials() async => uid != null;

  /// Tạo `users/{uid}` nếu chưa có; upsert `userLookup` khi email đã xác minh (Google luôn xác minh).
  /// Best-effort: lỗi mạng không làm hỏng đăng nhập (sẽ thử lại ở lần đăng nhập sau).
  Future<void> _ensureProfileDocs(User u, {String? displayName}) async {
    try {
      final ref = _fs.collection('users').doc(u.uid);
      final snap = await ref.get();
      final name = (displayName ?? u.displayName)?.trim();
      if (!snap.exists) {
        await ref.set(newUserDoc(email: u.email ?? '', displayName: name, nowMs: _clock.nowMs()));
      }
      await _upsertLookup(u, fallbackName: snap.data()?['displayName'] as String? ?? name);
    } catch (e) {
      StrideLog.e('auth', 'ensure user doc failed: ${e is FirebaseException ? e.code : 'error'}');
    }
  }

  Future<void> _upsertLookup(User u, {String? fallbackName}) async {
    final email = u.email;
    if (email == null || email.isEmpty || !u.emailVerified) return;
    await _fs.collection('userLookup').doc(emailLowerOf(email)).set({'uid': u.uid, 'displayName': fallbackName ?? u.displayName ?? ''});
  }

  Future<AuthUser> register({required String email, required String password, String? displayName}) => guardFirebase(() async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final u = cred.user;
    if (u == null) throw ApiException(500, 'bad_response', 'Unexpected response');
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) await u.updateDisplayName(name);
    try {
      await u.sendEmailVerification();
    } catch (e) {
      StrideLog.e('auth', 'send verification failed: ${e is FirebaseException ? e.code : 'error'}');
    }
    await _ensureProfileDocs(u, displayName: name);
    return authUserFromParts(uid: u.uid, email: u.email ?? email.trim(), emailVerified: u.emailVerified, displayName: name ?? u.displayName);
  });

  Future<AuthUser> login({required String email, required String password}) => guardFirebase(() async {
    final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    final u = cred.user;
    if (u == null) throw ApiException(500, 'bad_response', 'Unexpected response');
    await _ensureProfileDocs(u);
    return AuthUser.fromFirebase(u);
  });

  /// Đăng nhập bằng credential Google (lấy từ [GoogleCredentialSource]).
  Future<AuthUser> loginWithGoogle(AuthCredential credential) => guardFirebase(() async {
    final cred = await _auth.signInWithCredential(credential);
    final u = cred.user;
    if (u == null) throw ApiException(500, 'bad_response', 'Unexpected response');
    await _ensureProfileDocs(u);
    return AuthUser.fromFirebase(u);
  });

  /// Firebase không tiết lộ email có tồn tại hay không; `user-not-found` cũng coi như thành công để không lộ.
  Future<void> forgotPassword(String email) => guardFirebase(() async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found') rethrow;
    }
  });

  /// [token] là `oobCode` trong link đặt lại mật khẩu.
  Future<void> resetPassword({required String token, required String newPassword}) =>
      guardFirebase(() => _auth.confirmPasswordReset(code: token, newPassword: newPassword));

  /// [token] là `oobCode` trong link xác minh email.
  Future<AuthUser> verifyEmail(String token) => guardFirebase(() async {
    final info = await _auth.checkActionCode(token);
    await _auth.applyActionCode(token);
    final u = _auth.currentUser;
    if (u != null) {
      await u.reload();
      final fresh = _auth.currentUser ?? u;
      try {
        await _upsertLookup(fresh);
      } catch (_) {}
      return AuthUser.fromFirebase(fresh);
    }
    return authUserFromParts(uid: '', email: info.data['email'] as String?, emailVerified: true);
  });

  Future<void> resendVerification() => guardFirebase(() => _requireUser().sendEmailVerification());

  /// Xác thực lại bằng mật khẩu trước thao tác nhạy cảm (xóa tài khoản).
  Future<void> reauth(String password) => guardFirebase(() async {
    final u = _requireUser();
    final email = u.email;
    if (email == null) throw ApiException(401, 'reauth_required', 'No email on account');
    await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: email, password: password));
  });

  /// Xác thực lại bằng credential Google cho tài khoản không có mật khẩu.
  Future<void> reauthWithGoogle(AuthCredential credential) => guardFirebase(() => _requireUser().reauthenticateWithCredential(credential));

  /// Hồ sơ trên Firestore: `{user, profile}`. `profile` null nếu chưa có.
  Future<Map<String, Object?>> me() => guardFirebase(() async {
    final u = _requireUser();
    final snap = await _fs.collection('users').doc(u.uid).get();
    final data = snap.data() ?? const <String, Object?>{};
    final user = AuthUser.fromFirebase(u).toJson();
    final created = data['createdAt'];
    if (created is num) user['createdAt'] = created.toInt();
    final profile = data['profile'];
    return {'user': user, 'profile': profile is Map ? profile.cast<String, Object?>() : null};
  });

  /// Đăng xuất Firebase; không ném lỗi (phiên cục bộ luôn bị xóa ở tầng gọi).
  Future<void> logout() async {
    if (!_ready) return;
    try {
      await _authFn().signOut();
    } catch (_) {
      StrideLog.e('auth', 'sign out failed');
    }
  }
}

/// Ngữ cảnh lỗi để chọn câu thông báo cụ thể (E02).
enum AuthAction { login, register, forgot, reset, verify, reauth, other }

/// Map lỗi → thông báo cụ thể cho người dùng; không lộ chi tiết kỹ thuật.
String authErrorMessage(Object error, AuthAction action) {
  if (error is FirebaseException) error = mapFirebaseError(error);
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
    case 'reauth_required':
      return 'Confirm your password again to continue.';
    case 'account-exists-with-different-credential':
      return 'An account with this email already exists. Log in with your password first.';
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
      return "Sign in with Google isn't available yet. Use your email instead.";
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

/// Quy tắc mật khẩu của app (chặt hơn Firebase ≥ 6): ≥ 8 ký tự, có chữ cái, có chữ số, ≤ 72 byte.
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
