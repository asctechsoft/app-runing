import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show AuthCredential;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/community/community_providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_community/share_to_community.dart';
import 'package:stride/repository/community_repository.dart';
import 'package:stride/services/application/google_sign_in_service.dart';

class _CancelledGoogle implements GoogleCredentialSource {
  int calls = 0;
  @override
  Future<AuthCredential> pickCredential() async {
    calls++;
    throw const GoogleSignInCancelled();
  }

  @override
  Future<void> signOut() async {}
}

/// Chia sẻ buổi chạy lên Cộng đồng: luôn xác nhận trước; khách phải đăng nhập Google; hủy thì không đăng gì.
void main() {
  late FakeFirebaseFirestore db;
  late _CancelledGoogle google;

  final saved = Activity(
    id: 'a1',
    ownerId: 'alice',
    type: ActivityType.run,
    status: ActivityStatus.saved,
    startedAt: 1,
    tzId: 'UTC',
    tzOffsetMin: 0,
    distanceM: 5000,
    movingMs: 1800000,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    google = _CancelledGoogle();
  });

  Future<void> pump(WidgetTester tester, {required bool signedIn}) async {
    final repo = CommunityRepository(ready: () => true, firestore: () => db, uid: () => signedIn ? 'alice' : null, displayName: () => 'Alice');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communitySignedInProvider.overrideWithValue(signedIn),
          communityRepositoryProvider.overrideWithValue(repo),
          googleCredentialSourceProvider.overrideWithValue(google),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(onPressed: () => shareRunToCommunity(context, ref, saved), child: const Text('share')),
            ),
          ),
        ),
      ),
    );
  }

  Future<int> posts() async => (await db.collection('communityPosts').get()).docs.length;

  testWidgets('đã đăng nhập: xác nhận rồi đăng, báo thành công sau khi ghi xong', (tester) async {
    await pump(tester, signedIn: true);
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(find.text('Share this run?'), findsOneWidget);
    expect(find.textContaining('No map or location is shared'), findsOneWidget);
    expect(await posts(), 0, reason: 'chưa xác nhận thì chưa đăng');

    await tester.enterText(find.byType(TextField), '  Vui quá!  ');
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(await posts(), 1);
    expect((await db.collection('communityPosts').get()).docs.single.data()['text'], 'Vui quá!');
    expect(find.text('Shared to the community'), findsOneWidget);
  });

  testWidgets('đã đăng nhập: bấm Hủy ở hộp xác nhận → không đăng', (tester) async {
    await pump(tester, signedIn: true);
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await posts(), 0);
    expect(find.text('Shared to the community'), findsNothing);
  });

  testWidgets('khách: hộp xác nhận yêu cầu đăng nhập Google; hủy chọn tài khoản → không đăng, không báo thành công', (tester) async {
    await pump(tester, signedIn: false);
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sharing needs an account'), findsOneWidget);
    await tester.tap(find.text('Log in and share'));
    await tester.pumpAndSettle();
    expect(google.calls, 1);
    expect(await posts(), 0);
    expect(find.text('Shared to the community'), findsNothing);
  });
}
