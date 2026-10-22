import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/repository/auth_repository.dart';

void main() {
  group('AuthRepository khi Firebase chưa sẵn sàng (E02)', () {
    late AuthRepository repo;
    setUp(() {
      repo = AuthRepository(
        ready: false,
        auth: () => throw StateError('không được đụng FirebaseAuth'),
        firestore: () => throw StateError('không được đụng Firestore'),
        clock: FakeClock(),
      );
    });

    test('available=false, uid=null, không có credentials', () async {
      expect(repo.available, isFalse);
      expect(repo.uid, isNull);
      expect(await repo.hasCredentials(), isFalse);
    });
    test('login/register/me không giả thành công: ném not_configured', () async {
      Matcher notConfigured() => throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_configured'));
      await expectLater(repo.login(email: 'a@b.co', password: 'x'), notConfigured());
      await expectLater(repo.register(email: 'a@b.co', password: 'abcdefg1'), notConfigured());
      await expectLater(repo.me(), notConfigured());
    });
    test('logout không ném lỗi', () async {
      await repo.logout();
    });
  });

  group('Mapper user / tài liệu users', () {
    test('authUserFromParts: email null → rỗng, tên rỗng → null, cắt khoảng trắng', () {
      final u = authUserFromParts(uid: 'u1', email: null, displayName: '  ');
      expect(u.id, 'u1');
      expect(u.email, '');
      expect(u.displayName, isNull);
      expect(authUserFromParts(uid: 'u1', email: 'a@b.co', emailVerified: true, displayName: ' An ').displayName, 'An');
    });
    test('emailLowerOf và newUserDoc đúng schema', () {
      expect(emailLowerOf('  Foo@Bar.COM '), 'foo@bar.com');
      expect(newUserDoc(email: 'Foo@Bar.com', displayName: 'An', nowMs: 5), {
        'displayName': 'An',
        'email': 'Foo@Bar.com',
        'emailLower': 'foo@bar.com',
        'createdAt': 5,
      });
      expect(newUserDoc(email: 'a@b.co', nowMs: 1)['displayName'], '');
    });
    test('AuthUser toJson/fromJson khứ hồi', () {
      const u = AuthUser(id: 'u', email: 'a@b.co', emailVerified: true, displayName: 'An');
      final back = AuthUser.fromJson(u.toJson());
      expect(back.id, 'u');
      expect(back.emailVerified, isTrue);
      expect(back.displayName, 'An');
    });
  });

  group('mapFirebaseError', () {
    ApiException m(String code) => mapFirebaseError(FirebaseAuthException(code: code, message: 'x'));
    test('sinh đúng code mà authErrorMessage hiểu', () {
      expect(m('wrong-password').code, 'invalid_credentials');
      expect(m('invalid-credential').code, 'invalid_credentials');
      expect(m('email-already-in-use').code, 'email_taken');
      expect(m('weak-password').code, 'validation_error');
      expect(m('too-many-requests').code, 'rate_limited');
      expect(m('user-disabled').code, 'account_disabled');
      expect(m('expired-action-code').code, 'invalid_token');
      expect(m('requires-recent-login').code, 'reauth_required');
      expect(m('network-request-failed').isNetwork, isTrue);
    });
    test('FirebaseException (Firestore) cũng được map', () {
      expect(mapFirebaseError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')).status, 403);
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
    test('lỗi Firebase thô cũng ra thông báo thân thiện', () {
      expect(authErrorMessage(FirebaseAuthException(code: 'wrong-password'), AuthAction.login), 'Email or password is incorrect.');
    });
    test('các code mới từ Firebase', () {
      expect(authErrorMessage(ApiException(401, 'reauth_required', 'x'), AuthAction.reauth), contains('Confirm your password'));
      expect(authErrorMessage(ApiException(403, 'account_disabled', 'x'), AuthAction.login), contains('deleted'));
      expect(authErrorMessage(ApiException(500, 'account-exists-with-different-credential', 'x'), AuthAction.login), contains('already exists'));
    });
    test('validation dùng message đầu tiên nếu có, nếu không dùng câu chung', () {
      final e = ApiException(422, 'validation_error', 'Invalid input', [
        {'path': 'password', 'message': 'Password must contain a number'},
      ]);
      expect(authErrorMessage(e, AuthAction.register), 'Password must contain a number.');
      expect(authErrorMessage(ApiException(400, 'validation_error', 'x'), AuthAction.register), contains('not valid'));
    });
    test('không cấu hình', () {
      expect(authErrorMessage(ApiException(0, 'not_configured', 'x'), AuthAction.login), "Accounts aren't available in this build.");
    });
    test('5xx không lộ chi tiết kỹ thuật', () {
      expect(authErrorMessage(ApiException(500, 'internal_error', 'stack...'), AuthAction.login), 'Something went wrong on our side. Please try again.');
    });
  });

  group('Quy tắc mật khẩu của app', () {
    test('≥ 8 ký tự, có chữ cái, có chữ số', () {
      expect(passwordValid('abcdefg1'), isTrue);
      expect(passwordValid('abcdefgh'), isFalse);
      expect(passwordValid('12345678'), isFalse);
      expect(passwordValid('abc12'), isFalse);
      expect(passwordValid('mậtkhẩu9'), isTrue, reason: 'chữ cái Unicode được tính');
    });
    test('không có quy tắc ký tự đặc biệt', () {
      expect(passwordRules.map((r) => r.label), ['At least 8 characters', 'Includes a letter', 'Includes a number']);
    });
    test('quá 72 byte bị từ chối', () {
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
