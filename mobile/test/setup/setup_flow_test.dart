import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/presentation/screens_setup/setup_permissions_screen.dart';
import 'package:stride/presentation/screens_setup/setup_profile_screen.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/values/routes.dart';

/// Luồng sau onboarding: Cập nhật thông tin (có "Đăng nhập" Google) → Yêu cầu quyền truy cập → Home.
void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:test', 'intro_seen': true});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, String start, {FeatureFlags flags = const FeatureFlags(authGoogle: true), FakePermissionCoordinator? perms}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(path: Routes.setupProfile, builder: (_, _) => const SetupProfileScreen()),
        GoRoute(path: Routes.setupPermissions, builder: (_, _) => const SetupPermissionsScreen()),
        GoRoute(
          path: Routes.home,
          builder: (_, _) => const Scaffold(body: Text('at:home')),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        flagsProvider.overrideWithValue(flags),
        permissionsProvider.overrideWithValue(perms ?? FakePermissionCoordinator()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('Cập nhật thông tin', () {
    testWidgets('có đủ trường theo thiết kế, nút Bắt đầu và Đăng nhập (Google)', (tester) async {
      await pump(tester, Routes.setupProfile);
      expect(find.text('Update your info'), findsOneWidget);
      for (final t in [
        'Username:',
        'Gender:',
        'Male',
        'Female',
        'Country:',
        'Date of birth:',
        'Weight:',
        'Height:',
        'Start',
        'Log in',
        'If you have signed in before',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.bySemanticsLabel('Choose profile photo'), findsOneWidget);
    });

    testWidgets('Google tắt → không có nút Đăng nhập (không ship nút giả)', (tester) async {
      await pump(tester, Routes.setupProfile, flags: const FeatureFlags());
      expect(find.text('Log in'), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('thiếu tên → không lưu, không sang màn quyền', (tester) async {
      await pump(tester, Routes.setupProfile);
      await tester.tap(find.text('Start'));
      await settle(tester);
      expect(find.byType(SetupPermissionsScreen), findsNothing);
      expect(prefs.getBool('profile_setup_done:guest:test'), isNull);
    });

    testWidgets('Bắt đầu: lưu hồ sơ (cục bộ), đánh dấu đã thiết lập, sang màn quyền', (tester) async {
      await pump(tester, Routes.setupProfile);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Linh');
      await tester.enterText(fields.at(1), '58,5');
      await tester.enterText(fields.at(2), '165');
      await tester.tap(find.text('Female'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await settle(tester);

      expect(find.byType(SetupPermissionsScreen), findsOneWidget);
      expect(prefs.getBool('profile_setup_done:guest:test'), isTrue);
      final rows = await tester.runAsync(() => db.db.query('settings', where: 'owner_id = ?', whereArgs: ['guest:test']));
      final s = UserSettings.fromRow(rows!.single);
      expect((s.displayName, s.gender, s.weightKg, s.heightCm), ('Linh', Gender.female, 58.5, 165));
      expect(s.countryCode, isNull, reason: 'không tự điền quốc gia');
      expect(s.birthDate, isNull, reason: 'không tự điền ngày sinh');
    });
  });

  group('Yêu cầu quyền truy cập', () {
    testWidgets('Chấp nhận → xin quyền cảm biến; Tiếp tục → Home', (tester) async {
      final perms = FakePermissionCoordinator();
      await pump(tester, Routes.setupPermissions, perms: perms);
      expect(find.text('Permission request'), findsOneWidget);
      expect(find.text('Motion sensor permission'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(perms.statuses[PermKind.motion], PermStatus.granted);
      expect(find.text('Accept'), findsNothing, reason: 'đã cấp quyền thì hiện dấu tích thay nút');
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('at:home'), findsOneWidget);
    });

    testWidgets('từ chối quyền vẫn vào được Home; không xin vị trí ở bước này', (tester) async {
      final perms = FakePermissionCoordinator({PermKind.motion: PermStatus.denied});
      await pump(tester, Routes.setupPermissions, perms: perms);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('at:home'), findsOneWidget);
      expect(perms.statuses.containsKey(PermKind.location), isFalse);
    });
  });
}
