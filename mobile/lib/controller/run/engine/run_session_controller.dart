import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/logger.dart';
import '../../providers.dart';
import '../../run_plugins.dart';
import '../../../utils/clock.dart';
import '../../../presentation/common_components/buttons.dart' show OnceGuard;
import '../../../repository/activity_repository.dart';
import '../../../utils/calc/calories.dart';
import '../../../utils/calc/geo.dart';
import '../../../utils/calc/gps_filter.dart';
import '../../../utils/calc/run_metrics.dart';
import '../../../models/data_models/activity.dart';
import '../../../models/data_models/profile.dart';
import '../../../models/data_models/session_state.dart';
import '../../../models/ui_models/workout_models.dart';
import '../../../repository/workout_repository.dart';
import 'auto_pause.dart';
import 'run_audio.dart';
import 'run_session_state.dart';
import 'run_sources.dart';

/// Tham số engine; test tắt timer/lifecycle và gọi tick()/checkpointNow() trực tiếp.
class RunEngineConfig {
  const RunEngineConfig({
    this.tickEvery = const Duration(seconds: 1),
    this.checkpointEvery = const Duration(seconds: 10),
    this.pointBatchSize = 10,
    this.gpsLostAfterMs = 15000,
    this.recentWindowMs = 60000,
    this.listenLifecycle = true,
  });

  final Duration? tickEvery;
  final Duration? checkpointEvery;
  final int pointBatchSize;

  /// Không có điểm hợp lệ lâu hơn ngưỡng này (theo đồng hồ đơn điệu) → cảnh báo mất GPS.
  final int gpsLostAfterMs;
  final int recentWindowMs;
  final bool listenLifecycle;
}

final runEngineConfigProvider = Provider<RunEngineConfig>((ref) => const RunEngineConfig());

/// Đã có phiên chưa chốt — UI phải chuyển sang Recovery thay vì tạo phiên mới.
class RunSessionAlreadyOpen implements Exception {
  const RunSessionAlreadyOpen();
  @override
  String toString() => 'RunSessionAlreadyOpen';
}

/// Engine + vòng đời phiên chạy (G01–G10, K02, L04). Sống suốt app (keepAlive) để đổi màn không tạo subscription mới.
///
/// Thứ tự bắt buộc: ghi event/checkpoint vào DB TRƯỚC khi đổi state UI (G06).
/// Thời gian: đồng hồ đơn điệu tính từ lúc start của phiên ("session mono"), không đếm tick UI (G02).
class RunSessionController extends Notifier<RunSessionState> {
  @override
  RunSessionState build() {
    ref.onDispose(_disposeRuntime);
    return const RunSessionState();
  }

  ActivityRepository get _repo => ref.read(activityRepositoryProvider);
  Clock get _clock => ref.read(clockProvider);
  RunEngineConfig get _cfg => ref.read(runEngineConfigProvider);

  final _startGuard = OnceGuard();
  Future<void> _chain = Future.value();

  // ---- Runtime của phiên đang ghi ----
  List<SessionEvent> _events = const [];
  int _anchorClockMono = 0;
  int _anchorSessionMono = 0;
  TrackSegment? _segment;
  int _nextSeq = 0;
  final List<TrackPoint> _buffer = [];
  TrackPoint? _lastAccepted;
  int? _lastAcceptedSessionMono;
  RawFix? _lastRawFix;
  final List<TrackPoint> _recent = [];
  List<List<TrackPoint>> _segs = [];
  double _gpsDistance = 0;
  bool _gpsLost = false;
  int _announced = 0;
  int? _stepsTotal;
  int? _lastPhaseIndex;
  Map<int, double> _phaseDistance = {};
  UserSettings? _settings;
  AutoPauseDetector? _auto;
  RunAudioQueue? _audioQ;
  StreamSubscription<RawFix>? _posSub;
  StreamSubscription<int?>? _stepSub;
  Timer? _tickTimer;
  Timer? _cpTimer;
  AppLifecycleListener? _life;
  bool _pluginsEnded = false;
  int? _recoveryBaseMono;
  int? _recoveryCheckpointAt;
  Map<String, Object?> _recoveryExtra = const {};
  final Set<String> _importedPhotos = {};

