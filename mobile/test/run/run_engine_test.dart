import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/controller/run/engine/run_session_controller.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/models/data_models/session_state.dart';
import 'package:stride/models/ui_models/workout_models.dart';
import 'package:stride/repository/workout_repository.dart';
import 'package:stride/utils/calc/geo.dart';
import 'package:stride/utils/calc/gps_filter.dart';
import 'package:stride/utils/calc/run_metrics.dart';
import 'package:stride/utils/clock.dart';

import 'run_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RunHarness h;

  setUp(() async => h = await RunHarness.create());
  tearDown(() => h.close());

  Future<int> activityCount() async => (await h.db.db.query('activities')).length;

  group('Vòng đời phiên (G01, G02, C05)', () {
    test('mở màn chuẩn bị và đếm ngược không tạo hoạt động; Cancel quay về preparing', () async {
      h.ctl.open();
      expect(h.ctl.state.phase, SessionPhase.preparing);
      expect(h.ctl.beginCountdown(), isTrue);
      expect(h.ctl.state.phase, SessionPhase.countdown);
      h.ctl.cancelCountdown();
      expect(h.ctl.state.phase, SessionPhase.preparing);
      expect(await activityCount(), 0);
      expect(h.loc.recordingListens, 0, reason: 'không mở GPS ghi khi chỉ chuẩn bị');
    });

    test('bấm Start hai lần (đồng thời và tuần tự) chỉ tạo một phiên', () async {
      h.ctl.open();
      h.ctl.beginCountdown();
      final results = await Future.wait([h.ctl.startRecording(), h.ctl.startRecording()]);
      expect(results.whereType<Activity>().length, 1);
      expect(await h.ctl.startRecording(), isNull);
      expect(await activityCount(), 1);
      expect(h.ctl.state.phase, SessionPhase.recording);
      expect(h.loc.recordingListens, 1);
    });

    test('đã có phiên mở trong DB → RunSessionAlreadyOpen, không tạo phiên thứ hai', () async {
      await createForeignSession(h);
      h.ctl.open();
      h.ctl.beginCountdown();
      await expectLater(h.ctl.startRecording(), throwsA(isA<RunSessionAlreadyOpen>()));
      expect(await activityCount(), 1);
      expect(h.ctl.state.phase, SessionPhase.preparing);
    });

    test('mới bắt đầu: 00:00, 0 m, pace null', () async {
      await h.start();
      expect(h.ctl.movingMsNow(), 0);
      expect(h.ctl.state.distanceM, 0);
      expect(h.ctl.state.currentPaceSecPerKm, isNull);
    });
  });

  group('Timer (G02)', () {
    test('timer theo đồng hồ đơn điệu, không bị đổi giờ hệ thống', () async {
      await h.start();
      h.clock.advance(const Duration(seconds: 60));
      expect(h.ctl.movingMsNow(), 60000);
      h.clock.jumpWallClock(const Duration(hours: 1));
      expect(h.ctl.movingMsNow(), 60000);
      h.clock.jumpWallClock(const Duration(hours: -3));
      expect(h.ctl.movingMsNow(), 60000);
    });

    test('pause không cộng thời gian và quãng đường; resume mở segment mới', () async {
      await h.start();
      await h.run(seconds: 60);
      final distBefore = h.ctl.state.distanceM!;
      expect(distBefore, closeTo(177, 1)); // 60 fix → 59 đoạn × 3 m
      await h.ctl.pause();
      expect(h.ctl.state.phase, SessionPhase.paused);
      expect(h.ctl.state.pauseKind, PauseKind.manual);
      // Di chuyển 5 phút khi đang pause: không ghi điểm, không cộng thời gian.
      await h.run(seconds: 300);
      expect(h.ctl.movingMsNow(), 60000);
      expect(h.ctl.state.distanceM, distBefore);
      await h.ctl.resume();
      await h.run(seconds: 30);
      expect(h.ctl.movingMsNow(), 90000);
      // Không nối đường qua quãng di chuyển lúc pause (~900 m).
      expect(h.ctl.state.distanceM!, closeTo(177 + 87, 2));
      final segs = await h.container.read(activityRepositoryProvider).segments(h.ctl.state.activity!.id);
      expect(segs.map((s) => s.reason), [SegmentReason.start, SegmentReason.resume]);
      final a = await h.ctl.finish();
      expect(a!.movingMs, 90000);
      expect(a.elapsedMs, 390000);
    });
  });

  group('TM24: vị trí giả', () {
    late RunHarness h;
    setUp(() async => h = await RunHarness.create());
    tearDown(() async => h.close());

    test('fix từ ứng dụng giả lập → hoạt động đánh dấu locationMocked, event ghi một lần', () async {
      final started = await h.start();
      await h.run(seconds: 20);
      h.move(3);
      await h.fix(h.lat, h.lon, mocked: true);
      h.move(3);
      await h.fix(h.lat, h.lon, mocked: true);
      await h.run(seconds: 20);
      await h.ctl.pause();
      final a = await h.ctl.finish();
      expect(a!.locationMocked, isTrue);
      final events = await h.container.read(activityRepositoryProvider).events(started.id);
      expect(events.where((e) => e.type == SessionEventType.mockLocation), hasLength(1));
    });

    test('không có fix giả → locationMocked = false', () async {
      await h.start();
      await h.run(seconds: 30);
      await h.ctl.pause();
      expect((await h.ctl.finish())!.locationMocked, isFalse);
    });
  });

  group('Hồi quy: cảm biến treo (X41)', () {
    test('finish() vẫn hoàn thành khi cancel() của stream GPS và đếm bước không bao giờ trả lời', () async {
      h.loc.hangOnCancel = true;
      h.steps.hangOnCancel = true;
      await h.start();
      await h.run(seconds: 10);
      final a = await h.ctl.finish().timeout(const Duration(seconds: 10));
      expect(a, isNotNull);
      expect(a!.movingMs, 10000);
    });
  });

  group('GPS (G03, G04)', () {
    test('gap GPS > gapMs tạo segment mới và không cộng quãng đường qua gap', () async {
      await h.start();
      await h.run(seconds: 20);
      final before = h.ctl.state.distanceM!;
      // 40 s không có tín hiệu nhưng người chạy vẫn di chuyển 120 m.
      h.clock.advance(const Duration(seconds: 40));
      h.move(120);
      await h.fix(h.lat, h.lon);
      await h.run(seconds: 10);
      expect(h.ctl.state.distanceM!, closeTo(before + 30, 1));
      expect(h.ctl.state.segments.length, 2);
      final repo = h.container.read(activityRepositoryProvider);
      final segs = await repo.segments(h.ctl.state.activity!.id);
      expect(segs.last.reason, SegmentReason.gpsGap);
    });

    test('mất GPS > 15 s ghi event gpsLost, giữ vị trí cuối; có lại thì gpsRecovered', () async {
      await h.start();
      await h.run(seconds: 5);
      await h.idle(const Duration(seconds: 16));
      expect(h.ctl.state.gps.name, 'lost');
      expect(h.ctl.state.lastFix, isNotNull);
      await h.run(seconds: 2);
      final events = await h.container.read(activityRepositoryProvider).events(h.ctl.state.activity!.id);
      expect(events.map((e) => e.type), containsAllInOrder([SessionEventType.gpsLost, SessionEventType.gpsRecovered]));
    });

    test('replay fixture: điểm nhảy bị loại, km không tăng, mọi điểm vẫn được lưu', () async {
      await h.start();
      await h.run(seconds: 100);
      // Điểm nhảy 400 m sang đông rồi quay về tuyến.
      h.clock.advance(const Duration(seconds: 1));
      final (jl, jo) = offsetPoint(h.lat, h.lon, 400, 90);
      await h.fix(jl, jo);
      // Điểm sai số lớn.
      h.clock.advance(const Duration(seconds: 1));
      await h.fix(h.lat, h.lon, accuracy: 80);
      await h.run(seconds: 100);
      final a = await h.ctl.finish();
      // 200 điểm hợp lệ trên tuyến thẳng 3 m/giây → 199 đoạn; 2 điểm bị loại không cộng quãng đường.
      expect(a!.distanceM!, closeTo(597, 1));
      final pts = await h.container.read(activityRepositoryProvider).points(a.id);
      expect(pts.length, 202);
      final rejected = pts.where((p) => !p.accepted).toList();
      expect(rejected.map((p) => p.rejectReason), ['speed', 'accuracy']);
      expect(distanceOfPoints(pts), a.distanceM);
      expect(pts.map((p) => p.seq).toList(), List.generate(202, (i) => i));
    });

    test('tổng split bằng tổng quãng đường; split time cộng đúng phần có GPS', () async {
      await h.start();
      await h.run(seconds: 500, speedMps: 3.1);
      final a = await h.ctl.finish();
      final pts = await h.container.read(activityRepositoryProvider).points(a!.id);
      final splits = computeSplits(pts);
      expect(splits.length, 2);
      expect(splits.fold<double>(0, (s, x) => s + x.distanceM), closeTo(a.distanceM!, 0.01));
      final splitMs = splits.fold<int>(0, (s, x) => s + x.movingMs);
      expect((splitMs - 499000).abs(), lessThanOrEqualTo(2));
      expect(a.avgPaceSecPerKm, closeTo(500 / (a.distanceM! / 1000), 0.5));
    });
  });

  group('Checkpoint và recovery (G08)', () {
    Future<String> crashAfterRecording() async {
      await h.start();
      await h.run(seconds: 120);
      await h.ctl.checkpointNow();
      final id = h.ctl.state.activity!.id;
      // Process chết: container bị hủy không finish. Process mới có đồng hồ đơn điệu bắt đầu lại từ 0.
      h.container.dispose();
      final wall = h.clock.nowMs() + const Duration(minutes: 10).inMilliseconds;
      h.boot(clock: FakeClock(wall));
      return id;
    }

    test('Resume as new segment: thời gian app chết không tính là moving time', () async {
      final id = await crashAfterRecording();
      final info = await h.ctl.loadOpenSession();
      expect(info, isNotNull);
      expect(info!.activity.id, id);
      expect(h.ctl.state.phase, SessionPhase.recoveryNeeded);
      expect(info.movingMs, 120000);
      expect(info.distanceM!, closeTo(357, 1));
      expect(info.checkpointAt, isNotNull);

      expect(await h.ctl.recover(), isTrue);
      expect(h.ctl.state.phase, SessionPhase.recording);
      expect(h.ctl.movingMsNow(), 120000);
      h.move(1000); // vị trí mới sau khoảng thiếu
      await h.run(seconds: 60);
      expect(h.ctl.movingMsNow(), 180000);
      final a = await h.ctl.finish();
      expect(a!.movingMs, 180000);
      expect(a.distanceM!, closeTo(357 + 177, 2), reason: 'không nối đường qua khoảng thiếu');
      final repo = h.container.read(activityRepositoryProvider);
      final segs = await repo.segments(id);
      expect(segs.last.reason, SegmentReason.recovery);
      final events = await repo.events(id);
      final rec = events.firstWhere((e) => e.type == SessionEventType.recovered);
      expect(rec.data!['closeAtMono'], 120000);
    });

    test('Finish & save sau sự cố chốt tại checkpoint cuối', () async {
      await crashAfterRecording();
      await h.ctl.loadOpenSession();
      final a = await h.ctl.finishRecovered();
      expect(h.ctl.state.phase, SessionPhase.awaitingSave);
      expect(a!.movingMs, 120000);
      expect(a.status, ActivityStatus.awaitingSave);
    });

    test('rời results không lưu: mở lại app thấy draft awaitingSave', () async {
      await h.start();
      await h.run(seconds: 30);
      final a = await h.ctl.finish();
      h.container.dispose();
      h.boot(clock: FakeClock(h.clock.nowMs() + 60000));
      final info = await h.ctl.loadOpenSession();
      expect(info!.activity.id, a!.id);
      expect(h.ctl.state.phase, SessionPhase.awaitingSave);
    });
  });

  group('Thông báo giọng nói (G07)', () {
    Future<void> enableAudio() async {
      final repo = h.container.read(settingsRepositoryProvider);
      await repo.save(UserSettings(ownerId: h.owner, audioCues: const AudioCueSettings(enabled: true, everyKm: 1), weightKg: 70));
    }

    int kmCues(String n) => h.audio.spoken.where((s) => s.startsWith('$n kilometer')).length;

    test('mỗi mốc chỉ đọc một lần, kể cả sau pause/resume và recovery', () async {
      await enableAudio();
      await h.start();
      await h.run(seconds: 340); // ~1020 m
      await pumpEventQueue();
      expect(kmCues('1'), 1);
      await h.run(seconds: 10);
      await h.ctl.pause();
      await h.ctl.resume();
      await h.run(seconds: 5);
      await pumpEventQueue();
      expect(kmCues('1'), 1);
      await h.ctl.checkpointNow();
      h.container.dispose();
      h.boot(clock: FakeClock(h.clock.nowMs() + 60000));
      await h.ctl.loadOpenSession();
      await h.ctl.recover();
      await h.run(seconds: 5);
      await pumpEventQueue();
      expect(h.audio.spoken.where((s) => s.startsWith('1 kilometer')), isEmpty, reason: 'process mới không đọc lại mốc cũ');
    });

    test('calo ước tính dùng cân nặng trong settings và lưu snapshot model', () async {
      await enableAudio();
      await h.start();
      await h.run(seconds: 120);
      final a = await h.ctl.finish();
      expect(a!.caloriesKcal, isNotNull);
      expect(a.calorieModel, 'met-v1');
      expect(a.weightKgUsed, 70);
    });

    test('không có cân nặng → calo null', () async {
      await h.start();
      await h.run(seconds: 60);
      final a = await h.ctl.finish();
      expect(a!.caloriesKcal, isNull);
      expect(a.weightKgUsed, isNull);
    });
  });

  group('Auto pause (G07)', () {
    Future<void> enableAutoPause() async {
      await h.container.read(settingsRepositoryProvider).save(UserSettings(ownerId: h.owner, autoPause: true));
    }

    test('đứng yên → auto pause; chạy lại → auto resume; mất GPS không coi là đứng yên', () async {
      await enableAutoPause();
      await h.start();
      await h.run(seconds: 10);
      // Fix kém chất lượng khi đứng yên: không pause.
      await h.run(seconds: 15, speedMps: 0, accuracy: 60);
      expect(h.ctl.state.phase, SessionPhase.recording);
      await h.run(seconds: 10, speedMps: 0);
      expect(h.ctl.state.phase, SessionPhase.paused);
      expect(h.ctl.state.pauseKind, PauseKind.auto);
      await h.run(seconds: 5, speedMps: 3);
      expect(h.ctl.state.phase, SessionPhase.recording);
    });

    test('pause thủ công không tự resume khi di chuyển', () async {
      await enableAutoPause();
      await h.start();
      await h.run(seconds: 5);
      await h.ctl.pause();
      await h.run(seconds: 20, speedMps: 3);
      expect(h.ctl.state.phase, SessionPhase.paused);
      expect(h.ctl.state.pauseKind, PauseKind.manual);
    });
  });

  group('Mục tiêu, plugin, lock (G06, G09)', () {
    test('đạt mục tiêu quãng đường: báo một lần và vẫn ghi', () async {
      await h.start(goal: const RunGoal(RunGoalType.distance, 300));
      await h.run(seconds: 110);
      expect(h.ctl.state.targetReached, isTrue);
      expect(h.ctl.state.phase, SessionPhase.recording);
      await h.run(seconds: 10);
      await pumpEventQueue();
      expect(h.audio.spoken.where((s) => s.startsWith('Target reached')).length, 1);
    });

    test('plugin lỗi không làm hỏng phiên ghi', () async {
      final plugin = ThrowingPlugin();
      h.container.dispose();
      h.boot(clock: h.clock, plugins: [plugin]);
      await h.start();
      await h.run(seconds: 20);
      await pumpEventQueue();
      expect(plugin.points, greaterThan(0));
      expect(h.ctl.state.distanceM!, closeTo(57, 1));
      expect(h.ctl.state.phase, SessionPhase.recording);
    });

    test('lock không pause sensor', () async {
      await h.start();
      await h.ctl.lock();
      await h.run(seconds: 10);
      expect(h.ctl.state.locked, isTrue);
      expect(h.ctl.state.phase, SessionPhase.recording);
      expect(h.ctl.state.distanceM!, closeTo(27, 1));
      await h.ctl.unlock();
      expect(h.ctl.state.locked, isFalse);
    });
  });

  group('Save / discard (G10)', () {
    test('save lưu local, không giả Synced; ảnh được chép và gắn vào hoạt động', () async {
      await h.start();
      await h.run(seconds: 60);
      await h.ctl.finish();
      final saved = await h.ctl.save(title: '  ', feeling: Feeling.steady, notes: 'Nice', privacy: Privacy.onlyMe, photoPaths: ['/tmp/a.jpg']);
      expect(saved.status, ActivityStatus.saved);
      expect(saved.title, 'Morning run');
      expect(saved.syncState, isNot(SyncState.synced));
      expect(h.photos.imported, ['/tmp/a.jpg']);
      final att = await h.container.read(activityRepositoryProvider).attachments(saved.id);
      expect(att.length, 1);
      // Save không được làm mất track/event của hoạt động.
      expect((await h.container.read(activityRepositoryProvider).points(saved.id)).length, 60);
      expect((await h.container.read(activityRepositoryProvider).events(saved.id)), isNotEmpty);
      expect(h.ctl.state.phase, SessionPhase.saved);
    });

    test('discard xóa bản nháp', () async {
      await h.start();
      await h.run(seconds: 10);
      await h.ctl.finish();
      await h.ctl.discard();
      expect(await activityCount(), 0);
      expect(h.ctl.state.phase, SessionPhase.discarded);
    });

    test('session ngắn không GPS: distance null, hasGps false', () async {
      await h.start();
      h.clock.advance(const Duration(seconds: 20));
      final a = await h.ctl.finish();
      expect(a!.hasGps, isFalse);
      expect(a.distanceM, isNull);
      expect(a.avgPaceSecPerKm, isNull);
    });
  });

  group('Indoor run (L04)', () {
    test('không mở GPS; quãng đường từ bước cần chiều cao, nguồn steps', () async {
      await h.container.read(settingsRepositoryProvider).save(UserSettings(ownerId: h.owner, heightCm: 175));
      await h.start(type: ActivityType.indoorRun);
      expect(h.loc.recordingListens, 0);
      h.steps.controller.add(1000);
      await pumpEventQueue();
      h.clock.advance(const Duration(minutes: 10));
      final a = await h.ctl.finish();
      expect(a!.distanceSource, DistanceSource.steps);
      expect(a.hasGps, isFalse);
      expect(a.steps, 1000);
      expect(a.distanceM, closeTo(1000 * 175 * 0.415 / 100, 0.01));
    });

    test('không có chiều cao → distance null', () async {
      await h.start(type: ActivityType.indoorRun);
      h.steps.controller.add(800);
      await pumpEventQueue();
      h.clock.advance(const Duration(minutes: 5));
      final a = await h.ctl.finish();
      expect(a!.distanceM, isNull);
    });
  });

  group('Interval execution (K02, K03)', () {
    test('pha xác định bằng moving time; pause dừng tiến độ pha; kết quả pha lưu lại', () async {
      h.ctl.open();
      h.ctl.setPlan(WorkoutPlan.starter());
      await h.start();
      expect(h.ctl.state.interval!.position.index, 0);
      await h.run(seconds: 300); // hết warm-up
      expect(h.ctl.state.interval!.position.index, 1);
      expect(h.ctl.state.interval!.current!.label, 'Run 1 of 6');
      await h.ctl.pause();
      h.clock.advance(const Duration(minutes: 10));
      await h.ctl.resume();
      await h.ctl.tick();
      expect(h.ctl.state.interval!.position.index, 1, reason: 'pause không đẩy pha');
      await h.run(seconds: 120);
      expect(h.ctl.state.interval!.current!.kind, IntervalKind.walk);
      await pumpEventQueue();
      expect(h.audio.spoken.where((s) => s.startsWith('Run 1 of 6')).length, 1);
      final a = await h.ctl.finish();
      expect(h.ctl.state.workoutIncomplete, isTrue);
      final ex = await h.container.read(workoutRepositoryProvider).executionForActivity(a!.id);
      expect(ex, isNotNull);
      expect(ex!.incomplete, isTrue);
      expect(ex.phases.first.completed, isTrue);
      expect(ex.phases.fold<int>(0, (s, p) => s + p.actualMs), a.movingMs);
      expect(a.workoutExecutionId, ex.id);
    });
  });

  test('GpsFilterConfig run có gap 20 s (giả định của test gap)', () {
    expect(const GpsFilterConfig().gapMs, 20000);
  });
}

/// Tạo một phiên mở trực tiếp trong DB (như do lần chạy trước để lại).
Future<void> createForeignSession(RunHarness h) async {
  await h.container
      .read(activityRepositoryProvider)
      .createSession(ownerId: h.owner, type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
}
