import '../../../models/data_models/activity.dart';
import '../../../models/data_models/session_state.dart';
import '../../../models/ui_models/workout_models.dart';
import '../../../utils/l10n.dart';
import 'run_sources.dart';

/// Lựa chọn ở màn chuẩn bị — chưa ghi gì vào DB (G01).
class RunSetup {
  const RunSetup({this.type = ActivityType.run, this.goal = const RunGoal.free(), this.plan});

  final ActivityType type;
  final RunGoal goal;

  /// null = Free run.
  final WorkoutPlan? plan;

  RunSetup copyWith({ActivityType? type, RunGoal? goal, WorkoutPlan? plan, bool clearPlan = false}) =>
      RunSetup(type: type ?? this.type, goal: goal ?? this.goal, plan: clearPlan ? null : (plan ?? this.plan));
}

/// Tiến độ interval hiện tại.
class IntervalStatus {
  const IntervalStatus({required this.phases, required this.position});
  final List<PlannedPhase> phases;
  final PhasePosition position;

  bool get done => position.index >= phases.length;
  PlannedPhase? get current => done ? null : phases[position.index];
  PlannedPhase? get next => position.index + 1 < phases.length ? phases[position.index + 1] : null;
}

/// Thông tin phiên chưa chốt để hiển thị ở Recovery (G08).
class RecoveryInfo {
  const RecoveryInfo({required this.activity, required this.checkpointAt, required this.movingMs, required this.distanceM, required this.lastPointAt});

  final Activity activity;

  /// UTC ms của checkpoint cuối (null nếu chưa kịp checkpoint).
  final int? checkpointAt;
  final int movingMs;
  final double? distanceM;
  final int? lastPointAt;
}

/// Snapshot trạng thái phiên cho UI. Thời gian chạy đọc qua controller.movingMsNow() (đồng hồ đơn điệu).
class RunSessionState {
  const RunSessionState({
    this.phase = SessionPhase.idle,
    this.setup = const RunSetup(),
    this.activity,
    this.pauseKind,
    this.distanceM,
    this.currentPaceSecPerKm,
    this.steps,
    this.caloriesKcal,
    this.segments = const [],
    this.lastFix,
    this.lastFixWallMs,
    this.gps = GpsQuality.searching,
    this.locked = false,
    this.targetReached = false,
    this.interval,
    this.recovery,
    this.phaseResults,
    this.workoutIncomplete = false,
    this.revision = 0,
  });

  final SessionPhase phase;
  final RunSetup setup;

  /// Draft (khi đang ghi) hoặc summary (awaitingSave) hoặc bản đã lưu.
  final Activity? activity;
  final PauseKind? pauseKind;

  /// null khi không đo được (vd. indoor không có chiều cao) → "—".
  final double? distanceM;
  final double? currentPaceSecPerKm;
  final int? steps;
  final double? caloriesKcal;

  /// Điểm accepted theo segment — vẽ polyline tách rời qua gap/pause.
  final List<List<TrackPoint>> segments;

  /// Fix gần nhất (có thể là vị trí cũ khi mất GPS).
  final TrackPoint? lastFix;
  final int? lastFixWallMs;
  final GpsQuality gps;
  final bool locked;
  final bool targetReached;
  final IntervalStatus? interval;
  final RecoveryInfo? recovery;

  /// Kết quả interval sau Finish (K03).
  final List<PhaseResult>? phaseResults;
  final bool workoutIncomplete;
  final int revision;

  bool get isActive => phase == SessionPhase.recording || phase == SessionPhase.paused;
  bool get isIndoor => setup.type == ActivityType.indoorRun;

  RunSessionState copyWith({
    SessionPhase? phase,
    RunSetup? setup,
    Activity? activity,
    bool clearActivity = false,
    PauseKind? pauseKind,
    bool clearPauseKind = false,
    double? distanceM,
    bool clearDistance = false,
    double? currentPaceSecPerKm,
    bool clearPace = false,
    int? steps,
    bool clearSteps = false,
    double? caloriesKcal,
    bool clearCalories = false,
    List<List<TrackPoint>>? segments,
    TrackPoint? lastFix,
    bool clearLastFix = false,
    int? lastFixWallMs,
    GpsQuality? gps,
    bool? locked,
    bool? targetReached,
    IntervalStatus? interval,
    bool clearInterval = false,
    RecoveryInfo? recovery,
    bool clearRecovery = false,
    List<PhaseResult>? phaseResults,
    bool clearPhaseResults = false,
    bool? workoutIncomplete,
  }) => RunSessionState(
    phase: phase ?? this.phase,
    setup: setup ?? this.setup,
    activity: clearActivity ? null : (activity ?? this.activity),
    pauseKind: clearPauseKind ? null : (pauseKind ?? this.pauseKind),
    distanceM: clearDistance ? null : (distanceM ?? this.distanceM),
    currentPaceSecPerKm: clearPace ? null : (currentPaceSecPerKm ?? this.currentPaceSecPerKm),
    steps: clearSteps ? null : (steps ?? this.steps),
    caloriesKcal: clearCalories ? null : (caloriesKcal ?? this.caloriesKcal),
    segments: segments ?? this.segments,
    lastFix: clearLastFix ? null : (lastFix ?? this.lastFix),
    lastFixWallMs: clearLastFix ? null : (lastFixWallMs ?? this.lastFixWallMs),
    gps: gps ?? this.gps,
    locked: locked ?? this.locked,
    targetReached: targetReached ?? this.targetReached,
    interval: clearInterval ? null : (interval ?? this.interval),
    recovery: clearRecovery ? null : (recovery ?? this.recovery),
    phaseResults: clearPhaseResults ? null : (phaseResults ?? this.phaseResults),
    workoutIncomplete: workoutIncomplete ?? this.workoutIncomplete,
    revision: revision + 1,
  );
}

/// Tiêu đề mặc định theo loại + buổi trong ngày, vd. "Morning run".
String defaultActivityTitle(ActivityType type, DateTime local) {
  final h = local.hour;
  final part = h >= 5 && h < 12
      ? 'morning'
      : h >= 12 && h < 17
      ? 'afternoon'
      : h >= 17 && h < 21
      ? 'evening'
      : 'night';
  final noun = switch (type) {
    ActivityType.run => 'run',
    ActivityType.walk => 'walk',
    ActivityType.indoorRun => 'indoor',
  };
  return 'run_title_${part}_$noun'.tr;
}

String activityTypeLabel(ActivityType type) => switch (type) {
  ActivityType.run => 'run_type_run'.tr,
  ActivityType.walk => 'run_type_walk'.tr,
  ActivityType.indoorRun => 'run_type_indoor'.tr,
};