  /// Chạy tuần tự mọi thao tác thay đổi phiên (fix GPS, pause, finish…) để không tranh chấp segment/seq.
  Future<T> _serial<T>(Future<T> Function() action) {
    final c = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        c.complete(await action());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  /// Chờ mọi thao tác đang xếp hàng xong (test/UI).
  Future<void> settle() => _serial(() async {});

  // ================= Thời gian =================

  int _sessionMonoNow() {
    final v = _anchorSessionMono + (_clock.monoMs() - _anchorClockMono);
    final last = _events.isEmpty ? 0 : _events.last.monoMs;
    return v < last ? last : v;
  }

  /// Moving time hiện tại (ms) từ event — pause không cộng, đổi giờ hệ thống không ảnh hưởng.
  int movingMsNow() {
    if (state.phase == SessionPhase.recoveryNeeded) return state.recovery?.movingMs ?? 0;
    if (!state.isActive) return state.activity?.movingMs ?? 0;
    return movingMsOf(_events, nowMono: _sessionMonoNow());
  }

  /// Thời gian từ lúc start (gồm pause, không gồm thời gian app bị dừng).
  int elapsedMsNow() => state.isActive ? _sessionMonoNow() : (state.activity?.elapsedMs ?? 0);

  // ================= Chuẩn bị =================

  /// Mở màn chuẩn bị: không tạo gì trong DB (G01).
  void open() {
    if (state.phase == SessionPhase.idle || state.phase == SessionPhase.saved || state.phase == SessionPhase.discarded) {
      _resetRuntime();
      state = RunSessionState(phase: transition(state.phase, SessionAction.open), setup: state.setup);
    }
  }

  void setType(ActivityType type) => state = state.copyWith(setup: state.setup.copyWith(type: type));
  void setGoal(RunGoal goal) => state = state.copyWith(setup: state.setup.copyWith(goal: goal));
  void setPlan(WorkoutPlan? plan) => state = state.copyWith(setup: plan == null ? state.setup.copyWith(clearPlan: true) : state.setup.copyWith(plan: plan));

  /// Start ở màn chuẩn bị → đếm ngược. Vẫn chưa tạo draft.
  bool beginCountdown() {
    if (state.phase == SessionPhase.idle) open();
    if (!canTransition(state.phase, SessionAction.start)) return false;
    state = state.copyWith(phase: transition(state.phase, SessionAction.start));
    return true;
  }

  /// Cancel khi đếm ngược: quay về chuẩn bị, không có hoạt động nào được tạo.
  void cancelCountdown() {
    if (state.phase == SessionPhase.countdown) state = state.copyWith(phase: transition(state.phase, SessionAction.cancel));
  }

  // ================= Bắt đầu ghi =================

  /// Hết đếm ngược → tạo draft đúng một lần. Gọi lặp/đồng thời trả null, không tạo phiên thứ hai.
  Future<Activity?> startRecording() async {
    final r = await _startGuard.run(() => _serial(_doStart));
    return r;
  }

  Future<Activity?> _doStart() async {
    if (state.phase != SessionPhase.countdown) return null;
    final owner = ref.read(ownerProvider).ownerId;
    _resetRuntime();
    _settings = await _loadSettings(owner);
    final setup = state.setup;
    final (Activity, TrackSegment) created;
    try {
      created = await _repo.createSession(
        ownerId: owner,
        type: setup.type,
        goal: setup.goal,
        monoMs: 0,
        tzId: currentTzId(),
        tzOffsetMin: currentTzOffsetMin(),
      );
    } on StateError {
      state = state.copyWith(phase: SessionPhase.preparing);
      throw const RunSessionAlreadyOpen();
    }
    final (a, seg) = created;
    _anchorClockMono = _clock.monoMs();
    _anchorSessionMono = 0;
    _events = await _repo.events(a.id);
    _segment = seg;
    _nextSeq = 0;
    _lastAcceptedSessionMono = null;
    state = state.copyWith(
      phase: transition(SessionPhase.countdown, SessionAction.countdownDone),
      activity: a,
      clearPauseKind: true,
      distanceM: setup.type == ActivityType.indoorRun ? null : 0,
      clearDistance: setup.type == ActivityType.indoorRun,
      clearPace: true,
      clearSteps: true,
      clearCalories: true,
      segments: const [],
      gps: setup.type == ActivityType.indoorRun ? GpsQuality.notUsed : GpsQuality.searching,
      locked: false,
      targetReached: false,
      clearInterval: true,
      clearRecovery: true,
      clearPhaseResults: true,
      workoutIncomplete: false,
    );
    await _checkpoint();
    _startSensors();
    _plugins((p) => p.onSessionStart(a));
    await _evaluateProgress();
    return a;
  }

  Future<UserSettings?> _loadSettings(String owner) async {
    try {
      return await ref.read(settingsRepositoryProvider).load(owner);
    } catch (e, st) {
      StrideLog.e('run.settings', e, st);
      return null;
    }
  }

  // ================= Sensor =================

  void _startSensors() {
    final a = state.activity!;
    final indoor = a.type == ActivityType.indoorRun;
    if (!indoor) {
      _posSub = ref
          .read(runLocationSourceProvider)
          .recordingPositions(a.type)
          .listen(
            (f) => _serial(() => _onFix(f)).catchError((Object e, StackTrace st) => StrideLog.e('run.fix', e, st)),
            onError: (Object e, StackTrace st) {
              StrideLog.e('run.gps', e, st);
              _serial(() async {
                if (state.isActive) state = state.copyWith(gps: GpsQuality.lost);
              });
            },
          );
    }
    _stepSub = ref.read(runStepSourceProvider).watchSteps(a.ownerId, a.startedAt).listen((s) {
      _stepsTotal = s;
      if (state.isActive) _emitMetrics();
    }, onError: (Object e, StackTrace st) => StrideLog.e('run.steps', e, st));
    final cfg = _cfg;
    if (cfg.tickEvery != null) {
      _tickTimer = Timer.periodic(cfg.tickEvery!, (_) => _serial(_onTick).catchError((Object e, StackTrace st) => StrideLog.e('run.tick', e, st)));
    }
    if (cfg.checkpointEvery != null) {
      _cpTimer = Timer.periodic(
        cfg.checkpointEvery!,
        (_) => _serial(_checkpointIfActive).catchError((Object e, StackTrace st) => StrideLog.e('run.cp', e, st)),
      );
    }
    if (cfg.listenLifecycle && _life == null) {
      try {
        // App xuống nền/bị đóng: flush điểm + checkpoint ngay (G05, G08).
        _life = AppLifecycleListener(
          onPause: () => _serial(_checkpointIfActive),
          onHide: () => _serial(_checkpointIfActive),
          onDetach: () => _serial(_checkpointIfActive),
        );
      } catch (e, st) {
        StrideLog.e('run.lifecycle', e, st);
      }
    }
    _audioQ ??= RunAudioQueue(ref.read(runAudioProvider));
    _auto = (_settings?.autoPause ?? false) && !indoor ? AutoPauseDetector.forType(a.type) : null;
  }

  Future<void> _stopSensors() async {
    await _posSub?.cancel();
    _posSub = null;
    await _stepSub?.cancel();
    _stepSub = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _cpTimer?.cancel();
    _cpTimer = null;
    _life?.dispose();
    _life = null;
  }

  void _disposeRuntime() {
    _posSub?.cancel();
    _stepSub?.cancel();
    _tickTimer?.cancel();
    _cpTimer?.cancel();
    _life?.dispose();
    _audioQ?.clear();
  }

  void _resetRuntime() {
    _events = const [];
    _segment = null;
    _nextSeq = 0;
    _buffer.clear();
    _lastAccepted = null;
    _lastAcceptedSessionMono = null;
    _lastRawFix = null;
    _recent.clear();
    _segs = [];
    _gpsDistance = 0;
    _gpsLost = false;
    _announced = 0;
    _stepsTotal = null;
    _lastPhaseIndex = null;
    _phaseDistance = {};
    _pluginsEnded = false;
    _recoveryBaseMono = null;
    _recoveryCheckpointAt = null;
    _recoveryExtra = const {};
    _importedPhotos.clear();
    _auto = null;
  }

  GpsFilterConfig get _filter => GpsFilterConfig.forType(state.setup.type);

  /// Xử lý một fix (G03): lọc, lưu mọi điểm (accepted + lý do loại), segment mới khi gap.
  Future<void> _onFix(RawFix f) async {
    final prevRaw = _lastRawFix;
    _lastRawFix = f;
    final a = state.activity;
    if (a == null || !state.isActive) return;
    final cfg = _filter;
    var gps = state.gps;
    final shown = TrackPoint(activityId: a.id, segmentId: _segment?.id ?? '', seq: -1, t: f.t, lat: f.lat, lon: f.lon, accuracyM: f.accuracyM);

    if (state.phase == SessionPhase.recording) {
      var segId = _segment!.id;
      // Khoảng không có điểm hợp lệ dài hơn gapMs → segment mới, không nối polyline qua khoảng thiếu.
      if (_lastAccepted != null && f.t - _lastAccepted!.t > cfg.gapMs) {
        await _flushPoints();
        await _appendEvent(SessionEventType.gpsRecovered, openSegment: SegmentReason.gpsGap, data: {'gapMs': f.t - _lastAccepted!.t});
        _segment = await _repo.currentSegment(a.id);
        segId = _segment!.id;
        _lastAccepted = null;
        _recent.clear();
        _gpsLost = false;
      }
      final cand = TrackPoint(
        activityId: a.id,
        segmentId: segId,
        seq: _nextSeq,
        t: f.t,
        lat: f.lat,
        lon: f.lon,
        accuracyM: f.accuracyM,
        altitudeM: f.altitudeM,
        speedMps: f.speedMps,
      );
      final d = evaluatePoint(candidate: cand, lastAccepted: _lastAccepted, config: cfg);
      final point = cand.copyWith(accepted: d.accepted, rejectReason: d.reason);
      _nextSeq++;
      _buffer.add(point);
      if (_buffer.length >= _cfg.pointBatchSize) await _flushPoints();
      if (point.accepted) {
        if (_gpsLost) {
          _gpsLost = false;
          await _appendEvent(SessionEventType.gpsRecovered);
        }
        final last = _lastAccepted;
        if (last != null && last.segmentId == point.segmentId) {
          _gpsDistance += haversineM(last.lat, last.lon, point.lat, point.lon);
        }
        if (_segs.isEmpty || _segs.last.isEmpty || _segs.last.last.segmentId != point.segmentId) {
          _segs = [..._segs, <TrackPoint>[]];
        }
        _segs.last.add(point);
        _recent.add(point);
        _recent.removeWhere((p) => point.t - p.t > _cfg.recentWindowMs);
        _lastAccepted = point;
        _lastAcceptedSessionMono = _sessionMonoNow();
        gps = qualityForAccuracy(f.accuracyM);
        _plugins((p) => p.onPoint(a, point));
      } else {
        gps = d.reason == 'accuracy' ? GpsQuality.weak : (gps == GpsQuality.searching ? GpsQuality.weak : gps);
      }
    } else {
      gps = qualityForAccuracy(f.accuracyM);
    }

    state = state.copyWith(lastFix: shown, lastFixWallMs: _clock.nowMs(), gps: _gpsLost ? GpsQuality.lost : gps);

    // Auto pause: chỉ dựa fix đủ chính xác; mất GPS không bị coi là đứng yên (G07).
    final auto = _auto;
    if (auto != null && (state.phase == SessionPhase.recording || (state.phase == SessionPhase.paused && state.pauseKind == PauseKind.auto))) {
      double? speed = f.speedMps;
      if (speed == null && prevRaw != null && f.t > prevRaw.t) {
        speed = haversineM(prevRaw.lat, prevRaw.lon, f.lat, f.lon) / ((f.t - prevRaw.t) / 1000);
      }
      final reliable = f.accuracyM != null && f.accuracyM! <= cfg.maxAccuracyM;
      final sig = auto.feed(t: f.t, speedMps: speed, reliable: reliable, autoPaused: state.phase == SessionPhase.paused);
      if (sig == AutoPauseSignal.pause) {
        await _doPause(manual: false);
      } else if (sig == AutoPauseSignal.resume) {
        await _doResume(auto: true);
      }
    }
    if (state.phase == SessionPhase.recording) {
      _emitMetrics();
      await _evaluateProgress();
    }
  }

  Future<void> _flushPoints() async {
    if (_buffer.isEmpty) return;
    final batch = List<TrackPoint>.of(_buffer);
    _buffer.clear();
    try {
      await _repo.insertPoints(batch);
    } catch (e, st) {
      StrideLog.e('run.points', e, st);
      _buffer.insertAll(0, batch);
    }
  }

  double? _stepDistance() {
    final s = _stepsTotal;
    if (s == null) return null;
    return stepDistanceM(steps: s, heightCm: _settings?.heightCm);
  }

  double? _currentDistance() {
    if (state.setup.type == ActivityType.indoorRun) return _stepDistance();
    return _gpsDistance;
  }

  void _emitMetrics() {
    final indoor = state.setup.type == ActivityType.indoorRun;
    final dist = _currentDistance();
    final moving = movingMsNow();
    final pace = indoor ? null : (state.phase == SessionPhase.recording ? currentPaceSecPerKm(_recent) : null);
    final kcal = estimateCalories(type: state.setup.type, weightKg: _settings?.weightKg, movingMs: moving, distanceM: dist);
    state = state.copyWith(
      distanceM: dist,
      clearDistance: dist == null,
      currentPaceSecPerKm: pace,
      clearPace: pace == null,
      steps: _stepsTotal,
      clearSteps: _stepsTotal == null,
      caloriesKcal: kcal,
      clearCalories: kcal == null,
      segments: _segs,
    );
  }

  // ================= Tick, mục tiêu, thông báo, interval =================

  /// Tick engine (1 s): phát hiện mất GPS, tiến độ goal/interval. Public để test gọi trực tiếp.
  @visibleForTesting
  Future<void> tick() => _serial(_onTick);

  Future<void> _onTick() async {
    if (state.phase != SessionPhase.recording) return;
    if (state.setup.type != ActivityType.indoorRun) {
      final since = _lastAcceptedSessionMono;
      if (since != null && !_gpsLost && _sessionMonoNow() - since > _cfg.gpsLostAfterMs) {
        await _flushPoints();
        final last = _lastAccepted;
        await _appendEvent(SessionEventType.gpsLost, data: last == null ? null : {'lat': last.lat, 'lon': last.lon, 't': last.t});
        _gpsLost = true;
        state = state.copyWith(gps: GpsQuality.lost);
        await _checkpoint();
      }
    }
    _emitMetrics();
    await _evaluateProgress();
  }

  void _speak(String text) {
    try {
      (_audioQ ??= RunAudioQueue(ref.read(runAudioProvider))).enqueue(text);
    } catch (e, st) {
      StrideLog.e('run.audio', e, st);
    }
  }

  void _haptic() {
    try {
      unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
    } catch (_) {}
  }

  Future<void> _evaluateProgress() async {
    if (state.phase != SessionPhase.recording) return;
    final moving = movingMsNow();
    final dist = _currentDistance();
    var changed = false;

    // Đạt mục tiêu buổi chạy: báo một lần và tiếp tục ghi (G09).
    final g = state.setup.goal;
    if (!state.targetReached && g.type != RunGoalType.free && g.value != null) {
      final reached = g.type == RunGoalType.distance ? (dist != null && dist >= g.value!) : moving >= g.value!;
      if (reached) {
        state = state.copyWith(targetReached: true);
        _speak('Target reached. Keep going, or finish when you are ready.');
        _haptic();
        changed = true;
      }
    }

    // Mốc quãng đường: mỗi mốc đọc đúng một lần; mốc đã đọc lưu trong checkpoint (G07).
    final s = _settings;
    if (s != null && s.audioCues.enabled) {
      final every = milestoneMeters(s.audioCues, s.distanceUnit);
      final m = nextMilestone(distanceM: dist, everyM: every, announced: _announced);
      if (m != null) {
        _announced = m;
        _speak(
          milestoneSpeech(
            milestone: m,
            everyUnits: s.audioCues.everyKm,
            unit: s.distanceUnit,
            movingMs: moving,
            avgPaceSecPerKm: avgPaceSecPerKm(movingMs: moving, distanceM: dist),
            cues: s.audioCues,
          ),
        );
        changed = true;
      }
    }

    // Interval: pha xác định bằng moving time; event phaseStart lưu trước khi báo (K02).
    final plan = state.setup.plan;
    if (plan != null) {
      final phases = plan.phases;
      final pos = phaseAt(phases, moving);
      if (_lastPhaseIndex == null || pos.index > _lastPhaseIndex!) {
        final done = pos.index >= phases.length;
        await _appendEvent(SessionEventType.phaseStart, data: {'index': pos.index, 'distanceM': dist, 'done': done});
        if (dist != null) _phaseDistance[pos.index] = dist;
        _lastPhaseIndex = pos.index;
        if (plan.audioCues) {
          _speak(done ? 'Workout complete. Keep going, or finish when you are ready.' : phaseSpeech(phases[pos.index].label, phases[pos.index].plannedMs));
        }
        _haptic();
        changed = true;
      }
      state = state.copyWith(
        interval: IntervalStatus(phases: phases, position: pos),
      );
    }
    if (changed) await _checkpoint();
  }

  // ================= Checkpoint =================

  Future<void> _checkpointIfActive() async {
    if (state.isActive) await _checkpoint();
  }

  @visibleForTesting
  Future<void> checkpointNow() => _serial(_checkpointIfActive);

  Future<void> _checkpoint() async {
    final a = state.activity;
    if (a == null) return;
    await _flushPoints();
    await _repo.checkpoint(
      activityId: a.id,
      phase: state.phase.name,
      movingMs: movingMsNow(),
      distanceM: _currentDistance() ?? 0,
      steps: _stepsTotal,
      hasGps: _segs.any((s) => s.isNotEmpty),
      lastPointSeq: _nextSeq > 0 ? _nextSeq - 1 : null,
      lastEventSeq: _events.isEmpty ? null : _events.last.seq,
      extraJson: jsonEncode({
        'monoMs': _sessionMonoNow(),
        'announced': _announced,
        'targetReached': state.targetReached,
        'pauseKind': state.pauseKind?.name,
        'plan': state.setup.plan?.toJson(),
      }),
    );
  }

  Future<SessionEvent> _appendEvent(
    SessionEventType type, {
    ActivityStatus? newStatus,
    SegmentReason? openSegment,
    Map<String, Object?>? data,
    int? monoMs,
  }) async {
    final e = await _repo.appendEvent(
      activityId: state.activity!.id,
      type: type,
      monoMs: monoMs ?? _sessionMonoNow(),
      newStatus: newStatus,
      openSegment: openSegment,
      data: data,
    );
    _events = [..._events, e];
    return e;
  }

  void _plugins(Future<void> Function(RunPlugin p) call) {
    final List<RunPlugin> plugins;
    try {
      plugins = ref.read(runPluginsProvider);
    } catch (e, st) {
      StrideLog.e('run.plugins', e, st);
      return;
    }
    for (final p in plugins) {
      // Lỗi plugin không bao giờ làm hỏng phiên ghi.
      unawaited(
        Future<void>(() => call(p)).timeout(const Duration(seconds: 5)).catchError((Object e, StackTrace st) {
          StrideLog.e('run.plugin.${p.id}', e, st);
        }),
      );
    }
  }

  // ================= Pause / resume / lock =================

  Future<void> pause() => _serial(() => _doPause(manual: true));

  Future<void> _doPause({required bool manual}) async {
    if (state.phase == SessionPhase.recording) {
      transition(state.phase, manual ? SessionAction.pause : SessionAction.autoPause);
      await _flushPoints();
      await _appendEvent(manual ? SessionEventType.pause : SessionEventType.autoPause, newStatus: ActivityStatus.paused);
      _auto?.reset();
      state = state.copyWith(phase: SessionPhase.paused, pauseKind: manual ? PauseKind.manual : PauseKind.auto, clearPace: true);
      await _checkpoint();
      final a = state.activity!;
      _plugins((p) => p.onPause(a));
    } else if (manual && state.phase == SessionPhase.paused && state.pauseKind == PauseKind.auto) {
      // Người dùng bấm Pause khi đang auto-pause → thành pause thủ công, chỉ người dùng mới resume.
      await _appendEvent(SessionEventType.pause);
      state = state.copyWith(pauseKind: PauseKind.manual);
      await _checkpoint();
    }
  }

  Future<void> resume() => _serial(() => _doResume(auto: false));

  Future<void> _doResume({required bool auto}) async {
    if (state.phase != SessionPhase.paused) return;
    // Pause thủ công không bao giờ tự resume (G07).
    if (auto && state.pauseKind != PauseKind.auto) return;
    transition(state.phase, auto ? SessionAction.autoResume : SessionAction.resume);
    await _appendEvent(auto ? SessionEventType.autoResume : SessionEventType.resume, newStatus: ActivityStatus.recording, openSegment: SegmentReason.resume);
    final a = state.activity!;
    _segment = await _repo.currentSegment(a.id);
    _lastAccepted = null;
    _recent.clear();
    _gpsLost = false;
    _lastAcceptedSessionMono = _sessionMonoNow();
    _auto?.reset();
    state = state.copyWith(phase: SessionPhase.recording, clearPauseKind: true, gps: state.isIndoor ? GpsQuality.notUsed : GpsQuality.searching);
    await _checkpoint();
    _plugins((p) => p.onResume(a));
  }

  /// Khóa chỉ khóa thao tác — sensor và ghi vẫn chạy (G06).
  Future<void> lock() => _serial(() async {
    if (!state.isActive || state.locked) return;
    await _appendEvent(SessionEventType.lock);
    state = state.copyWith(locked: true);
  });

  Future<void> unlock() => _serial(() async {
    if (!state.locked) return;
    if (state.activity != null && state.isActive) await _appendEvent(SessionEventType.unlock);
    state = state.copyWith(locked: false);
  });

  // ================= Finish / save / discard =================

  /// Finish: chốt một lần, ngừng sensor, tính summary → awaitingSave.
  Future<Activity?> finish() => _serial(() async {
    if (state.phase == SessionPhase.recording) await _doPause(manual: true);
    if (state.phase != SessionPhase.paused) return state.activity;
    transition(state.phase, SessionAction.finish);
    await _flushPoints();
    await _appendEvent(SessionEventType.finish);
    return _completeFinish();
  });

  Future<Activity> _completeFinish() async {
    await _stopSensors();
    _audioQ?.clear();
    final summary = await _buildSummary();
    final saved = await _repo.finalizeSummary(summary);
    state = state.copyWith(
      phase: SessionPhase.awaitingSave,
      activity: saved,
      distanceM: saved.distanceM,
      clearDistance: saved.distanceM == null,
      steps: saved.steps,
      clearSteps: saved.steps == null,
      caloriesKcal: saved.caloriesKcal,
      clearCalories: saved.caloriesKcal == null,
      clearPace: true,
      locked: false,
      clearPauseKind: true,
      clearRecovery: true,
    );
    if (!_pluginsEnded) {
      _pluginsEnded = true;
      _plugins((p) => p.onSessionEnd(saved, discarded: false));
    }
    return saved;
  }

  Future<Activity> _buildSummary() async {
    final a = state.activity!;
    final indoor = a.type == ActivityType.indoorRun;
    final pts = await _repo.points(a.id);
    final hasGps = !indoor && pts.any((p) => p.accepted);
    final moving = movingMsOf(_events);
    final elapsed = _events.isEmpty ? 0 : _events.last.monoMs;
    final double? distance = indoor ? _stepDistance() : (hasGps ? distanceOfPoints(pts) : null);
    final weight = _settings?.weightKg;
    final kcal = estimateCalories(type: a.type, weightKg: weight, movingMs: moving, distanceM: distance);
    final pace = avgPaceSecPerKm(movingMs: moving, distanceM: distance);

    String? executionId;
    final plan = state.setup.plan;
    if (plan != null) {
      final results = computePhaseResults(plan.phases, movingMs: moving, distanceAtStart: _phaseDistance, totalDistanceM: distance);
      final incomplete = results.isEmpty || results.any((r) => !r.completed);
      try {
        executionId = await ref
            .read(workoutRepositoryProvider)
            .saveExecution(activityId: a.id, plan: plan, phases: results, currentPhase: _lastPhaseIndex ?? 0, incomplete: incomplete);
      } catch (e, st) {
        StrideLog.e('run.workout', e, st);
      }
      state = state.copyWith(phaseResults: results, workoutIncomplete: incomplete);
    }

    return Activity(
      id: a.id,
      ownerId: a.ownerId,
      type: a.type,
      status: ActivityStatus.awaitingSave,
      startedAt: a.startedAt,
      endedAt: _clock.nowMs(),
      tzId: a.tzId,
      tzOffsetMin: a.tzOffsetMin,
      distanceM: distance,
      movingMs: moving,
      elapsedMs: elapsed < moving ? moving : elapsed,
      avgPaceSecPerKm: pace,
      steps: _stepsTotal,
      caloriesKcal: kcal,
      calorieModel: kcal == null ? null : calorieModelId,
      weightKgUsed: kcal == null ? null : weight,
      title: a.title.isNotEmpty ? a.title : defaultActivityTitle(a.type, DateTime.fromMillisecondsSinceEpoch(a.startedAt)),
      privacy: a.privacy,
      goal: a.goal,
      hasGps: hasGps,
      distanceSource: indoor ? DistanceSource.steps : DistanceSource.gps,
      workoutExecutionId: executionId,
      syncState: a.syncState,
      revision: a.revision,
      createdAt: a.createdAt,
      updatedAt: _clock.nowMs(),
    );
  }

  /// Lưu local trước (offline OK). Lỗi → giữ draft nguyên trạng để Retry (G10).
  Future<Activity> save({required String title, Feeling? feeling, String? notes, required Privacy privacy, List<String> photoPaths = const []}) =>
      _serial(() async {
        if (state.phase != SessionPhase.awaitingSave || state.activity == null) throw StateError('not-awaiting-save');
        final a = state.activity!;
        final store = ref.read(runPhotoStoreProvider);
        for (final path in photoPaths) {
          if (_importedPhotos.contains(path)) continue;
          final imported = await store.importPhoto(path, a.id);
          await _repo.addAttachment(activityId: a.id, ownerId: a.ownerId, localPath: imported.path, mime: mimeForPath(path), bytes: imported.bytes);
          _importedPhotos.add(path);
        }
        final owner = ref.read(ownerProvider);
        final enqueue = ref.read(flagsProvider).sync && !owner.isGuest;
        final trimmed = title.trim();
        final next = a.copyWith(
          title: trimmed.isEmpty ? defaultActivityTitle(a.type, DateTime.fromMillisecondsSinceEpoch(a.startedAt)) : trimmed,
          feeling: feeling,
          notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
          privacy: privacy,
        );
        final saved = await _repo.saveActivity(next, enqueueSync: enqueue);
        state = state.copyWith(phase: transition(SessionPhase.awaitingSave, SessionAction.save), activity: saved);
        return saved;
      });

  /// Bỏ bản nháp (đã xác nhận ở UI). Khác xóa hoạt động đã lưu.
  Future<void> discard() => _serial(() async {
    final a = state.activity;
    if (a == null) return;
    if (!canTransition(state.phase, SessionAction.discard) && !state.isActive) return;
    await _stopSensors();
    _audioQ?.clear();
    _buffer.clear();
    await _repo.discardDraft(a.id);
    if (!_pluginsEnded) {
      _pluginsEnded = true;
      _plugins((p) => p.onSessionEnd(a, discarded: true));
    }
    final setup = state.setup;
    _resetRuntime();
    state = RunSessionState(phase: SessionPhase.discarded, setup: setup);
  });

  /// Rời màn Saved: về idle, giữ lựa chọn chuẩn bị.
  void reset() {
    if (state.isActive || state.phase == SessionPhase.awaitingSave || state.phase == SessionPhase.recoveryNeeded) return;
    _resetRuntime();
    state = RunSessionState(setup: state.setup);
  }

  // ================= Recovery (G08) =================

  /// Tìm phiên chưa chốt trong DB. Không đụng tới phiên đang chạy trong bộ nhớ.
  Future<RecoveryInfo?> loadOpenSession() => _serial(() async {
    if (state.isActive) return null;
    final current = state.activity;
    if (current != null && (state.phase == SessionPhase.awaitingSave || state.phase == SessionPhase.recoveryNeeded)) {
      return state.recovery ?? RecoveryInfo(activity: current, checkpointAt: null, movingMs: current.movingMs, distanceM: current.distanceM, lastPointAt: null);
    }
    final owner = ref.read(ownerProvider).ownerId;
    final a = await _repo.detectUnclosedSession(owner);
    if (a == null) return null;
    _resetRuntime();
    final cp = await _repo.loadCheckpoint(a.id);
    Map<String, Object?> extra = const {};
    final rawExtra = cp?['extra_json'] as String?;
    if (rawExtra != null) {
      try {
        extra = (jsonDecode(rawExtra) as Map).cast<String, Object?>();
      } catch (_) {}
    }
    _recoveryExtra = extra;
    WorkoutPlan? plan;
    if (extra['plan'] is Map) {
      try {
        plan = WorkoutPlan.fromJson((extra['plan'] as Map).cast<String, Object?>());
      } catch (_) {}
    }
    _settings = await _loadSettings(owner);
    final setup = RunSetup(type: a.type, goal: a.goal, plan: plan);
    _events = await _repo.events(a.id);
    final pts = await _repo.points(a.id);

    if (a.status == ActivityStatus.awaitingSave) {
      List<PhaseResult>? results;
      var incomplete = false;
      try {
        final ex = await ref.read(workoutRepositoryProvider).executionForActivity(a.id);
        results = ex?.phases;
        incomplete = ex?.incomplete ?? false;
      } catch (_) {}
      final info = RecoveryInfo(
        activity: a,
        checkpointAt: cp?['saved_at'] as int?,
        movingMs: a.movingMs,
        distanceM: a.distanceM,
        lastPointAt: pts.isEmpty ? null : pts.last.t,
      );
      state = RunSessionState(
        phase: SessionPhase.awaitingSave,
        setup: setup,
        activity: a,
        distanceM: a.distanceM,
        steps: a.steps,
        caloriesKcal: a.caloriesKcal,
        segments: polylinesBySegment(pts),
        gps: a.type == ActivityType.indoorRun ? GpsQuality.notUsed : GpsQuality.searching,
        recovery: info,
        phaseResults: results,
        workoutIncomplete: incomplete,
      );
      _pluginsEnded = true;
      return info;
    }

    // Mốc đơn điệu cuối cùng có dữ liệu: checkpoint hoặc event sau cùng. Thời gian sau mốc này (app chết) không tính.
    final cpMono = (extra['monoMs'] as num?)?.toInt() ?? 0;
    final lastEventMono = _events.isEmpty ? 0 : _events.last.monoMs;
    final base = cpMono > lastEventMono ? cpMono : lastEventMono;
    _recoveryBaseMono = base;
    _recoveryCheckpointAt = cp?['saved_at'] as int?;
    final moving = movingMsOf(_events, nowMono: base);
    final indoor = a.type == ActivityType.indoorRun;
    final hasPts = pts.any((p) => p.accepted);
    final double? distance = indoor ? (cp?['distance_m'] as num?)?.toDouble() : (hasPts ? distanceOfPoints(pts) : (cp == null ? null : 0));
    _stepsTotal = a.steps;
    final info = RecoveryInfo(
      activity: a,
      checkpointAt: _recoveryCheckpointAt,
      movingMs: moving,
      distanceM: distance,
      lastPointAt: pts.isEmpty ? null : pts.last.t,
    );
    state = RunSessionState(
      phase: SessionPhase.recoveryNeeded,
      setup: setup,
      activity: a,
      distanceM: distance,
      steps: a.steps,
      segments: polylinesBySegment(pts),
      gps: indoor ? GpsQuality.notUsed : GpsQuality.searching,
      targetReached: extra['targetReached'] as bool? ?? false,
      recovery: info,
    );
    return info;
  });

  void _restoreFromEvents(List<TrackPoint> pts) {
    _segs = polylinesBySegment(pts);
    _gpsDistance = distanceOfPoints(pts);
    _announced = (_recoveryExtra['announced'] as num?)?.toInt() ?? 0;
    _phaseDistance = {};
    _lastPhaseIndex = null;
    for (final e in _events) {
      if (e.type != SessionEventType.phaseStart) continue;
      final idx = (e.data?['index'] as num?)?.toInt();
      if (idx == null) continue;
      _lastPhaseIndex = idx;
      final d = (e.data?['distanceM'] as num?)?.toDouble();
      if (d != null) _phaseDistance[idx] = d;
    }
  }

  /// Resume as new segment: event recovered đóng khoảng cũ tại checkpoint cuối → thời gian chết không thành moving time.
  Future<bool> recover() => _serial(() async {
    if (state.phase != SessionPhase.recoveryNeeded || state.activity == null) return false;
    final a = state.activity!;
    final base = _recoveryBaseMono ?? (_events.isEmpty ? 0 : _events.last.monoMs);
    _anchorSessionMono = base;
    _anchorClockMono = _clock.monoMs();
    await _appendEvent(
      SessionEventType.recovered,
      monoMs: base,
      newStatus: ActivityStatus.recording,
      openSegment: SegmentReason.recovery,
      data: {'closeAtMono': base, 'checkpointAt': _recoveryCheckpointAt},
    );
    _segment = await _repo.currentSegment(a.id);
    final pts = await _repo.points(a.id);
    _nextSeq = await _repo.nextPointSeq(a.id);
    _restoreFromEvents(pts);
    _lastAccepted = null;
    _lastAcceptedSessionMono = base;
    state = state.copyWith(
      phase: transition(SessionPhase.recoveryNeeded, SessionAction.recover),
      activity: a.copyWith(status: ActivityStatus.recording),
      clearPauseKind: true,
      segments: _segs,
      clearRecovery: true,
    );
    await _checkpoint();
    _startSensors();
    _plugins((p) => p.onSessionStart(a));
    await _evaluateProgress();
    return true;
  });

  /// Finish & save sau sự cố: chốt tại checkpoint cuối, không cộng thời gian app chết.
  Future<Activity?> finishRecovered() => _serial(() async {
    if (state.phase != SessionPhase.recoveryNeeded || state.activity == null) return null;
    final base = _recoveryBaseMono ?? (_events.isEmpty ? 0 : _events.last.monoMs);
    _anchorSessionMono = base;
    _anchorClockMono = _clock.monoMs();
    final pts = await _repo.points(state.activity!.id);
    _restoreFromEvents(pts);
    await _appendEvent(SessionEventType.finish, monoMs: base, data: {'closeAtMono': base, 'afterCrash': true});
    _pluginsEnded = true;
    return _completeFinish();
  });
}

final runSessionProvider = NotifierProvider<RunSessionController, RunSessionState>(RunSessionController.new);
