import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/post_to_club_sheet.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';

Activity _run({DistanceSource source = DistanceSource.gps, double? pace = 330}) => Activity(
  id: 'a1',
  ownerId: 'me',
  type: ActivityType.run,
  status: ActivityStatus.saved,
  startedAt: 1000,
  tzId: 'UTC',
  tzOffsetMin: 0,
  distanceM: 5000,
  movingMs: 1650000,
  avgPaceSecPerKm: pace,
  hasGps: source == DistanceSource.gps,
  distanceSource: source,
  notes: 'private note',
  privacy: Privacy.onlyMe,
);

class _FakeRepo extends ExploreRepository {
  _FakeRepo(this.clubs) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  final List<Club> clubs;
  final sent = <(String, String, Map<String, Object?>?)>[];
  Completer<void>? gate;

  @override
  Future<List<Club>> myClubs() async => clubs;

  @override
  Future<ClubPost> createPost(String clubId, {required String text, Map<String, Object?>? activity}) async {
    sent.add((clubId, text, activity));
    await gate?.future;
    return ClubPost(id: 'p', clubId: clubId, authorId: 'me', text: text, commentCount: 0, cheerCount: 0, cheeredByMe: false, createdAt: 1);
  }
}

Club _club(String id, {MembershipStatus status = MembershipStatus.approved}) => Club(
  id: id,
  name: 'Club $id',
  description: '',
  regionText: '',
  memberCount: 2,
  membership: ClubMembership(role: 'member', status: status),
);

void main() {
  group('TM06: tóm tắt hoạt động trong bài đăng', () {
    test('chỉ khóa cho phép (khớp rules), không tọa độ/ghi chú; quãng đường theo bước → estimated', () {
      final d = postActivityDoc(_run(), title: 'Morning run');
      expect(postActivityKeys, containsAll(d.keys));
      expect(d, {
        'id': 'a1',
        'type': 'run',
        'title': 'Morning run',
        'startedAt': 1000,
        'distanceM': 5000.0,
        'distanceEstimated': false,
        'movingMs': 1650000,
        'avgPaceSecPerKm': 330.0,
      });
      final est = postActivityDoc(_run(source: DistanceSource.steps, pace: null), title: 't');
      expect((est['distanceEstimated'], est.containsKey('avgPaceSecPerKm')), (true, false));
    });

    test('repository: đăng kèm hoạt động (không cần chữ), feed đọc lại thẻ hoạt động', () async {
      final db = FakeFirebaseFirestore();
      final repo = ExploreRepository(ready: () => true, firestore: () => db, uid: () => 'me', displayName: () => 'Me', nowMs: () => 5);
      await expectLater(repo.createPost('c1', text: '  '), throwsA(isA<ExploreFailure>()));
      await repo.createPost(
        'c1',
        text: '',
        activity: postActivityDoc(_run(), title: 'Morning run'),
      );
      final page = await repo.posts('c1');
      final a = page.items.single.activity!;
      expect((a.title, a.distanceM, a.movingMs, a.distanceEstimated), ('Morning run', 5000.0, 1650000, false));
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
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => showPostToClubSheet(context, _run()), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('chọn club (bỏ club đang chờ duyệt), đăng một lần dù chạm đúp', (tester) async {
      final repo = _FakeRepo([_club('a'), _club('b'), _club('p', status: MembershipStatus.pending)])..gate = Completer<void>();
      await pump(tester, repo);
      expect(find.byKey(const Key('post-club-p')), findsNothing);
      expect(find.textContaining('Your map and notes stay private'), findsOneWidget);
      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      // Chưa chọn club → nút tắt.
      await tester.tap(find.byKey(const Key('post-club-submit')));
      await tester.pump();
      expect(repo.sent, isEmpty);

      await tester.tap(find.byKey(const Key('post-club-b')));
      await tester.enterText(find.byKey(const Key('post-club-text')), 'Nice one');
      await tester.pump();
      await tester.tap(find.byKey(const Key('post-club-submit')));
      await tester.tap(find.byKey(const Key('post-club-submit')), warnIfMissed: false);
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.sent.length, 1);
      expect((repo.sent.single.$1, repo.sent.single.$2, repo.sent.single.$3!['distanceM']), ('b', 'Nice one', 5000.0));
      expect(repo.sent.single.$3!.containsKey('notes'), isFalse);
      expect(find.text('Posted to the club'), findsOneWidget);
    });

    testWidgets('chưa tham gia club nào → trạng thái rỗng', (tester) async {
      await pump(tester, _FakeRepo([_club('p', status: MembershipStatus.pending)]));
      expect(find.text('You’re not in a club yet'), findsOneWidget);
      expect(find.byKey(const Key('post-club-submit')), findsNothing);
    });
  });
}
