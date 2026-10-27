import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/clubs_screen.dart';
import 'package:stride/presentation/screens_explore/explore_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';

class _FakeExploreRepository extends ExploreRepository {
  _FakeExploreRepository(this.current) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  Club current;
  int joinCalls = 0;
  int postCalls = 0;
  int archiveCalls = 0;

  @override
  Future<void> archiveClub(String clubId) async {
    archiveCalls++;
    current = Club(
      id: current.id,
      name: current.name,
      description: current.description,
      regionText: current.regionText,
      memberCount: current.memberCount,
      membership: current.membership,
      archived: true,
    );
  }

  /// Đặt để mô phỏng mạng chậm: requestJoin chờ tới khi complete.
  Completer<void>? joinGate;

  @override
  Future<Club> club(String id) async => current;

  @override
  Future<ClubMembership?> requestJoin(String clubId) async {
    joinCalls++;
    await joinGate?.future;
    return const ClubMembership(role: 'member', status: MembershipStatus.pending);
  }

  List<ClubPost> page = const [];
  final pins = <String?>[];

  @override
  Future<ExplorePage<ClubPost>> posts(String clubId, {String? cursor}) async {
    postCalls++;
    return ExplorePage(page, null);
  }

  @override
  Future<ClubPost?> post(String postId) async => _post(postId, 'Pinned rules');

  @override
  Future<void> setPinnedPost(String clubId, String? postId) async => pins.add(postId);

  @override
  Future<ExplorePage<ClubEvent>> events(String clubId, {String? cursor}) async => const ExplorePage([], null);
}

ClubPost _post(String id, String text) =>
    ClubPost(id: id, clubId: 'c1', authorId: 'someone', authorName: 'Ann', text: text, commentCount: 0, cheerCount: 0, cheeredByMe: false, createdAt: 1);

Club _club(ClubMembership? m) =>
    Club(id: 'c1', name: 'Central Park Runners', description: 'Weekly easy runs', regionText: 'New York, NY', memberCount: 246, membership: m);

void main() {
  sqfliteFfiInit();
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget screen, {ExploreRepository? repo, bool guest = false, FeatureFlags flags = const FeatureFlags()}) async {
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', if (!guest) 'user_id': 'u-me', if (!guest) 'user_email': 'x@y.z'});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
          flagsProvider.overrideWithValue(flags),
          if (repo != null) exploreRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('chưa là thành viên → Request to join → pending (khác member, không thấy feed)', (tester) async {
    final repo = _FakeExploreRepository(_club(null));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.text('Request to join'), findsOneWidget);
    expect(find.text('Feed'), findsNothing);

    await tester.tap(find.text('Request to join'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.joinCalls, 1);
    expect(find.text('Request pending'), findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.text('Request to join'), findsNothing);
    expect(find.text('Feed'), findsNothing);
    expect(repo.postCalls, 0);
  });

  testWidgets('T04: chạm đúp "Request to join" trong cùng một frame chỉ gửi một yêu cầu', (tester) async {
    final repo = _FakeExploreRepository(_club(null))..joinGate = Completer<void>();
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    await tester.tap(find.text('Request to join'));
    await tester.tap(find.text('Request to join'), warnIfMissed: false);
    repo.joinGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.joinCalls, 1);
  });

  testWidgets('pending từ server hiển thị trạng thái chờ duyệt', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'member', status: MembershipStatus.pending)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.text('Request pending'), findsOneWidget);
    expect(find.text('Leave club'), findsNothing);
  });

  testWidgets('member thấy Feed/Events và Leave club', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'member', status: MembershipStatus.approved)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Leave club'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(repo.postCalls, 1);
    // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('owner không có nút Leave club', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'owner', status: MembershipStatus.approved)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Leave club'), findsNothing);
  });

  testWidgets('TM04: owner giải tán (có xác nhận) → banner, ẩn mời/sửa/ô đăng bài và nút giải tán', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'owner', status: MembershipStatus.approved)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.byKey(const Key('club-invite')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // ô đăng bài
    await tester.tap(find.byKey(const Key('club-archive')));
    await tester.pumpAndSettle();
    expect(find.text('Close Central Park Runners?'), findsOneWidget);
    await tester.tap(find.text('Close club').last);
    await tester.pumpAndSettle();
    expect(repo.archiveCalls, 1);
    expect(find.byKey(const Key('club-archived')), findsOneWidget);
    expect(find.byKey(const Key('club-invite')), findsNothing);
    expect(find.byKey(const Key('club-edit')), findsNothing);
    expect(find.byKey(const Key('club-archive')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('TM04: bài ghim (ngoài trang đầu) hiện đầu feed có nhãn; admin ghim bài khác qua menu', (tester) async {
    final repo = _FakeExploreRepository(
      Club(
        id: 'c1',
        name: 'Central Park Runners',
        description: '',
        regionText: '',
        memberCount: 2,
        membership: const ClubMembership(role: 'admin', status: MembershipStatus.approved),
        pinnedPostId: 'old',
      ),
    )..page = [_post('p1', 'Hello'), _post('p2', 'Second')];
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    expect(texts.indexOf('Pinned rules'), lessThan(texts.indexOf('Hello')));
    expect(find.byKey(const Key('post-pinned')), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('post-p2')), matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin to top'));
    await tester.pumpAndSettle();
    expect(repo.pins, ['p2']);
  });

  testWidgets('TM04: thành viên thường không có mục ghim', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'member', status: MembershipStatus.approved)))..page = [_post('p1', 'Hello')];
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('post-p1')), matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    expect(find.text('Pin to top'), findsNothing);
    expect(find.text('Report post'), findsOneWidget);
  });

  testWidgets('TM04: admin không thấy nút giải tán', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'admin', status: MembershipStatus.approved)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.byKey(const Key('club-archive')), findsNothing);
  });

  testWidgets('khách thấy CTA đăng nhập, không gọi API', (tester) async {
    final repo = _FakeExploreRepository(_club(null));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo, guest: true);
    expect(find.text('Sign in to join clubs'), findsOneWidget);
    expect(find.text('Request to join'), findsNothing);
  });

  testWidgets('Explore hub ẩn module có flag tắt', (tester) async {
    await pump(tester, const ExploreScreen(), flags: const FeatureFlags(exploreChallenges: false));
    expect(find.text('Running clubs'), findsOneWidget);
    expect(find.text('Challenges'), findsNothing);
    expect(find.text('Discover routes'), findsOneWidget);
  });
}
