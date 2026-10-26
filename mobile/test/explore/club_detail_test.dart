import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/presentation/screens_explore/clubs_screen.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/presentation/screens_explore/explore_screen.dart';

class _FakeExploreRepository extends ExploreRepository {
  _FakeExploreRepository(this.current) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  Club current;
  int joinCalls = 0;
  int postCalls = 0;

  @override
  Future<Club> club(String id) async => current;

  @override
  Future<ClubMembership?> requestJoin(String clubId) async {
    joinCalls++;
    return const ClubMembership(role: 'member', status: MembershipStatus.pending);
  }

  @override
  Future<ExplorePage<ClubPost>> posts(String clubId, {String? cursor}) async {
    postCalls++;
    return const ExplorePage([], null);
  }

  @override
  Future<ExplorePage<ClubEvent>> events(String clubId, {String? cursor}) async => const ExplorePage([], null);
}

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
  });

  testWidgets('owner không có nút Leave club', (tester) async {
    final repo = _FakeExploreRepository(_club(const ClubMembership(role: 'owner', status: MembershipStatus.approved)));
    await pump(tester, const ClubDetailScreen(clubId: 'c1'), repo: repo);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Leave club'), findsNothing);
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
