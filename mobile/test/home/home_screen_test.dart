import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/reminders/reminder_logic.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/presentation/screen_home/home_screen.dart';
import 'package:stride/services/application/reminder_scheduler.dart';
import 'package:stride/services/application/step_tracking_service.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

class _NoopScheduler implements ReminderScheduler {
  @override
  Future<void> apply(Reminder r, List<ReminderSlot> slots) async {}
  @override
  Future<void> applyEvents(List<EventReminderSlot> slots) async {}
}

void main() {
  sqfliteFfiInit();

  Future<AppDatabase> pumpHome(WidgetTester tester, {required PermStatus motion, Future<void> Function(AppDatabase db, FakeClock clock)? seed}) async {
    SharedPreferences.setMockInitialValues({'guest_id': 'guest:w'});
    final prefs = await SharedPreferences.getInstance();
    final clock = FakeClock(DateTime(2026, 10, 18, 9, 41).millisecondsSinceEpoch);
    final db = (await tester.runAsync(() async {
      final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
      await seed?.call(db, clock);
      return db;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.motion: motion, PermKind.notification: PermStatus.denied})),
          clockProvider.overrideWithValue(clock),
          remindersSchedulerProvider.overrideWithValue(_NoopScheduler()),
          stepTrackingServiceProvider.overrideWith((ref) => StepTrackingService(ref, streamFactory: () => const Stream.empty())),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Để các truy vấn sqflite (I/O thật) hoàn tất.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    return db;
  }

  testWidgets('chưa cấp quyền: hiển thị Turn on step tracking và không có số 0 giả', (tester) async {
    final db = await pumpHome(
      tester,
      motion: PermStatus.denied,
      seed: (db, clock) async {
        final s = await SettingsRepositoryHelper.setGoal(db, clock);
        expect(s, isTrue);
      },
    );
    expect(find.text('Turn on step tracking'), findsOneWidget);
    expect(find.text('Enable access'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('0 steps'), findsNothing);
    expect(find.text('No runs yet'), findsOneWidget);
    // T01: vùng chạm ≥ 48 (Android) / 44 (iOS); T08: mọi vùng chạm có nhãn.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.runAsync(db.close);
  });

  testWidgets('bị chặn vĩnh viễn: nút Open phone settings', (tester) async {
    final db = await pumpHome(tester, motion: PermStatus.blocked);
    expect(find.text('Open phone settings'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    await tester.runAsync(db.close);
  });

  testWidgets('có quyền nhưng chưa có mẫu: No step data yet, không hiển thị 0', (tester) async {
    final db = await pumpHome(tester, motion: PermStatus.granted);
    expect(find.text('No step data yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    await tester.runAsync(db.close);
  });
}

/// Ghi mục tiêu trực tiếp qua SettingsRepository để Home có goal.
abstract final class SettingsRepositoryHelper {
  static Future<bool> setGoal(AppDatabase db, Clock clock) async {
    await db.db.insert('goal_versions', {
      'id': 'g1',
      'owner_id': 'guest:w',
      'type': GoalType.dailySteps.name,
      'value': 8000.0,
      'effective_from': '2026-01-01',
      'created_at': clock.nowMs(),
    });
    return true;
  }
}
