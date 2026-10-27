import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/presentation/screens_profile/data_sources_screen.dart';
import 'package:stride/presentation/screens_profile/edit_profile_screen.dart';
import 'package:stride/presentation/screens_profile/help_screen.dart';
import 'package:stride/presentation/screens_profile/profile_screen.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:test'});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => db.close());

  Future<ProviderContainer> pump(WidgetTester tester, Widget screen, {FeatureFlags flags = const FeatureFlags()}) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.motion: PermStatus.granted})),
        clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 18, 9).millisecondsSinceEpoch)),
        flagsProvider.overrideWithValue(flags),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  testWidgets('Profile: khách hiện "Guest", Explore hiện khi có flag', (tester) async {
    await pump(tester, const ProfileScreen());
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Total runs'), findsOneWidget);
    // TM20: chưa có dữ liệu → thẻ chuỗi trạng thái rỗng.
    expect(find.byKey(const Key('streak-card')), findsOneWidget);
    expect(find.text('No active streak yet'), findsOneWidget);
    // T01: vùng chạm ≥ 48 (Android) / 44 (iOS); T08: mọi vùng chạm có nhãn.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('X20: Trợ giúp › Tối ưu pin hiện trạng thái thật + hướng dẫn theo hãng', (tester) async {
    await pump(tester, const HelpScreen());
    await tester.tap(find.text('Battery optimization'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('battery optimization is on for STRIDE'), findsOneWidget);
    expect(find.textContaining('Samsung:'), findsOneWidget);
    expect(find.textContaining('Xiaomi'), findsOneWidget);
  });

  testWidgets('Profile: tắt mọi flag explore thì ẩn hàng Explore', (tester) async {
    await pump(tester, const ProfileScreen(), flags: const FeatureFlags(exploreClubs: false, exploreChallenges: false, exploreRoutes: false));
    expect(find.text('Explore'), findsNothing);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('Data sources: Connect a device theo devicesBle, Health theo stepsHealth', (tester) async {
    await pump(tester, const DataSourcesScreen(), flags: const FeatureFlags(devicesBle: false));
    expect(find.text('Connect a device'), findsNothing);
    expect(find.text('Health Connect'), findsNothing);
    expect(find.text('Overlapping steps count once'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
  });

  testWidgets('Data sources: hiện Connect a device khi bật devicesBle', (tester) async {
    await pump(tester, const DataSourcesScreen());
    expect(find.text('Connect a device'), findsOneWidget);
    expect(find.text('Source priority'), findsOneWidget);
  });

  testWidgets('Edit profile: thiếu tên báo lỗi, chiều cao ngoài khoảng báo lỗi, không lưu', (tester) async {
    final c = await pump(tester, const EditProfileScreen());
    await tester.enterText(find.byKey(const Key('profile-name')), '');
    await tester.enterText(find.byKey(const Key('profile-height')), '90');
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a height between 100 and 250 cm'), findsOneWidget);
    final s = await c.read(settingsRepositoryProvider).load('guest:test');
    expect(s.revision, 0);
  });

  testWidgets('Edit profile: lưu tên + số đo theo cm/kg', (tester) async {
    final c = await pump(tester, const EditProfileScreen());
    await tester.enterText(find.byKey(const Key('profile-name')), 'Alex Morgan');
    await tester.enterText(find.byKey(const Key('profile-height')), '172');
    await tester.enterText(find.byKey(const Key('profile-weight')), '68');
    await tester.tap(find.text('Save changes'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final s = await c.read(settingsRepositoryProvider).load('guest:test');
    expect(s.displayName, 'Alex Morgan');
    expect(s.heightCm, 172);
    expect(s.weightKg, 68);
    expect(s.heightUnit, HeightUnit.cm);
  });
}
