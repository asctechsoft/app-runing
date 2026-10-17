import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/permissions/permission_coordinator.dart';
import 'package:stride/core/providers.dart';
import 'package:stride/core/theme/stride_theme.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/activity_repository.dart';
import 'package:stride/features/activity/activity_providers.dart';

const testOwner = 'user-1';

/// Môi trường widget test: DB in-memory thật (ffi), owner cố định, không tile bản đồ.
class WidgetHarness {
  WidgetHarness._(this.db, this.prefs, this.clock);

  final AppDatabase db;
  final SharedPreferences prefs;
  final FakeClock clock;

  late final ActivityRepository repo = ActivityRepository(db, clock);

  static Future<WidgetHarness> create(WidgetTester tester, {DateTime? now}) async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({'user_id': testOwner, 'user_email': 'a@b.c'});
    final h = await tester.runAsync(() async {
      final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final prefs = await SharedPreferences.getInstance();
      return WidgetHarness._(db, prefs, FakeClock((now ?? DateTime(2026, 10, 15, 18)).millisecondsSinceEpoch));
    });
    // Đóng DB kể cả khi test fail: ":memory:" được sqflite cache theo path, không đóng sẽ rò dữ liệu sang test sau.
    addTearDown(() => h!.db.close());
    return h!;
  }

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      permissionsProvider.overrideWithValue(FakePermissionCoordinator()),
      clockProvider.overrideWithValue(clock),
      activityMapTilesEnabledProvider.overrideWithValue(false),
      // Repository dùng chung với test để seed dữ liệu.
      activityRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(theme: buildStrideTheme(), home: child),
  );

  /// Cho DB (ffi, async thật) chạy rồi pump khung hình.
  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
