import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/challenge_teams.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

const _h = 3600 * 1000;
const _red = ChallengeTeam(id: 'red', name: 'Red', color: 2);
const _blue = ChallengeTeam(id: 'blue', name: 'Blue', color: 1);
const _green = ChallengeTeam(id: 'green', name: 'Green', color: 0);

TeamMemberProgress _p(String u, String t, double v) => TeamMemberProgress(userId: u, teamId: t, value: v);

void main() {
  group('TM32: logic', () {
    test('điểm đội = trung bình mỗi người; đội đông không tự thắng; bằng điểm → đội đông hơn; đội trống cuối', () {
      final s = computeTeamStandings([_red, _blue, _green], [_p('a', 'red', 30), _p('b', 'red', 10), _p('c', 'red', 20), _p('d', 'blue', 25)]);
      expect(s.map((x) => (x.team.id, x.rank, x.average, x.members)), [('blue', 1, 25.0, 1), ('red', 2, 20.0, 3), ('green', 3, 0.0, 0)]);
      final tie = computeTeamStandings([_red, _blue], [_p('a', 'red', 10), _p('b', 'blue', 10)]);
      expect(tie.map((x) => x.rank), [1, 1]);
      final tie2 = computeTeamStandings([_red, _blue], [_p('a', 'red', 10), _p('b', 'red', 10), _p('c', 'blue', 10)]);
      expect(tie2.map((x) => (x.team.id, x.rank)), [('red', 1), ('blue', 2)]);
    });

    test('chọn/đổi một lần; khóa 48 giờ trước khi kết thúc', () {
      const end = 1000 * _h;
      expect(teamChoice(currentTeamId: null, teamChanges: 0, endsAt: end, nowMs: 0), TeamChoice.choose);
      expect(teamChoice(currentTeamId: 'red', teamChanges: 0, endsAt: end, nowMs: 0), TeamChoice.change);
      expect(teamChoice(currentTeamId: 'red', teamChanges: 1, endsAt: end, nowMs: 0), TeamChoice.locked);
      expect(teamChoice(currentTeamId: null, teamChanges: 0, endsAt: end, nowMs: end - 48 * _h), TeamChoice.locked);
      expect(teamChoice(currentTeamId: null, teamChanges: 0, endsAt: end, nowMs: end - 48 * _h - 1), TeamChoice.choose);
    });

    test('chia cân bằng: đội ít người nhất, bằng nhau theo tên', () {
      expect(pickBalancedTeam([_red, _blue, _green], {'red': 2, 'blue': 1, 'green': 1}), 'blue');
      expect(pickBalancedTeam([_red, _blue], {'red': 0, 'blue': 3}), 'red');
      expect(pickBalancedTeam(const [], const {}), isNull);
    });
  });

  group('TM32: repository', () {
    test('tạo đội, chọn, đổi một lần, lần hai bị chặn; tiến độ theo đội', () async {
      final db = FakeFirebaseFirestore();
      var now = 0;
      ExploreRepository as(String uid) => ExploreRepository(ready: () => true, firestore: () => db, uid: () => uid, nowMs: () => now);
      await db.doc('challenges/k').set({'title': 'k', 'metric': 'distance', 'target': 1, 'startsAt': 0, 'endsAt': 1000 * _h, 'clubId': 'c1'});
      await as('olly').createTeam('k', name: ' Red ', color: 2);
      await as('olly').createTeam('k', name: 'Blue', color: 1);
      final teams = await as('mia').teams('k');
      expect(teams.map((t) => (t.name, t.color)), [('Blue', 1), ('Red', 2)]);
      await db.doc('challenges/k/participants/mia').set({'userId': 'mia', 'progressValue': 7});
      await db.doc('challenges/k/participants/bo').set({'userId': 'bo', 'progressValue': 3});

      await as('mia').setMyTeam('k', teams[1].id);
      await as('bo').setMyTeam('k', teams[1].id);
      await as('mia').setMyTeam('k', teams[0].id);
      final mia = (await db.doc('challenges/k/participants/mia').get()).data()!;
      expect((mia['teamId'], mia['teamChanges']), (teams[0].id, 1));
      await expectLater(as('mia').setMyTeam('k', teams[1].id), throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'team_locked')));

      final progress = await as('bo').teamProgress('k', teams);
      expect(progress.map((p) => (p.userId, p.teamId, p.value)).toSet(), {('mia', teams[0].id, 7.0), ('bo', teams[1].id, 3.0)});

      now = 1000 * _h - 47 * _h;
      await expectLater(as('bo').setMyTeam('k', teams[0].id), throwsA(isA<ExploreFailure>()));
    });
  });

  group('TM32: widget', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());

    testWidgets('xếp hạng đội, "Put me on a team" vào đội ít người nhất', (tester) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'mia', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = FakeFirebaseFirestore();
      await db.doc('challenges/k').set({'title': 'k', 'metric': 'count', 'target': 10, 'startsAt': 0, 'endsAt': 1000 * _h, 'clubId': 'c1'});
      await db.doc('challenges/k/teams/red').set({'name': 'Red', 'color': 2});
      await db.doc('challenges/k/teams/blue').set({'name': 'Blue', 'color': 1});
      await db.doc('challenges/k/participants/a').set({'userId': 'a', 'progressValue': 4, 'teamId': 'red'});
      await db.doc('challenges/k/participants/b').set({'userId': 'b', 'progressValue': 2, 'teamId': 'red'});
      await db.doc('challenges/k/participants/mia').set({'userId': 'mia', 'progressValue': 1});
      final repo = ExploreRepository(ready: () => true, firestore: () => db, uid: () => 'mia', nowMs: () => 0);
      final c = await repo.challenge('k');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(sql),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(FakeClock(0)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChallengeTeams(challenge: c, canManage: false)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 activities per member · 2 members'), findsOneWidget);
      expect(find.text('0 activities per member · 0 members'), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byKey(const Key('team-auto')));
      await tester.pumpAndSettle();
      expect((await db.doc('challenges/k/participants/mia').get()).data()!['teamId'], 'blue');
    });
  });
}
