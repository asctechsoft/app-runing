import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show AuthCredential;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/controller/community/community_providers.dart';
import 'package:stride/controller/providers.dart';
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

  Future<void> pump(WidgetTester tester, {required bool signedIn, Widget? child}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = CommunityRepository(ready: () => true, firestore: () => db, uid: () => signedIn ? 'alice' : null, displayName: () => 'Alice');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          communitySignedInProvider.overrideWithValue(signedIn),
          communityRepositoryProvider.overrideWithValue(repo),
          googleCredentialSourceProvider.overrideWithValue(google),
        ],
        child: MaterialApp(
          home: Scaffold(
            body:
                child ??
                Consumer(
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
    expect(find.textContaining('No exact location is shared'), findsOneWidget);
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

  testWidgets('chia sẻ xong thì nút đổi thành Ngừng chia sẻ; ngừng chia sẻ xóa bài mềm và gỡ ảnh tuyến đường', (tester) async {
    await pump(tester, signedIn: true, child: CommunityShareButton(activity: saved));
    // Bài đã đăng từ trước kèm ảnh: ghi thẳng vào Firestore giả và đăng ký là bài của buổi a1.
    await db.doc('communityPosts/p1').set({
      'authorId': 'alice',
      'authorName': 'Alice',
      'text': '',
      'createdAt': 1,
      'likeCount': 0,
      'deletedAt': null,
      'activity': {'type': 'run', 'startedAt': 1, 'movingMs': 1, 'distanceEstimated': false},
      'image': 'AAAA',
    });
    final container = ProviderScope.containerOf(tester.element(find.byType(CommunityShareButton)));
    await tester.runAsync(() => container.read(communitySharesProvider.notifier).record('a1', 'p1'));
    await tester.pump();
    expect(find.text('Stop sharing to community'), findsOneWidget);

    await tester.tap(find.text('Stop sharing to community'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sharing this run?'), findsOneWidget);
    await tester.tap(find.text('Stop sharing').last);
    await tester.pumpAndSettle();

    final d = (await db.doc('communityPosts/p1').get()).data()!;
    expect(d['deletedAt'], isNotNull);
    expect(d.containsKey('image'), isFalse, reason: 'ngừng chia sẻ phải xóa luôn ảnh tuyến đường');
    expect(container.read(communitySharesProvider), isEmpty);
    expect(find.text('Stopped sharing'), findsOneWidget);
    expect(find.text('Share to community'), findsOneWidget);
  });
}
