import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/group_sharing.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/club_group_tab.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/calc/group_stats.dart';
import 'package:stride/utils/clock.dart';

Activity _act(String id, DateTime at, {ActivityType type = ActivityType.run, Privacy privacy = Privacy.public, double m = 5000}) => Activity(
  id: id,
  ownerId: 'u',
  type: type,
  status: ActivityStatus.saved,
  startedAt: at.millisecondsSinceEpoch,
  tzId: 'UTC',
  tzOffsetMin: at.timeZoneOffset.inMinutes,
  distanceM: m,
  movingMs: 1800000,
  avgPaceSecPerKm: 360,
  hasGps: type != ActivityType.indoorRun,
  distanceSource: type == ActivityType.indoorRun ? DistanceSource.steps : DistanceSource.gps,
  privacy: privacy,
);

MemberStats _m(String id, Map<String, (bool, double)> days) => MemberStats(
  userId: id,
  displayName: id,
  days: {for (final e in days.entries) e.key: MemberDay(achieved: e.value.$1, distanceM: e.value.$2, activities: e.value.$2 > 0 ? 1 : 0)},
);

class _FakeSharing extends GroupSharing {
  _FakeSharing(super.ref);
  final on = <String>{};
  @override
  Future<Set<String>> clubs() async => on;
  @override
  Future<void> set(String clubId, bool v) async => v ? on.add(clubId) : on.remove(clubId);
}

class _Repo extends ExploreRepository {
  _Repo(this.stats) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  final List<MemberStats> stats;
  @override
  Future<List<MemberStats>> clubMemberStats(String clubId) async => stats;
}

void main() {
  // Thứ Tư 2026-10-28.
  final today = DateTime(2026, 10, 28, 20);

  group('logic', () {
    test('ngày của tôi: 62 ngày, chỉ cộng hoạt động hợp lệ cho nhóm (bỏ riêng tư, indoor)', () {
      final days = buildMemberDays(
        today: today,
        achieved: {'2026-10-28', '2026-10-27'},
        activities: [
          _act('a', DateTime(2026, 10, 28, 7)),
          _act('private', DateTime(2026, 10, 28, 8), privacy: Privacy.onlyMe),
          _act('indoor', DateTime(2026, 10, 28, 9), type: ActivityType.indoorRun),
        ],
      );
      expect(days.length, groupStatsDays);
      expect(days.keys.last, '2026-10-28');
      final d = days['2026-10-28']!;
      expect((d.achieved, d.distanceM, d.activities), (true, 5000.0, 1));
      expect(days['2026-10-26']!.achieved, isFalse);
    });

    test('chuỗi nhóm: chỉ ngày MỌI người đạt; hôm nay chưa xong chưa đứt; đếm người xong hôm nay', () {
      final members = [
        _m('a', {'2026-10-25': (true, 0), '2026-10-26': (true, 0), '2026-10-27': (true, 0), '2026-10-28': (true, 0)}),
        _m('b', {'2026-10-25': (false, 0), '2026-10-26': (true, 0), '2026-10-27': (true, 0), '2026-10-28': (false, 0)}),
      ];
      final s = computeGroupStreak(members, today);
      expect((s.summary.current, s.members, s.doneToday, s.summary.todayAchieved), (2, 2, 1, false));
      expect(computeGroupStreak(const [], today).members, 0);
    });

    test('mục tiêu: kỳ tuần theo weekStart của mục tiêu, kỳ tháng; tổng + đóng góp giảm dần, bỏ người 0', () {
      const week = GroupGoal(period: GroupGoalPeriod.week, metric: GroupGoalMetric.distance, target: 50000, weekStart: DateTime.sunday);
      expect(groupGoalRange(week, today), (DateTime(2026, 10, 25), DateTime(2026, 10, 31)));
      const month = GroupGoal(period: GroupGoalPeriod.month, metric: GroupGoalMetric.count, target: 20);
      expect(groupGoalRange(month, today), (DateTime(2026, 10, 1), DateTime(2026, 10, 31)));
      final p = computeGroupGoalProgress(week, [
        _m('a', {'2026-10-24': (true, 9000), '2026-10-26': (true, 3000)}),
        _m('b', {'2026-10-27': (true, 7000)}),
        _m('c', {'2026-10-20': (true, 4000)}),
      ], today);
      expect(p.total, 10000);
      expect(p.byMember.map((r) => (r.$1, r.$3)), [('b', 7000.0), ('a', 3000.0)]);
      expect(GroupGoal.fromMap(week.toMap())!.weekStart, DateTime.sunday);
      expect(GroupGoal.fromMap({'period': 'week', 'metric': 'distance', 'target': 0}), isNull);
    });
  });

  group('repository', () {
    test('ghi / đọc / tắt chia sẻ; đặt và gỡ mục tiêu nhóm', () async {
      final db = FakeFirebaseFirestore();
      ExploreRepository as(String uid) => ExploreRepository(ready: () => true, firestore: () => db, uid: () => uid, displayName: () => uid, nowMs: () => 7);
      await db.doc('clubs/c1').set({'name': 'Club', 'visibility': 'public', 'memberCount': 2, 'ownerId': 'olly'});
      await as('mia').publishMemberStats('c1', {'2026-10-28': const MemberDay(achieved: true, distanceM: 5000, activities: 1, movingMs: 1)});
      await as('bo').publishMemberStats('c1', {'2026-10-28': const MemberDay(achieved: false)});
      final list = await as('olly').clubMemberStats('c1');
      expect(list.map((m) => m.userId).toSet(), {'mia', 'bo'});
      expect(list.firstWhere((m) => m.userId == 'mia').days['2026-10-28']!.distanceM, 5000);

      await as('bo').stopSharingStats('c1');
      expect((await as('olly').clubMemberStats('c1')).map((m) => m.userId), ['mia']);

      const g = GroupGoal(period: GroupGoalPeriod.month, metric: GroupGoalMetric.time, target: 36000000);
      await as('olly').setGroupGoal('c1', g);
      expect((await as('olly').club('c1')).groupGoal!.metric, GroupGoalMetric.time);
      await as('olly').setGroupGoal('c1', null);
      expect((await as('olly').club('c1')).groupGoal, isNull);
    });
  });

  group('widget', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());

    testWidgets('chuỗi nhóm + số người xong hôm nay (không tên), mục tiêu + đóng góp; bật chia sẻ', (tester) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'mia', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late _FakeSharing sharing;
      final repo = _Repo([
        _m('Ann', {'2026-10-27': (true, 4000), '2026-10-28': (true, 6000)}),
        _m('Bo', {'2026-10-27': (true, 2000), '2026-10-28': (false, 0)}),
      ]);
      const club = Club(
        id: 'c1',
        name: 'Crew',
        description: '',
        regionText: '',
        memberCount: 2,
        groupGoal: GroupGoal(period: GroupGoalPeriod.week, metric: GroupGoalMetric.distance, target: 20000),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(sql),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(FakeClock(today.millisecondsSinceEpoch)),
            groupSharingProvider.overrideWith((ref) => sharing = _FakeSharing(ref)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ClubGroupTab(club: club, canManage: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1-day group streak'), findsOneWidget);
      expect(find.text('Today: 1 of 2 sharing members are done'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^12[.,]?0* km of 20[.,]?0* km$')), findsOneWidget);
      expect(find.byKey(const Key('contribution-Ann')), findsOneWidget);
      expect(find.byKey(const Key('group-goal-edit')), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(const Key('group-share')));
      await tester.pumpAndSettle();
      expect(sharing.on, {'c1'});
    });
  });
}
