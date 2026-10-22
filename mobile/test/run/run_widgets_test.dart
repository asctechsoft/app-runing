import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stride/values/routes.dart';
import 'package:stride/values/stride_theme.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/data_models/session_state.dart';
import 'package:stride/presentation/screens_run/countdown_screen.dart';
import 'package:stride/controller/run/engine/run_sources.dart';
import 'package:stride/presentation/screens_run/live_run_screen.dart';
import 'package:stride/presentation/screens_run/recovery_screen.dart';
import 'package:stride/presentation/screens_run/results_screen.dart';
import 'package:stride/presentation/screens_run/run_prepare_screen.dart';
import 'package:stride/presentation/screens_workout/interval_editor_screen.dart';
import 'package:stride/presentation/screens_workout/workout_chooser_screen.dart';
import 'package:stride/presentation/screens_run/save_activity_screen.dart';

import 'run_harness.dart';

Widget _app(RunHarness h, String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: Routes.run,
        builder: (c, s) => const Scaffold(body: Text('PREPARE')),
      ),
      GoRoute(path: '/prepare-real', builder: (c, s) => const RunPrepareScreen()),
      GoRoute(path: '/live-real', builder: (c, s) => const LiveRunScreen()),
      GoRoute(path: '/results-real', builder: (c, s) => const ResultsScreen()),
      GoRoute(path: '/recovery-real', builder: (c, s) => const RecoveryScreen()),
      GoRoute(path: Routes.runWorkout, builder: (c, s) => const WorkoutChooserScreen()),
      GoRoute(path: Routes.runIntervals, builder: (c, s) => const IntervalEditorScreen()),
      GoRoute(path: Routes.countdown, builder: (c, s) => const CountdownScreen()),
      GoRoute(
        path: Routes.live,
        builder: (c, s) => const Scaffold(body: Text('LIVE')),
      ),
      GoRoute(
        path: Routes.recovery,
        builder: (c, s) => const Scaffold(body: Text('RECOVERY')),
      ),
      GoRoute(
        path: Routes.results,
        builder: (c, s) => const Scaffold(body: Text('RESULTS')),
      ),
      GoRoute(path: Routes.saveActivity, builder: (c, s) => const SaveActivityScreen()),
      GoRoute(
        path: Routes.saved,
        builder: (c, s) => Scaffold(body: Text('SAVED ${s.uri.queryParameters['id']}')),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: h.container,
    child: MaterialApp.router(theme: buildStrideTheme(), routerConfig: router),
  );
}

/// Thao tác DB khởi chạy trong FakeAsync cần xen kẽ thời gian thật (I/O sqflite) và pump (microtask).
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
}

