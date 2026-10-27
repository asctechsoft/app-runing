import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/badges/badges_providers.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_progress/badges_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/analytics.dart';
import 'package:stride/utils/calc/badges.dart';

Activity _a(String id, int at, double m, {ActivityType type = ActivityType.run, bool mocked = false, DistanceSource src = DistanceSource.gps}) => Activity(
  id: id,
  ownerId: 'u',
  type: type,
  status: ActivityStatus.saved,
  startedAt: at,
  tzId: 'UTC',
  tzOffsetMin: 0,
  distanceM: m,
  movingMs: 1,
  hasGps: src == DistanceSource.gps,
  distanceSource: src,
  locationMocked: mocked,
  privacy: Privacy.onlyMe,
);

void main() {
  group('TM40: tính huy hiệu', () {
    test('mốc quãng đường lấy buổi đầu tiên đạt; tổng cộng dồn theo thời gian; bỏ indoor/ước lượng/vị trí giả', () {
      final earned = evaluateBadges(
        activities: [
          _a('indoor', 1, 30000, type: ActivityType.indoorRun, src: DistanceSource.steps),
          _a('fake', 2, 30000, mocked: true),
          _a('r1', 10, 6000),
          _a('r2', 20, 11000),
          _a('r3', 30, 90000),
        ],
        longestStreak: 8,
        challenges: [(id: 'ch1', title: 'October 100K', completedAt: 99)],
      );
      final byId = {for (final b in earned) b.id: b};
      expect(byId['first5k']!.earnedAt, 10);
      expect(byId['first10k']!.earnedAt, 20);
      expect(byId['firstHalf']!.earnedAt, 30);
      expect(byId['total100km']!.earnedAt, 30);
      expect(byId.containsKey('total500km'), isFalse);
      expect(byId.containsKey('streak7'), isTrue);
      expect(byId.containsKey('streak30'), isFalse);
      expect((byId['challenge:ch1']!.title, byId['challenge:ch1']!.earnedAt), ('October 100K', 99));
    });

    test('idempotent: tính lại cùng dữ liệu → cùng tập; chỉ huy hiệu chưa thấy là "mới"', () {
      List<EarnedBadge> run() => evaluateBadges(activities: [_a('r', 1, 5000)], longestStreak: 7);
      expect(run().map((b) => b.id), run().map((b) => b.id));
      expect(newlyEarned(run(), {'first5k'}).map((b) => b.id), ['streak7']);
      expect(newlyEarned(run(), {'first5k', 'streak7'}), isEmpty);
    });

    test('độ hiếm và sự kiện analytics không chứa id', () {
      expect((BadgeKind.first5k.rarity, BadgeKind.total500km.rarity, BadgeKind.streak100.rarity), (BadgeRarity.common, BadgeRarity.rare, BadgeRarity.epic));
      final sent = <(String, Map<String, Object>?)>[];
      Analytics.sink = (n, p) => sent.add((n, p));
      addTearDown(Analytics.resetSink);
      Analytics.badgeEarned(kind: 'challenge');
      expect(sent.single.$1, 'badge_earned');
      expect(sent.single.$2, {'kind': 'challenge'});
    });

    test('repository: thử thách đã hoàn thành (bỏ chưa xong và đã rời)', () async {
      final db = FakeFirebaseFirestore();
      final repo = ExploreRepository(ready: () => true, firestore: () => db, uid: () => 'me');
      for (final (id, done, status) in [('a', 5, 'active'), ('b', null, 'active'), ('c', 7, 'left')]) {
        await db.doc('challenges/$id').set({'title': 'Ch $id'});
        await db.doc('challenges/$id/participants/me').set({'userId': 'me', 'completedAt': ?done});
        await db.doc('users/me/challengeJoins/$id').set({'status': status});
      }
      expect(await repo.myCompletedChallenges(), [(id: 'a', title: 'Ch a', completedAt: 5)]);
    });
  });

  group('TM40: tủ huy hiệu', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());

    testWidgets('đã nhận có ngày, chưa nhận có khóa + điều kiện, huy hiệu thử thách; hộp thoại báo mới', (tester) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cab = BadgeCabinet(
        earned: [
          EarnedBadge(id: 'first5k', kind: BadgeKind.first5k, earnedAt: DateTime(2026, 10, 1).millisecondsSinceEpoch),
          const EarnedBadge(id: 'streak7', kind: BadgeKind.streak7),
          const EarnedBadge(id: 'challenge:x', kind: BadgeKind.challenge, earnedAt: 1, title: 'October 100K'),
        ],
        seen: {'streak7': DateTime(2026, 10, 5).millisecondsSinceEpoch},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(sql),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            badgesProvider.overrideWith((ref) async => cab),
          ],
          child: const MaterialApp(home: BadgesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 of 8 milestones'), findsOneWidget);
      expect(find.text('First 5K'), findsOneWidget);
      expect(find.textContaining('Earned Oct 1, 2026'), findsOneWidget);
      expect(find.textContaining('Earned Oct 5, 2026'), findsOneWidget);
      expect(find.text('Reach 500 km in total.'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(6));
      expect(find.text('October 100K'), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(cab.fresh.map((b) => b.id), ['first5k', 'challenge:x']);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(onPressed: () => showBadgeEarnedDialog(context, cab.fresh), child: const Text('show')),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('badge-earned-dialog')), findsOneWidget);
      expect(find.text('First 5K'), findsOneWidget);
      expect(find.text('+1 more badge'), findsOneWidget);
    });
  });
}
