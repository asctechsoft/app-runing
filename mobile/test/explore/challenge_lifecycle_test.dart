import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screens_explore/challenges_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

const _h = 3600 * 1000;

Activity _run(String id, int startedAt, double m) => Activity(
  id: id,
  ownerId: 'mia',
  type: ActivityType.run,
  status: ActivityStatus.saved,
  startedAt: startedAt,
  tzId: 'UTC',
  tzOffsetMin: 0,
  distanceM: m,
  movingMs: 30 * 60 * 1000,
  avgPaceSecPerKm: 360,
  hasGps: true,
  distanceSource: DistanceSource.gps,
  privacy: Privacy.public,
);

/// TM33: vòng đời thử thách + các ca đặc biệt (đồng bộ trễ, sửa sau khi khóa, rời/bị cấm giữa kỳ).
void main() {
  group('pha', () {
    ChallengePhase at(int now, {bool cancelled = false}) => challengePhase(startsAt: 100, endsAt: 200, cancelled: cancelled, nowMs: now);

    test('sắp diễn ra → đang diễn ra → chờ đồng bộ 48 giờ → khóa; hủy luôn thắng', () {
      expect(at(99), ChallengePhase.upcoming);
      expect(at(100), ChallengePhase.active);
      expect(at(200), ChallengePhase.active);
      expect(at(201), ChallengePhase.grace);
      expect(at(200 + 48 * _h), ChallengePhase.grace);
      expect(at(201 + 48 * _h), ChallengePhase.finished);
      expect(at(150, cancelled: true), ChallengePhase.cancelled);
    });

    test('quyền theo pha', () {
      expect(ChallengePhase.values.where(canUpdateChallengeProgress), [ChallengePhase.active, ChallengePhase.grace]);
      expect(ChallengePhase.values.where(canJoinChallenge), [ChallengePhase.upcoming, ChallengePhase.active]);
      expect(canLeaveChallenge(ChallengePhase.finished), isFalse);
      expect(canLeaveChallenge(ChallengePhase.grace), isTrue);
    });
  });

  group('repository', () {
    late FakeFirebaseFirestore db;
    late int now;
    late List<Activity> local;
    final start = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
    final end = DateTime.utc(2026, 10, 31).millisecondsSinceEpoch;

    ExploreRepository as(String uid) => ExploreRepository(
      ready: () => true,
      firestore: () => db,
      uid: () => uid,
      nowMs: () => now,
      localActivities: (from, to) async => local.where((a) => a.startedAt >= from && a.startedAt < to).toList(),
    );

    setUp(() async {
      db = FakeFirebaseFirestore();
      local = [];
      now = start + _h;
      await db.doc('challenges/ch').set({'title': 'Oct', 'metric': 'distance', 'target': 100000, 'startsAt': start, 'endsAt': end, 'participantCount': 0});
    });

    test('hoạt động offline (chạy trong kỳ) đồng bộ trong thời gian chờ vẫn được cộng; sau khi khóa thì sửa/xóa không đổi kết quả', () async {
      await as('mia').joinChallenge('ch');
      local = [_run('a1', start + 2 * _h, 5000)];
      expect((await as('mia').challengeProgress('ch')).progressValue, 5000);

      // Kỳ kết thúc; buổi chạy trước hạn mới đồng bộ về máy sau hạn → vẫn tính.
      now = end + 10 * _h;
      local = [...local, _run('late', end - _h, 3000), _run('after', end + _h, 9000)];
      expect((await as('mia').challengeProgress('ch')).progressValue, 8000);

      // Hết thời gian chờ: xóa hoạt động không làm đổi kết quả đã chốt.
      now = end + 49 * _h;
      local = [];
      expect((await as('mia').challengeProgress('ch')).progressValue, 8000);
      expect((await db.doc('challenges/ch/participants/mia').get()).data()!['progressValue'], 8000);
    });

    test('không tham gia sau khi kết thúc; không rời sau khi khóa (vẫn rời được trong thời gian chờ)', () async {
      await as('mia').joinChallenge('ch');
      await as('bo').joinChallenge('ch');
      now = end + _h;
      await expectLater(as('cy').joinChallenge('ch'), throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'challenge_ended')));
      await as('bo').leaveChallenge('ch');
      now = end + 49 * _h;
      await expectLater(as('mia').leaveChallenge('ch'), throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'challenge_locked')));
    });

    test('TM34: thử thách đang mở để nhắc — bỏ đã hủy, đã khóa, đã rời; giữ đang chờ đồng bộ', () async {
      now = end + 10 * _h;
      Future<void> c(String id, {int? endsAt, bool cancelled = false, String status = 'active'}) async {
        await db.doc('challenges/$id').set({
          'title': id,
          'metric': 'distance',
          'target': 1,
          'startsAt': start,
          'endsAt': endsAt ?? end,
          if (cancelled) 'cancelledAt': 1,
        });
        await db.doc('users/mia/challengeJoins/$id').set({'status': status});
      }

      await c('grace');
      await c('locked', endsAt: end - 49 * _h);
      await c('cancelled', cancelled: true);
      await c('left', status: 'left');
      await c('future', endsAt: end + 100 * _h);
      expect((await as('mia').myOpenChallenges()).map((x) => x.id).toSet(), {'grace', 'future'});
    });

    test('thử thách của club: người không còn là thành viên (bị cấm/đã rời) không tham gia được', () async {
      await db.doc('challenges/club').set({
        'title': 'Crew',
        'metric': 'count',
        'target': 10,
        'startsAt': start,
        'endsAt': end,
        'participantCount': 0,
        'clubId': 'c1',
      });
      await db.doc('clubs/c1/members/mia').set({'userId': 'mia', 'role': 'member', 'status': 'active'});
      await db.doc('clubs/c1/members/pete').set({'userId': 'pete', 'role': 'member', 'status': 'pending'});
      await as('mia').joinChallenge('club');
      for (final uid in ['pete', 'eve']) {
        await expectLater(as(uid).joinChallenge('club'), throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'club_members_only')));
      }
    });
  });

  group('widget: chi tiết theo pha', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());
    final start = DateTime(2026, 10, 1).millisecondsSinceEpoch;
    final end = DateTime(2026, 10, 31).millisecondsSinceEpoch;

    Future<void> pump(WidgetTester tester, int now) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'mia', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = FakeFirebaseFirestore();
      await db.doc('challenges/ch').set({'title': 'Oct', 'metric': 'distance', 'target': 100000, 'startsAt': start, 'endsAt': end, 'participantCount': 1});
      await db.doc('challenges/ch/participants/mia').set({'userId': 'mia', 'progressValue': 8000, 'progressUpdatedAt': 1, 'leaderboardOptIn': false});
      final repo = ExploreRepository(ready: () => true, firestore: () => db, uid: () => 'mia', nowMs: () => now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(sql),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(FakeClock(now)),
          ],
          child: const MaterialApp(home: ChallengeDetailScreen(challengeId: 'ch')),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('trong thời gian chờ: báo hạn đồng bộ, còn nút rời, không có nút tham gia', (tester) async {
      await pump(tester, end + 5 * _h);
      expect(find.byKey(const Key('phase-grace')), findsOneWidget);
      expect(find.text('Leave challenge'), findsOneWidget);
      expect(find.text('Join challenge'), findsNothing);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('đã khóa: "Results are final", không rời được', (tester) async {
      await pump(tester, end + 49 * _h);
      expect(find.text('Results are final.'), findsOneWidget);
      expect(find.text('Leave challenge'), findsNothing);
    });
  });
}
