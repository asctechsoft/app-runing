import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/create_challenge_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

class _FakeRepo extends ExploreRepository {
  _FakeRepo() : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  final created = <Map<String, Object?>>[];

  @override
  Future<String> createChallenge(
    String clubId, {
    required String title,
    required String description,
    required ChallengeTarget metric,
    required double target,
    required DateTime start,
    required DateTime end,
  }) async {
    created.add({'club': clubId, 'title': title, 'metric': metric, 'target': target, 'start': start, 'end': end});
    return 'ch-new';
  }
}

void main() {
  // Thứ Ba 2026-10-27 09:00 giờ máy.
  final today = DateTime(2026, 10, 27, 9);

  group('TM31: logic', () {
    Set<ChallengeDraftError> v({String title = 'Crew km', double? target = 1000, DateTime? start, DateTime? end}) => validateChallengeDraft(
      title: title,
      description: '',
      metric: ChallengeTarget.distance,
      target: target,
      start: start ?? today,
      end: end ?? DateTime(2026, 11, 30),
      today: today,
    );

    test('hợp lệ; tên/mục tiêu/ngày sai báo đúng lỗi; giới hạn 92 ngày tính cả hai đầu', () {
      expect(v(), isEmpty);
      expect(v(title: 'ab'), {ChallengeDraftError.titleTooShort});
      expect(v(target: 0), {ChallengeDraftError.targetInvalid});
      expect(v(target: null), {ChallengeDraftError.targetInvalid});
      expect(v(target: 10000 * 1000 + 1), {ChallengeDraftError.targetInvalid});
      expect(v(start: DateTime(2026, 10, 26)), {ChallengeDraftError.startInPast});
      expect(v(end: DateTime(2026, 10, 26)), {ChallengeDraftError.endBeforeStart});
      expect(v(end: DateTime(2026, 10, 27 + 91)), isEmpty);
      expect(v(end: DateTime(2026, 10, 27 + 92)), {ChallengeDraftError.tooLong});
    });

    test('document: kỳ từ 00:00 ngày đầu tới hết ngày cuối (giờ máy), chỉ run/walk, participantCount 0', () {
      final d = newClubChallengeDoc(
        clubId: 'c1',
        createdBy: 'olly',
        title: ' 30 runs ',
        description: '',
        metric: ChallengeTarget.count,
        target: 30.4,
        start: DateTime(2026, 11, 1, 15),
        end: DateTime(2026, 11, 30),
        tzId: 'ICT',
        nowMs: 5,
      );
      expect(d['title'], '30 runs');
      expect(d['target'], 30.0);
      expect(d['startsAt'], DateTime(2026, 11, 1).millisecondsSinceEpoch);
      expect(d['endsAt'], DateTime(2026, 12, 1).millisecondsSinceEpoch - 1);
      expect((d['startDate'], d['endDate'], d['participantCount']), ('2026-11-01', '2026-11-30', 0));
      expect(d['activityTypes'], ['run', 'walk']);
    });

    test('mẫu: 100 km/10 giờ tới hết tháng, 30 buổi trong 30 ngày', () {
      expect(ChallengeTemplate.distanceMonth.period(today), (DateTime(2026, 10, 27), DateTime(2026, 10, 31)));
      expect(ChallengeTemplate.runs30.period(today), (DateTime(2026, 10, 27), DateTime(2026, 11, 25)));
      expect(ChallengeTemplate.hoursMonth.target, 36000000);
    });
  });

  group('TM31: repository', () {
    late FakeFirebaseFirestore db;
    final now = DateTime(2026, 10, 27, 9).millisecondsSinceEpoch;
    ExploreRepository as(String uid) => ExploreRepository(ready: () => true, firestore: () => db, uid: () => uid, nowMs: () => now);
    setUp(() => db = FakeFirebaseFirestore());

    test('tạo → hiện trong tab club, không lẫn vào danh sách chung; hủy → ẩn và không tham gia được', () async {
      await db.doc('challenges/global').set({'title': 'Global', 'metric': 'distance', 'target': 1000, 'startsAt': 0, 'endsAt': now + 1000});
      final id = await as('olly').createChallenge(
        'c1',
        title: 'Crew km',
        description: '',
        metric: ChallengeTarget.distance,
        target: 50000,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      );
      expect((await as('olly').challenges(clubId: 'c1')).map((c) => c.id), [id]);
      expect((await as('olly').challenges()).map((c) => c.id), ['global']);
      final c = await as('olly').challenge(id);
      expect((c.clubId, c.cancelled), ('c1', false));
      expect(c.activityTypes, ['run', 'walk']);

      await as('olly').cancelChallenge(id);
      expect(await as('olly').challenges(clubId: 'c1'), isEmpty);
      expect((await as('olly').challenge(id)).cancelled, isTrue);
      await expectLater(as('mia').joinChallenge(id), throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'challenge_cancelled')));
    });
  });

  group('TM31: widget', () {
    sqfliteFfiInit();
    late AppDatabase db;
    setUp(() async => db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => db.close());

    testWidgets('mẫu điền sẵn tên/mục tiêu/kỳ; mục tiêu trống báo lỗi; tạo → trả id', (tester) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'me', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeRepo();
      String? popped;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => TextButton(onPressed: () async => popped = await c.push<String>('/new'), child: const Text('open')),
          ),
          GoRoute(
            path: '/new',
            builder: (c, s) => const CreateChallengeScreen(clubId: 'c1'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(FakeClock(today.millisecondsSinceEpoch)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('challenge-title')), 'Crew km');
      await tester.tap(find.byKey(const Key('challenge-submit')));
      await tester.pump();
      expect(find.text('Enter a goal greater than 0.'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.tap(find.byKey(const Key('template-runs30')));
      await tester.pump();
      expect(find.widgetWithText(TextField, '30 activities in 30 days'), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byKey(const Key('challenge-submit')));
      await tester.pumpAndSettle();
      expect(repo.created.single, {
        'club': 'c1',
        'title': '30 activities in 30 days',
        'metric': ChallengeTarget.count,
        'target': 30.0,
        'start': DateTime(2026, 10, 27),
        'end': DateTime(2026, 11, 25),
      });
      expect(popped, 'ch-new');
    });
  });
}
