import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/presentation/screens_explore/challenge_results_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

const _h = 3600 * 1000;

/// TM41: màn kết quả — bục top 3 chỉ gồm người bật hiện tên, đội thắng, kết quả của tôi, khiếu nại; tạm thời trước khi khóa.
void main() {
  sqfliteFfiInit();
  late AppDatabase sql;
  setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
  tearDown(() => sql.close());
  const end = 1000 * _h;

  Future<FakeFirebaseFirestore> pump(WidgetTester tester, int now) async {
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'me', 'user_email': 'x@y.z'});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = FakeFirebaseFirestore();
    await db.doc('challenges/k').set({'title': 'October 50K', 'metric': 'count', 'target': 10, 'startsAt': 0, 'endsAt': end, 'clubId': 'c1'});
    await db.doc('challenges/k/teams/red').set({'name': 'Red', 'color': 2});
    await db.doc('challenges/k/teams/blue').set({'name': 'Blue', 'color': 1});
    Future<void> p(String id, double v, int t, {bool optIn = true, String? team, int? done}) => db.doc('challenges/k/participants/$id').set({
      'userId': id,
      'displayName': id.toUpperCase(),
      'leaderboardOptIn': optIn,
      'progressValue': v,
      'progressUpdatedAt': t,
      'teamId': ?team,
      'completedAt': ?done,
    });
    await p('ann', 12, 1, team: 'red', done: 5);
    await p('bo', 9, 2, team: 'blue');
    await p('cy', 9, 1, team: 'blue');
    await p('hid', 99, 1, optIn: false, team: 'red');
    await p('me', 4, 3);
    final repo = ExploreRepository(ready: () => true, firestore: () => db, uid: () => 'me', nowMs: () => now);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(sql),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
          exploreRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FakeClock(now)),
        ],
        child: const MaterialApp(home: ChallengeResultsScreen(challengeId: 'k')),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('đã khóa: top 3 người hiện tên (đồng điểm ai đạt trước xếp trên), đội thắng theo trung bình, kết quả của tôi, khiếu nại', (tester) async {
    final db = await pump(tester, end + 49 * _h);
    expect(find.byKey(const Key('results-final')), findsOneWidget);
    expect(find.text('ANN'), findsOneWidget);
    expect(find.text('HID'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Place 2: CY')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Place 3: BO')), findsOneWidget);
    // Red: (12 + 99) / 2 = 55.5 > Blue: 9.
    expect(find.descendant(of: find.byKey(const Key('results-team')), matching: find.text('Red')), findsOneWidget);
    expect(find.text('Goal not reached this time.'), findsOneWidget);
    expect(find.text('Your rank: #4'), findsOneWidget);
    // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.byKey(const Key('results-appeal')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('appeal-reason')), 'HID used a car');
    await tester.pump();
    await tester.tap(find.byKey(const Key('appeal-send')));
    await tester.pumpAndSettle();
    final reports = await db.collection('reports').get();
    expect((reports.docs.single.data()['targetType'], reports.docs.single.data()['targetId']), ('challenge_result', 'k'));
  });

  testWidgets('trong thời gian chờ đồng bộ: kết quả tạm thời', (tester) async {
    await pump(tester, end + 5 * _h);
    expect(find.byKey(const Key('results-provisional')), findsOneWidget);
  });
}
