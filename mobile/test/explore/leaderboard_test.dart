import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/leaderboard_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';

LeaderboardEntry _e(String id, double v, int t) => LeaderboardEntry(userId: id, displayName: id, value: v, updatedAt: t);

class _FakeRepo extends ExploreRepository {
  _FakeRepo(this.board) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  ChallengeLeaderboard board;
  final optIns = <bool>[];

  @override
  Future<Challenge> challenge(String id) async =>
      Challenge.fromDoc(id, {'title': '100 km in October', 'metric': 'count', 'target': 10, 'startsAt': 0, 'endsAt': 1});

  @override
  Future<ChallengeLeaderboard> challengeLeaderboard(String id) async => board;

  @override
  Future<void> setLeaderboardOptIn(String id, bool on) async {
    optIns.add(on);
    final me = board.me!;
    board = ChallengeLeaderboard(
      entries: rankLeaderboard([...board.entries, me]),
      me: me.withRank(rankLeaderboard([...board.entries, me]).firstWhere((e) => e.userId == me.userId).rank),
      optedIn: on,
      joined: true,
    );
  }
}

void main() {
  group('TM30: xếp hạng', () {
    test('điểm cao trước; bằng điểm → ai đạt trước xếp trên', () {
      final r = rankLeaderboard([_e('a', 10, 50), _e('b', 20, 90), _e('c', 10, 40)]);
      expect(r.map((e) => (e.userId, e.rank)), [('b', 1), ('c', 2), ('a', 3)]);
    });

    test('ẩn người bị chặn nhưng giữ nguyên hạng thật của người khác', () {
      final r = rankLeaderboard([_e('a', 30, 1), _e('blocked', 20, 1), _e('c', 10, 1)], hidden: {'blocked'});
      expect(r.map((e) => (e.userId, e.rank)), [('a', 1), ('c', 3)]);
    });
  });

  group('widget', () {
    sqfliteFfiInit();
    late AppDatabase db;
    setUp(() async => db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => db.close());

    Future<void> pump(WidgetTester tester, ExploreRepository repo) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'me', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: ChallengeLeaderboardScreen(challengeId: 'ch1')),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('đang ẩn: thấy banner + công tắc; bật → hiện hạng của tôi và dòng "You"', (tester) async {
      final repo = _FakeRepo(
        ChallengeLeaderboard(entries: rankLeaderboard([_e('ann', 8, 1), _e('bo', 5, 1)]), me: _e('me', 6, 2), optedIn: false, joined: true),
      );
      await pump(tester, repo);
      expect(find.text('You’re hidden from the leaderboard'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('You'), findsNothing);

      await tester.tap(find.byKey(const Key('leaderboard-optin')));
      await tester.pumpAndSettle();
      expect(repo.optIns, [true]);
      expect(find.text('Your rank: #2'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('You’re hidden from the leaderboard'), findsNothing);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('chưa tham gia và bảng rỗng: trạng thái rỗng, không có công tắc', (tester) async {
      await pump(tester, _FakeRepo(const ChallengeLeaderboard(entries: [], me: null, optedIn: false, joined: false)));
      expect(find.text('Join the challenge to appear on the leaderboard.'), findsOneWidget);
      expect(find.text('No one on the leaderboard yet'), findsOneWidget);
      expect(find.byKey(const Key('leaderboard-optin')), findsNothing);
    });
  });
}