void main() {
  late RunHarness h;

  testWidgets('Countdown: Cancel quay về prepare, không tạo hoạt động, không bắt đầu ghi', (tester) async {
    h = (await tester.runAsync(() => RunHarness.create()))!;
    h.ctl.open();
    h.ctl.beginCountdown();
    await tester.pumpWidget(_app(h, Routes.countdown));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('PREPARE'), findsOneWidget);
    expect(h.ctl.state.phase, SessionPhase.preparing);
    await tester.pump(const Duration(seconds: 5));
    final rows = await tester.runAsync(() => h.db.db.query('activities'));
    expect(rows, isEmpty);
    expect(h.loc.recordingListens, 0);
    await tester.runAsync(() => h.close());
  });

  testWidgets('Countdown: đếm xong 3 s mới tạo draft và vào màn ghi', (tester) async {
    h = (await tester.runAsync(() => RunHarness.create()))!;
    h.ctl.open();
    h.ctl.beginCountdown();
    await tester.pumpWidget(_app(h, Routes.countdown));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect((await tester.runAsync(() => h.db.db.query('activities')))!, isEmpty, reason: 'chưa tạo draft trong lúc đếm');
    await tester.pump(const Duration(seconds: 1));
    await _drain(tester);
    await tester.pumpAndSettle();
    expect(find.text('LIVE'), findsOneWidget);
    expect(h.ctl.state.phase, SessionPhase.recording);
    expect((await tester.runAsync(() => h.db.db.query('activities')))!.length, 1);
    await tester.runAsync(() => h.close());
  });

  testWidgets('Save flow: lưu local với title/feeling/privacy rồi tới Saved', (tester) async {
    h = (await tester.runAsync(() => RunHarness.create()))!;
    await tester.runAsync(() async {
      await h.start();
      await h.run(seconds: 60);
      await h.ctl.finish();
    });
    await tester.pumpWidget(_app(h, Routes.saveActivity));
    await _drain(tester);
    expect(find.text('Save activity'), findsWidgets);
    expect(find.text('Only me'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Park loop');
    await tester.tap(find.text('Steady'));
    await tester.pump();
    final saveBtn = find.widgetWithText(FilledButton, 'Save activity');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pump();
    await _drain(tester);
    await tester.pumpAndSettle();
    final a = h.ctl.state.activity!;
    expect(find.text('SAVED ${a.id}'), findsOneWidget);
    expect(a.status, ActivityStatus.saved);
    expect(a.title, 'Park loop');
    expect(a.feeling, Feeling.steady);
    expect(a.privacy, Privacy.onlyMe);
    expect(a.syncState, isNot(SyncState.synced));
    await tester.runAsync(() => h.close());
  });

  group('Smoke render ở kích thước điện thoại (không overflow)', () {
    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<RunHarness> harness(WidgetTester tester) async {
      final h = (await tester.runAsync(() => RunHarness.create()))!;
      h.container.dispose();
      h.boot(clock: h.clock, overrides: [runMapTilesEnabledProvider.overrideWithValue(false)]);
      return h;
    }

    testWidgets('Live: recording → paused → locked', (tester) async {
      await phone(tester);
      final h = await harness(tester);
      await tester.runAsync(() async {
        await h.start();
        await h.run(seconds: 30);
      });
      await tester.pumpWidget(_app(h, '/live-real'));
      await tester.pump();
      expect(find.text('Pause'), findsNothing); // nút tròn chỉ có Semantics label
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.text('Lock'), findsOneWidget);
      await tester.tap(find.text('Map'));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => h.ctl.pause());
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Hold to finish'), findsOneWidget);
      await tester.runAsync(() => h.ctl.lock());
      await tester.pump();
      expect(find.text('Hold to unlock'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => h.close());
    });

    testWidgets('Results + Recovery + Prepare + Workout render', (tester) async {
      await phone(tester);
      final h = await harness(tester);
      h.ctl.open();
      h.ctl.setPlan(null);
      await tester.pumpWidget(_app(h, '/prepare-real'));
      await _drain(tester);
      expect(find.text('Ready for a run?'), findsOneWidget);
      expect(find.text('Start a run'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(_app(h, Routes.runIntervals));
      await _drain(tester);
      expect(find.text('Total time'), findsWidgets);
      expect(find.text('28 min'), findsWidgets);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(_app(h, Routes.runWorkout));
      await _drain(tester);
      expect(find.text('Free run'), findsOneWidget);
      expect(find.text('Intervals'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        await h.start();
        await h.run(seconds: 30);
        await h.ctl.checkpointNow();
        h.container.dispose();
        h.boot(clock: h.clock, overrides: [runMapTilesEnabledProvider.overrideWithValue(false)]);
      });
      await tester.pumpWidget(_app(h, '/recovery-real'));
      await _drain(tester);
      expect(find.text('Resume as new segment'), findsOneWidget);
      expect(find.text('Missing time'), findsOneWidget);
      await tester.tap(find.text('Finish & save'));
      await _drain(tester);
      expect(find.text('RESULTS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(_app(h, '/results-real'));
      await _drain(tester);
      expect(find.text('Run complete'), findsOneWidget);
      expect(find.text('Continue to save'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => h.close());
    });
  });
}
