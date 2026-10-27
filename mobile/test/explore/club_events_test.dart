import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/reminders/reminder_logic.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/presentation/screens_explore/event_form_screen.dart';
import 'package:stride/repository/explore_repository.dart';
import 'package:stride/repository/reminder_repository.dart';
import 'package:stride/services/application/reminder_scheduler.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

class _Scheduler implements ReminderScheduler {
  List<EventReminderSlot>? events;
  @override
  Future<void> apply(Reminder r, List<ReminderSlot> slots) async {}
  @override
  Future<void> applyEvents(List<EventReminderSlot> slots) async => events = slots;
}

class _EventsRepo extends ExploreRepository {
  _EventsRepo(this.upcoming, {this.fail = false}) : super(ready: () => false, firestore: () => throw UnimplementedError(), uid: () => null);
  final List<ClubEvent> upcoming;
  final bool fail;
  final created = <Map<String, Object?>>[];

  List<Challenge> open = const [];

  @override
  Future<List<ClubEvent>> myUpcomingEvents() async => fail ? throw const ExploreFailure(ExploreErrorKind.offline) : upcoming;

  @override
  Future<List<Challenge>> myOpenChallenges() async => open;

  @override
  Future<String> createEvent(String clubId, Map<String, Object?> fields) async {
    created.add({...fields, 'clubId': clubId});
    return 'e-new';
  }
}

ClubEvent _ev(String id, DateTime start) =>
    ClubEvent(id: id, clubId: 'c1', title: 'Run $id', description: '', startAt: start.millisecondsSinceEpoch, tzId: 'UTC', meetingPlace: '', goingCount: 1);

