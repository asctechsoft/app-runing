import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/community/community_providers.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_community/community_screen.dart';
import 'package:stride/repository/community_repository.dart';
import 'package:stride/services/application/firebase_providers.dart';
import 'package:stride/utils/formatters.dart';

/// Cộng đồng chỉ cho người đã đăng nhập xem (khách thấy lời mời đăng nhập Google) và chỉ thả tim được.
void main() {
  late FakeFirebaseFirestore db;
  const now = 1700000000000;

  Activity act() => Activity(
    id: 'a1',
    ownerId: 'alice',
    type: ActivityType.walk,
    status: ActivityStatus.saved,
    startedAt: now,
    tzId: 'UTC',
    tzOffsetMin: 0,
    distanceM: 3000,
    movingMs: 1800000,
  );

  CommunityRepository repoFor(String? uid) =>
      CommunityRepository(ready: () => true, firestore: () => db, uid: () => uid, displayName: () => 'Alice', nowMs: () => now);

  setUp(() => db = FakeFirebaseFirestore());

  Future<void> pump(WidgetTester tester, {required bool signedIn, String uid = 'bob'}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        communitySignedInProvider.overrideWithValue(signedIn),
        communityRepositoryProvider.overrideWithValue(repoFor(signedIn ? uid : null)),
        currentUidProvider.overrideWithValue(signedIn ? uid : null),
        firebaseReadyProvider.overrideWithValue(true),
        flagsProvider.overrideWithValue(const FeatureFlags(authGoogle: true)),
        formatProvider.overrideWithValue(StrideFormat(locale: 'en_US')),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('khách: thấy lời mời đăng nhập Google, không thấy bài', (tester) async {
    await repoFor('alice').publish(act());
    await pump(tester, signedIn: false);
    expect(find.text('Log in to see the community'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('đã đăng nhập: thấy bài, thả tim tăng rồi bỏ tim giảm', (tester) async {
    final p = await repoFor('alice').publish(act());
    await pump(tester, signedIn: true);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.textContaining('3.00 km'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(find.text('1'), findsOneWidget, reason: 'cập nhật ngay (lạc quan)');
    await tester.pump(const Duration(milliseconds: 300));
    expect((await db.doc('communityPosts/${p.id}/likes/bob').get()).exists, isTrue);
    expect((await db.doc('communityPosts/${p.id}').get()).data()!['likeCount'], 1);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0'), findsOneWidget);
    expect((await db.doc('communityPosts/${p.id}/likes/bob').get()).exists, isFalse);
  });

  testWidgets('đã đăng nhập, chưa có bài → trạng thái rỗng', (tester) async {
    await pump(tester, signedIn: true);
    expect(find.text('No shared runs yet'), findsOneWidget);
  });

  testWidgets('menu bài: tác giả chỉ thấy Xóa; người khác thấy Báo cáo/Chặn, không thấy Xóa', (tester) async {
    await repoFor('alice').publish(act());
    await pump(tester, signedIn: true, uid: 'bob');
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Report user'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tác giả: menu chỉ có Xóa, xóa xong bài biến mất', (tester) async {
    await repoFor('alice').publish(act());
    await pump(tester, signedIn: true, uid: 'alice');
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Report post'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Post deleted'), findsOneWidget);
  });

  testWidgets('chặn người đăng: bài của họ biến mất ngay và ghi vào danh sách chặn', (tester) async {
    await repoFor('alice').publish(act());
    await pump(tester, signedIn: true, uid: 'bob');
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect((await db.doc('users/bob/blocks/alice').get()).exists, isTrue);
  });

  testWidgets('phân trang: có nút Tải thêm khi còn trang, bấm thì nối thêm bài cũ hơn', (tester) async {
    for (var i = 0; i < communityPageSize + 3; i++) {
      await CommunityRepository(
        ready: () => true,
        firestore: () => db,
        uid: () => 'alice',
        displayName: () => 'Alice $i',
        nowMs: () => now + i * 1000,
      ).publish(act());
    }
    await pump(tester, signedIn: true);
    expect(find.text('Load more'), findsOneWidget);
    expect(find.textContaining('Alice 0'), findsNothing, reason: 'bài cũ nhất chưa được tải');
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsNothing);
    await tester.scrollUntilVisible(find.text('Alice 0'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('Alice 0'), findsOneWidget);
  });
}
