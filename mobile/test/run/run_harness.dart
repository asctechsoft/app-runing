import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/permissions/permission_coordinator.dart';
import 'package:stride/core/providers.dart';
import 'package:stride/core/run_plugins.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/domain/calc/geo.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/run/engine/run_audio.dart';
import 'package:stride/features/run/engine/run_session_controller.dart';
import 'package:stride/features/run/engine/run_sources.dart';

class FakeLocationSource implements RunLocationSource {
  final controller = StreamController<RawFix>.broadcast();
  int recordingListens = 0;
  int previewListens = 0;

  @override
  Stream<RawFix> previewPositions() {
    previewListens++;
    return controller.stream;
  }

  @override
  Stream<RawFix> recordingPositions(ActivityType type) {
    recordingListens++;
    return controller.stream;
  }

  @override
  Future<RawFix?> lastKnown() async => null;

  @override
  Future<bool> openLocationSettings() async => true;
}

class FakeStepSource implements RunStepSource {
  final controller = StreamController<int?>.broadcast();
  @override
  Stream<int?> watchSteps(String ownerId, int fromMs) => controller.stream;
}

class FakeAudio implements RunAudio {
  final spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

class ThrowingPlugin extends RunPlugin {
  int points = 0;
  @override
  String get id => 'throwing';
  @override
  Future<void> onSessionStart(Activity activity) async => throw StateError('boom');
  @override
  Future<void> onPoint(Activity activity, TrackPoint point) async {
    points++;
    throw StateError('boom');
  }
}

class FakePhotoStore implements RunPhotoStore {
  final imported = <String>[];
  @override
  Future<({String path, int bytes})> importPhoto(String sourcePath, String activityId) async {
    imported.add(sourcePath);
    return (path: '/docs/$activityId/${imported.length}.jpg', bytes: 1234);
  }
}

/// Môi trường engine với DB in-memory dùng chung giữa các "process" (container) để mô phỏng crash.
class RunHarness {
  RunHarness._(this.db, this.prefs);

  final AppDatabase db;
  final SharedPreferences prefs;
  late FakeClock clock;
  late FakeLocationSource loc;
  late FakeStepSource steps;
  late FakeAudio audio;
  late FakePhotoStore photos;
  late ProviderContainer container;
  List<RunPlugin> plugins = const [];

  static Future<RunHarness> create({int startMs = 0}) async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final h = RunHarness._(db, await SharedPreferences.getInstance());
    h.boot(clock: FakeClock(startMs == 0 ? DateTime(2026, 10, 17, 7).millisecondsSinceEpoch : startMs));
    return h;
  }

  /// Khởi động một "process" mới (container mới) trên cùng DB.
  void boot({required FakeClock clock, List<RunPlugin>? plugins, List<dynamic> overrides = const []}) {
    this.clock = clock;
    loc = FakeLocationSource();
    steps = FakeStepSource();
    audio = FakeAudio();
    photos = FakePhotoStore();
    if (plugins != null) this.plugins = plugins;
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(clock),
        permissionsProvider.overrideWithValue(FakePermissionCoordinator({PermKind.location: PermStatus.granted})),
        runLocationSourceProvider.overrideWithValue(loc),
        runStepSourceProvider.overrideWithValue(steps),
        runAudioProvider.overrideWithValue(audio),
        runPhotoStoreProvider.overrideWithValue(photos),
        runPluginsProvider.overrideWithValue(this.plugins),
        runEngineConfigProvider.overrideWithValue(const RunEngineConfig(tickEvery: null, checkpointEvery: null, listenLifecycle: false)),
        ...overrides.cast(),
      ],
    );
  }

  RunSessionController get ctl => container.read(runSessionProvider.notifier);
  String get owner => container.read(ownerProvider).ownerId;

  Future<Activity> start({ActivityType type = ActivityType.run, RunGoal goal = const RunGoal.free()}) async {
    ctl.open();
    ctl.setType(type);
    ctl.setGoal(goal);
    expect(ctl.beginCountdown(), isTrue);
    final a = await ctl.startRecording();
    return a!;
  }

  // Tuyến fixture: đi về hướng bắc từ Central Park.
  double lat = 40.7812;
  double lon = -73.9665;

  /// Tiến [seconds] giây với tốc độ [speedMps], mỗi giây một fix.
  Future<void> run({int seconds = 1, double speedMps = 3, double accuracy = 5, double bearing = 0}) async {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      move(speedMps, bearing);
      await fix(lat, lon, accuracy: accuracy, speed: speedMps);
    }
  }

  /// Dời vị trí fixture [m] mét theo hướng [bearing] (không phát fix).
  void move(double m, [double bearing = 0]) {
    final (la, lo) = offsetPoint(lat, lon, m, bearing);
    lat = la;
    lon = lo;
  }

  Future<void> fix(double la, double lo, {double accuracy = 5, double? speed}) async {
    loc.controller.add(RawFix(t: clock.nowMs(), lat: la, lon: lo, accuracyM: accuracy, speedMps: speed));
    await pumpEventQueue();
    await ctl.settle();
  }

  Future<void> idle(Duration d) async {
    clock.advance(d);
    await ctl.tick();
  }

  Future<void> close() async {
    container.dispose();
    await db.close();
  }
}