void main() {
  final now = DateTime(2026, 10, 27, 9);

  group('TM05: logic', () {
    test('kiểm dữ liệu: tên, quá khứ, giờ kết thúc, sức chứa', () {
      Set<EventDraftError> v({String title = 'Long run', DateTime? start, DateTime? end, int? cap}) => validateEventDraft(
        title: title,
        description: '',
        location: '',
        startsAt: start ?? now.add(const Duration(days: 1)),
        endsAt: end,
        maxGoing: cap,
        now: now,
      );
      expect(v(), isEmpty);
      expect(v(title: 'ab'), {EventDraftError.titleTooShort});
      expect(v(start: now), {EventDraftError.startInPast});
      expect(v(start: now.add(const Duration(hours: 2)), end: now.add(const Duration(hours: 1))), {EventDraftError.endBeforeStart});
      expect(v(cap: 1), {EventDraftError.capacityInvalid});
      expect(v(cap: 2), isEmpty);
    });

    test('nhắc 1 ngày + 1 giờ trước, bỏ mốc đã qua; đủ chỗ; quyền quản lý', () {
      final start = DateTime(2026, 10, 28, 7);
      expect(eventReminderTimes(start.millisecondsSinceEpoch, now), [DateTime(2026, 10, 28, 6)]);
      expect(eventReminderTimes(DateTime(2026, 10, 29, 7).millisecondsSinceEpoch, now), [DateTime(2026, 10, 28, 7), DateTime(2026, 10, 29, 6)]);
      expect(eventFull(goingCount: 5, maxGoing: 5), isTrue);
      expect(eventFull(goingCount: 5, maxGoing: null), isFalse);
      expect(canManageEvent(createdBy: 'mia', myUid: 'mia', myRole: 'member'), isTrue);
      expect(canManageEvent(createdBy: 'adam', myUid: 'mia', myRole: 'member'), isFalse);
      expect(canManageEvent(createdBy: 'adam', myUid: 'olly', myRole: 'owner'), isTrue);
    });

    test('.ics: giờ UTC, thoát ký tự đặc biệt, mặc định dài 1 giờ, dòng CRLF', () {
      final start = DateTime.utc(2026, 11, 1, 0, 30).millisecondsSinceEpoch;
      final ics = eventIcs(id: 'e1', title: 'Run, then coffee; ok', description: 'Line 1\nLine 2', location: '', startsAt: start, nowMs: start);
      expect(ics, contains('DTSTART:20261101T003000Z\r\n'));
      expect(ics, contains('DTEND:20261101T013000Z\r\n'));
      expect(ics, contains(r'SUMMARY:Run\, then coffee\; ok'));
      expect(ics, contains(r'DESCRIPTION:Line 1\nLine 2'));
      expect(ics, isNot(contains('LOCATION')));
      expect(ics.startsWith('BEGIN:VCALENDAR\r\n'), isTrue);
    });
  });

  group('TM05: repository', () {
    late FakeFirebaseFirestore db;
    late int nowMs;
    ExploreRepository as(String uid) =>
        ExploreRepository(ready: () => true, firestore: () => db, uid: () => uid, displayName: () => uid.toUpperCase(), nowMs: () => nowMs);

    setUp(() {
      db = FakeFirebaseFirestore();
      nowMs = now.millisecondsSinceEpoch;
    });

    test('tạo/sửa; RSVP ghi tên + bản sao để nhắc; đủ chỗ → event_full; hủy → không còn trong "sắp tới"', () async {
      Map<String, Object?> f(String title, {int? cap}) =>
          eventFields(title: title, description: '', location: 'Park', startsAt: now.add(const Duration(days: 2)), maxGoing: cap, tzId: 'UTC', nowMs: nowMs);
      final id = await as('adam').createEvent('c1', f('Long run', cap: 2));
      await as('adam').updateEvent(id, f('Long run 15K', cap: 2));
      final e = await as('adam').event(id);
      expect((e.title, e.maxGoing, e.createdBy, e.goingCount), ('Long run 15K', 2, 'adam', 0));

      await as('mia').rsvp(id, true);
      await as('bo').rsvp(id, true);
      await expectLater(as('cy').rsvp(id, true), throwsA(isA<ExploreFailure>().having((x) => x.code, 'code', 'event_full')));
      expect((await as('adam').eventAttendees(id)).map((a) => (a.userId, a.displayName)), [('mia', 'MIA'), ('bo', 'BO')]);
      expect((await as('mia').myUpcomingEvents()).single.id, id);

      await as('mia').rsvp(id, false);
      expect(await as('mia').myUpcomingEvents(), isEmpty);
      await as('bo').rsvp(id, false);
      await as('cy').rsvp(id, true);
      await as('adam').cancelEvent(id);
      expect(await as('cy').myUpcomingEvents(), isEmpty);
    });
  });

  group('TM05: lịch nhắc', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());

    Future<_Scheduler> sync(_EventsRepo repo, {PermStatus perm = PermStatus.granted, bool guest = false, QuietHours? quiet}) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:r', if (!guest) 'user_id': 'mia', if (!guest) 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      final sched = _Scheduler();
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(sql),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.notification: perm})),
          remindersSchedulerProvider.overrideWithValue(sched),
          exploreRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FakeClock(now.millisecondsSinceEpoch)),
        ],
      );
      addTearDown(c.dispose);
      if (quiet != null) await c.read(remindersRepositoryProvider).saveQuietHours(c.read(ownerProvider).ownerId, quiet);
      await c.read(remindersSyncProvider)();
      return sched;
    }

    test('đặt nhắc cho sự kiện đã đăng ký, bỏ mốc đã qua và mốc trong giờ yên lặng', () async {
      final repo = _EventsRepo([_ev('a', DateTime(2026, 10, 28, 7)), _ev('b', DateTime(2026, 10, 30, 18))]);
      final s = (await sync(
        repo,
        quiet: const QuietHours(enabled: true, startMin: 22 * 60, endMin: 7 * 60),
      )).events!;
      // a: 1 giờ trước (06:00 rơi vào giờ yên lặng → bỏ; mốc 1 ngày trước đã qua). b: 29/10 18:00 và 30/10 17:00.
      expect(s.map((x) => x.at), [DateTime(2026, 10, 29, 18), DateTime(2026, 10, 30, 17)]);
      expect(s.map((x) => x.notificationId).toSet().length, 2);
      expect(s.first.body, allOf(startsWith('Tomorrow at 6:00'), endsWith('See you there!')));
      expect(s.last.link, '/profile/explore/clubs/c1');
    });

    test('TM34: thử thách đang tham gia → nhắc trước khi bắt đầu/kết thúc và lúc chốt kết quả, xếp chung theo thời gian', () async {
      final repo = _EventsRepo([_ev('a', DateTime(2026, 10, 29, 18))])
        ..open = [
          Challenge.fromDoc('ch', {
            'title': 'November 100K',
            'metric': 'distance',
            'target': 100000,
            'startsAt': DateTime(2026, 11, 1).millisecondsSinceEpoch,
            'endsAt': DateTime(2026, 11, 30).millisecondsSinceEpoch,
          }),
        ];
      final s = (await sync(repo)).events!;
      expect(s.map((x) => (x.at, x.title)), [
        (DateTime(2026, 10, 28, 18), 'Run a'),
        (DateTime(2026, 10, 29, 17), 'Run a'),
        (DateTime(2026, 10, 31), 'November 100K'),
        (DateTime(2026, 11, 29), 'November 100K'),
        (DateTime(2026, 12, 2), 'November 100K'),
      ]);
      expect(s[2].body, startsWith('Starts tomorrow'));
      expect(s.last.link, '/profile/explore/challenges/ch/results');
      expect(s.map((x) => x.notificationId).toSet().length, s.length);
    });

    test('không quyền hoặc khách → hủy hết; lỗi mạng → giữ lịch cũ (không gọi applyEvents)', () async {
      final repo = _EventsRepo([_ev('a', DateTime(2026, 10, 30, 18))]);
      expect((await sync(repo, perm: PermStatus.denied)).events, isEmpty);
      expect((await sync(repo, guest: true)).events, isEmpty);
      expect((await sync(_EventsRepo(const [], fail: true))).events, isNull);
    });
  });

  group('TM05: form', () {
    sqfliteFfiInit();
    late AppDatabase sql;
    setUp(() async => sql = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate));
    tearDown(() => sql.close());

    testWidgets('tên quá ngắn và sức chứa sai báo lỗi; hợp lệ → tạo (mặc định 7:00 sáng mai, 1 giờ)', (tester) async {
      SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'user_id': 'adam', 'user_email': 'x@y.z'});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _EventsRepo(const []);
      bool? popped;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => TextButton(onPressed: () async => popped = await c.push<bool>('/new'), child: const Text('open')),
          ),
          GoRoute(
            path: '/new',
            builder: (c, s) => const EventFormScreen(clubId: 'c1'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(sql),
            sharedPrefsProvider.overrideWithValue(prefs),
            permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
            exploreRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(FakeClock(now.millisecondsSinceEpoch)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // T01/T08: vùng chạm ≥ 48 (Android) / 44 (iOS), mọi vùng chạm có nhãn.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.enterText(find.byKey(const Key('event-title')), 'ab');
      await tester.enterText(find.byKey(const Key('event-capacity')), '1');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pump();
      expect(find.text('Use at least 3 characters.'), findsOneWidget);
      expect(find.text('Enter a number from 2 to 1000.'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.enterText(find.byKey(const Key('event-title')), 'Sunday long run');
      await tester.enterText(find.byKey(const Key('event-capacity')), '');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      final c = repo.created.single;
      expect((c['clubId'], c['title'], c['maxGoing']), ('c1', 'Sunday long run', null));
      expect(c['startsAt'], DateTime(2026, 10, 28, 7).millisecondsSinceEpoch);
      expect(c['endsAt'], DateTime(2026, 10, 28, 8).millisecondsSinceEpoch);
      expect(popped, isTrue);
    });
  });
}
