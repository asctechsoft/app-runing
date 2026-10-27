import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/configs/pref_const.dart';
import 'package:stride/controller/language/language_controller.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/sync/sync_providers.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/presentation/screen_startup/startup_screen.dart';
import 'package:stride/repository/owner_repository.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/values/routes.dart';

void main() {
  const guest = OwnerState(ownerId: 'guest:x', isGuest: true);
  final session = Activity(
    id: 's1',
    ownerId: 'guest:x',
    type: ActivityType.run,
    status: ActivityStatus.recoveryNeeded,
    startedAt: 0,
    tzId: 'UTC',
    tzOffsetMin: 0,
  );

  group('decideStartRoute (E01)', () {
    test('phiên chưa đóng được ưu tiên trước mọi thứ, kể cả intro chưa xem', () {
      expect(decideStartRoute(languageChosen: true, owner: guest, unclosedSession: session), Routes.recovery);
      expect(
        decideStartRoute(
          languageChosen: true,
          owner: const OwnerState(ownerId: 'u', isGuest: false, introSeen: true, profileSetupDone: true),
          unclosedSession: session.copyWith(status: ActivityStatus.awaitingSave),
        ),
        Routes.recovery,
      );
    });
    test('L19: chưa chọn ngôn ngữ → màn ngôn ngữ (trước intro); phiên dở vẫn thắng', () {
      expect(decideStartRoute(owner: guest, languageChosen: false), Routes.language);
      expect(decideStartRoute(owner: guest, languageChosen: false, unclosedSession: session), Routes.recovery);
    });
    test('L19: cờ ngôn ngữ — người dùng cũ (đã xem intro) được coi là đã chọn và ghi cờ; người mới thì chưa', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      expect(languageChosen(p, introSeen: false), isFalse);
      expect(p.getBool(PrefConst.languageChosen), isNull);
      expect(languageChosen(p, introSeen: true), isTrue);
      expect(p.getBool(PrefConst.languageChosen), isTrue);
    });
    test('chưa xem intro → onboarding', () {
      expect(decideStartRoute(languageChosen: true, owner: guest), Routes.onboarding);
    });
    test('đã xem intro, chưa thiết lập: khách → welcome, tài khoản → setup profile', () {
      expect(decideStartRoute(languageChosen: true, owner: const OwnerState(ownerId: 'g', isGuest: true, introSeen: true)), Routes.welcome);
      expect(decideStartRoute(languageChosen: true, owner: const OwnerState(ownerId: 'u', isGuest: false, introSeen: true)), Routes.setupProfile);
    });
    test('đã xong → home', () {
      expect(
        decideStartRoute(languageChosen: true, owner: const OwnerState(ownerId: 'g', isGuest: true, introSeen: true, profileSetupDone: true)),
        Routes.home,
      );
    });
  });

  group('StartupScreen', () {
    late AppDatabase db;
    setUp(() async {
      sqfliteFfiInit();
      db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    });
    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      // DB ffi chạy thật (ngoài fake async): xen kẽ chờ thật và pump frame.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    Future<GoRouter> pump(WidgetTester tester, Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(path: Routes.startup, builder: (_, _) => const StartupScreen()),
          for (final r in [Routes.language, Routes.onboarding, Routes.welcome, Routes.home, Routes.recovery, Routes.setupProfile])
            GoRoute(
              path: r,
              builder: (_, _) => Scaffold(body: Text('at:$r')),
            ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPrefsProvider.overrideWithValue(p),
            clockProvider.overrideWithValue(FakeClock(1000)),
            syncConnectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      return router;
    }

    testWidgets('lần đầu: splash → màn ngôn ngữ, không tự lưu intro_seen/cờ ngôn ngữ', (tester) async {
      await pump(tester, {});
      expect(find.text('Every step, your way'), findsOneWidget);
      await settle(tester);
      expect(find.text('at:${Routes.language}'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool(PrefConst.languageChosen), isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('intro_seen'), isNull);
    });

    testWidgets('phiên đang ghi dở → recovery (không mất run)', (tester) async {
      await tester.runAsync(() => db.db.insert('activities', session.copyWith(status: ActivityStatus.recording).toRow()));
      await pump(tester, {'guest_id': 'guest:x', 'intro_seen': true, 'profile_setup_done:guest:x': true});
      await settle(tester);
      expect(find.text('at:${Routes.recovery}'), findsOneWidget);
    });

    testWidgets('đã chọn ngôn ngữ, chưa xem intro → onboarding', (tester) async {
      await pump(tester, {PrefConst.languageChosen: true});
      await settle(tester);
      expect(find.text('at:${Routes.onboarding}'), findsOneWidget);
    });

    testWidgets('người dùng cũ (đã xem intro, chưa có cờ ngôn ngữ) → không hỏi lại ngôn ngữ', (tester) async {
      await pump(tester, {'guest_id': 'guest:x', 'intro_seen': true, 'profile_setup_done:guest:x': true});
      await settle(tester);
      expect(find.text('at:${Routes.home}'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool(PrefConst.languageChosen), isTrue);
    });

    testWidgets('đã thiết lập → home, không cần mạng', (tester) async {
      await pump(tester, {'guest_id': 'guest:x', 'intro_seen': true, 'profile_setup_done:guest:x': true});
      await settle(tester);
      expect(find.text('at:${Routes.home}'), findsOneWidget);
    });
  });
}
