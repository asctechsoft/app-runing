import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/core/theme/stride_theme.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/features/auth/auth_flow.dart';
import 'package:stride/features/auth/auth_repository.dart';
import 'package:stride/features/auth/google_sign_in_button.dart';
import 'package:stride/features/auth/google_sign_in_service.dart';

class _FakeGoogle implements GoogleCredentialSource {
  _FakeGoogle(this.result);
  final Object result; // AuthCredential hoặc exception
  int calls = 0;
  @override
  Future<AuthCredential> pickCredential() async {
    calls++;
    if (result is AuthCredential) return result as AuthCredential;
    throw result;
  }

  @override
  Future<void> signOut() async {}
}

/// Repository "chưa cấu hình": mọi lệnh gọi Firebase đều ném StateError → test bắt được việc lỡ gọi.
AuthRepository _unusedRepo() => AuthRepository(
  ready: false,
  auth: () => throw StateError('không được gọi Firebase'),
  firestore: () => throw StateError('không được gọi Firestore'),
  clock: FakeClock(),
);

void main() {
  test('lỗi phía Google có thông báo riêng', () {
    expect(googleSignInErrorMessage(const GoogleSignInFailure('network_error')), contains("Couldn't sign in with Google"));
  });

  test('lỗi Firebase khi đăng nhập Google đi qua authErrorMessage', () {
    expect(googleSignInErrorMessage(ApiException(0, 'network', 'x')), contains("You're offline"));
    expect(googleSignInErrorMessage(ApiException(500, 'account-exists-with-different-credential', 'x')), contains('already exists'));
  });

  testWidgets('hủy chọn tài khoản → không đăng nhập Firebase, không báo lỗi', (tester) async {
    final fake = _FakeGoogle(const GoogleSignInCancelled());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [googleCredentialSourceProvider.overrideWithValue(fake), authRepositoryProvider.overrideWithValue(_unusedRepo())],
        child: MaterialApp(
          theme: buildStrideTheme(),
          home: const Scaffold(body: Center(child: GoogleSignInButton())),
        ),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });
}
