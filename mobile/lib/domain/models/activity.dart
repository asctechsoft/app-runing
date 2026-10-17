import 'dart:convert';

/// Loại hoạt động. indoorRun chỉ dùng khi flag `run.indoor` bật.
enum ActivityType { run, walk, indoorRun }

/// Trạng thái phiên (C05). Tên khớp docs/domain-model.md.
enum ActivityStatus { recording, paused, awaitingSave, saved, discarded, recoveryNeeded }

enum Feeling { easy, steady, hard }

enum Privacy { onlyMe, followers, public }

enum DistanceSource { gps, steps, manual }

enum SyncState { local, pending, synced, error }

enum RunGoalType { free, distance, time }

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

T? _enumOrNull<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

class RunGoal {
  const RunGoal(this.type, [this.value]);
  const RunGoal.free() : type = RunGoalType.free, value = null;

  final RunGoalType type;

  /// distance → mét, time → mili giây.
  final double? value;

  Map<String, Object?> toJson() => {'type': type.name, 'value': value};
  factory RunGoal.fromJson(Map<String, Object?> j) =>
      RunGoal(_enumByName(RunGoalType.values, j['type'] as String?, RunGoalType.free), (j['value'] as num?)?.toDouble());

  @override
  bool operator ==(Object other) => other is RunGoal && other.type == type && other.value == value;
  @override
  int get hashCode => Object.hash(type, value);
}

/// Hoạt động đã/đang ghi. Đơn vị gốc: mét, mili giây, UTC epoch ms.
class Activity {
  const Activity({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.status,
    required this.startedAt,
    required this.tzId,
    required this.tzOffsetMin,
    this.endedAt,
    this.distanceM,
    this.movingMs = 0,
    this.elapsedMs = 0,
    this.avgPaceSecPerKm,
    this.steps,
    this.caloriesKcal,
    this.calorieModel,
    this.weightKgUsed,
    this.title = '',
    this.feeling,
    this.notes,
    this.privacy = Privacy.onlyMe,
    this.goal = const RunGoal.free(),
    this.hasGps = false,
    this.distanceSource = DistanceSource.gps,
    this.workoutExecutionId,
    this.syncState = SyncState.local,
    this.revision = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.deletedAt,
  });

  final String id;
  final String ownerId;
  final ActivityType type;
  final ActivityStatus status;
  final int startedAt;
  final int? endedAt;
  final String tzId;
  final int tzOffsetMin;
  final double? distanceM;
  final int movingMs;
  final int elapsedMs;
  final double? avgPaceSecPerKm;
  final int? steps;
  final double? caloriesKcal;
  final String? calorieModel;
  final double? weightKgUsed;
  final String title;
  final Feeling? feeling;
  final String? notes;
  final Privacy privacy;
  final RunGoal goal;
  final bool hasGps;
  final DistanceSource distanceSource;
  final String? workoutExecutionId;
  final SyncState syncState;
  final int revision;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isFinal => status == ActivityStatus.saved;

  Activity copyWith({
    ActivityType? type,
    ActivityStatus? status,
    int? startedAt,
    int? endedAt,
    double? distanceM,
    int? movingMs,
    int? elapsedMs,
    double? avgPaceSecPerKm,
    bool clearAvgPace = false,
    int? steps,
    double? caloriesKcal,
    String? calorieModel,
    double? weightKgUsed,
    String? title,
    Feeling? feeling,
    bool clearFeeling = false,
    String? notes,
    Privacy? privacy,
    RunGoal? goal,
    bool? hasGps,
    DistanceSource? distanceSource,
    String? workoutExecutionId,
    SyncState? syncState,
    int? revision,
    int? updatedAt,
    int? deletedAt,
    String? ownerId,
  }) {
    return Activity(
      id: id,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      tzId: tzId,
      tzOffsetMin: tzOffsetMin,
      distanceM: distanceM ?? this.distanceM,
      movingMs: movingMs ?? this.movingMs,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      avgPaceSecPerKm: clearAvgPace ? null : (avgPaceSecPerKm ?? this.avgPaceSecPerKm),
      steps: steps ?? this.steps,
      caloriesKcal: caloriesKcal ?? this.caloriesKcal,
      calorieModel: calorieModel ?? this.calorieModel,
      weightKgUsed: weightKgUsed ?? this.weightKgUsed,
      title: title ?? this.title,
      feeling: clearFeeling ? null : (feeling ?? this.feeling),
      notes: notes ?? this.notes,
      privacy: privacy ?? this.privacy,
      goal: goal ?? this.goal,
      hasGps: hasGps ?? this.hasGps,
      distanceSource: distanceSource ?? this.distanceSource,
      workoutExecutionId: workoutExecutionId ?? this.workoutExecutionId,
      syncState: syncState ?? this.syncState,
      revision: revision ?? this.revision,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'owner_id': ownerId,
    'type': type.name,
    'status': status.name,
    'started_at': startedAt,
    'ended_at': endedAt,
    'tz_id': tzId,
    'tz_offset_min': tzOffsetMin,
    'distance_m': distanceM,
    'moving_ms': movingMs,
    'elapsed_ms': elapsedMs,
    'avg_pace_sec_per_km': avgPaceSecPerKm,
    'steps': steps,
    'calories_kcal': caloriesKcal,
    'calorie_model': calorieModel,
    'weight_kg_used': weightKgUsed,
    'title': title,
    'feeling': feeling?.name,
    'notes': notes,
    'privacy': privacy.name,
    'goal_json': jsonEncode(goal.toJson()),
    'has_gps': hasGps ? 1 : 0,
    'distance_source': distanceSource.name,
    'workout_execution_id': workoutExecutionId,
    'sync_state': syncState.name,
    'revision': revision,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  factory Activity.fromRow(Map<String, Object?> r) => Activity(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    type: _enumByName(ActivityType.values, r['type'] as String?, ActivityType.run),
    status: _enumByName(ActivityStatus.values, r['status'] as String?, ActivityStatus.saved),
    startedAt: r['started_at'] as int,
    endedAt: r['ended_at'] as int?,
    tzId: r['tz_id'] as String? ?? 'UTC',
    tzOffsetMin: r['tz_offset_min'] as int? ?? 0,
    distanceM: (r['distance_m'] as num?)?.toDouble(),
    movingMs: r['moving_ms'] as int? ?? 0,
    elapsedMs: r['elapsed_ms'] as int? ?? 0,
    avgPaceSecPerKm: (r['avg_pace_sec_per_km'] as num?)?.toDouble(),
    steps: r['steps'] as int?,
    caloriesKcal: (r['calories_kcal'] as num?)?.toDouble(),
    calorieModel: r['calorie_model'] as String?,
    weightKgUsed: (r['weight_kg_used'] as num?)?.toDouble(),
    title: r['title'] as String? ?? '',
    feeling: _enumOrNull(Feeling.values, r['feeling'] as String?),
    notes: r['notes'] as String?,
    privacy: _enumByName(Privacy.values, r['privacy'] as String?, Privacy.onlyMe),
    goal: r['goal_json'] == null ? const RunGoal.free() : RunGoal.fromJson(jsonDecode(r['goal_json'] as String) as Map<String, Object?>),
    hasGps: (r['has_gps'] as int? ?? 0) == 1,
    distanceSource: _enumByName(DistanceSource.values, r['distance_source'] as String?, DistanceSource.gps),
    workoutExecutionId: r['workout_execution_id'] as String?,
    syncState: _enumByName(SyncState.values, r['sync_state'] as String?, SyncState.local),
    revision: r['revision'] as int? ?? 0,
    createdAt: r['created_at'] as int? ?? 0,
    updatedAt: r['updated_at'] as int? ?? 0,
    deletedAt: r['deleted_at'] as int?,
  );

  /// JSON gửi lên API (camelCase).
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'status': status.name,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'tzId': tzId,
    'tzOffsetMin': tzOffsetMin,
    'distanceM': distanceM,
    'movingMs': movingMs,
    'elapsedMs': elapsedMs,
    'avgPaceSecPerKm': avgPaceSecPerKm,
    'steps': steps,
    'caloriesKcal': caloriesKcal,
    'calorieModel': calorieModel,
    'weightKgUsed': weightKgUsed,
    'title': title,
    'feeling': feeling?.name,
    'notes': notes,
    'privacy': privacy.name,
    'goal': goal.toJson(),
    'hasGps': hasGps,
    'distanceSource': distanceSource.name,
    'workoutExecutionId': workoutExecutionId,
    'revision': revision,
    'deletedAt': deletedAt,
  };

  factory Activity.fromJson(Map<String, Object?> j, {required String ownerId}) => Activity(
    id: j['id'] as String,
    ownerId: ownerId,
    type: _enumByName(ActivityType.values, j['type'] as String?, ActivityType.run),
    status: _enumByName(ActivityStatus.values, j['status'] as String?, ActivityStatus.saved),
    startedAt: (j['startedAt'] as num).toInt(),
    endedAt: (j['endedAt'] as num?)?.toInt(),
    tzId: j['tzId'] as String? ?? 'UTC',
    tzOffsetMin: (j['tzOffsetMin'] as num?)?.toInt() ?? 0,
    distanceM: (j['distanceM'] as num?)?.toDouble(),
    movingMs: (j['movingMs'] as num?)?.toInt() ?? 0,
    elapsedMs: (j['elapsedMs'] as num?)?.toInt() ?? 0,
    avgPaceSecPerKm: (j['avgPaceSecPerKm'] as num?)?.toDouble(),
    steps: (j['steps'] as num?)?.toInt(),
    caloriesKcal: (j['caloriesKcal'] as num?)?.toDouble(),
    calorieModel: j['calorieModel'] as String?,
    weightKgUsed: (j['weightKgUsed'] as num?)?.toDouble(),
    title: j['title'] as String? ?? '',
    feeling: _enumOrNull(Feeling.values, j['feeling'] as String?),
    notes: j['notes'] as String?,
    privacy: _enumByName(Privacy.values, j['privacy'] as String?, Privacy.onlyMe),
    goal: j['goal'] is Map ? RunGoal.fromJson((j['goal'] as Map).cast<String, Object?>()) : const RunGoal.free(),
    hasGps: j['hasGps'] as bool? ?? false,
    distanceSource: _enumByName(DistanceSource.values, j['distanceSource'] as String?, DistanceSource.gps),
    workoutExecutionId: j['workoutExecutionId'] as String?,
    syncState: SyncState.synced,
    revision: (j['revision'] as num?)?.toInt() ?? 0,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
    deletedAt: (j['deletedAt'] as num?)?.toInt(),
  );
}

enum SegmentReason { start, resume, gpsGap, recovery }

class TrackSegment {
  const TrackSegment({required this.id, required this.activityId, required this.seq, required this.startedAt, this.endedAt, required this.reason});

  final String id;
  final String activityId;
  final int seq;
  final int startedAt;
  final int? endedAt;
  final SegmentReason reason;

  Map<String, Object?> toRow() => {'id': id, 'activity_id': activityId, 'seq': seq, 'started_at': startedAt, 'ended_at': endedAt, 'reason': reason.name};
  factory TrackSegment.fromRow(Map<String, Object?> r) => TrackSegment(
    id: r['id'] as String,
    activityId: r['activity_id'] as String,
    seq: r['seq'] as int,
    startedAt: r['started_at'] as int,
    endedAt: r['ended_at'] as int?,
    reason: _enumByName(SegmentReason.values, r['reason'] as String?, SegmentReason.start),
  );
}

class TrackPoint {
  const TrackPoint({
    required this.activityId,
    required this.segmentId,
    required this.seq,
    required this.t,
    required this.lat,
    required this.lon,
    this.accuracyM,
    this.altitudeM,
    this.speedMps,
    this.accepted = true,
    this.rejectReason,
  });

  final String activityId;
  final String segmentId;
  final int seq;
  final int t;
  final double lat;
  final double lon;
  final double? accuracyM;
  final double? altitudeM;
  final double? speedMps;
  final bool accepted;
  final String? rejectReason;

  TrackPoint copyWith({bool? accepted, String? rejectReason, int? seq, String? segmentId}) => TrackPoint(
    activityId: activityId,
    segmentId: segmentId ?? this.segmentId,
    seq: seq ?? this.seq,
    t: t,
    lat: lat,
    lon: lon,
    accuracyM: accuracyM,
    altitudeM: altitudeM,
    speedMps: speedMps,
    accepted: accepted ?? this.accepted,
    rejectReason: rejectReason ?? this.rejectReason,
  );

  Map<String, Object?> toRow() => {
    'activity_id': activityId,
    'segment_id': segmentId,
    'seq': seq,
    't': t,
    'lat': lat,
    'lon': lon,
    'accuracy_m': accuracyM,
    'altitude_m': altitudeM,
    'speed_mps': speedMps,
    'accepted': accepted ? 1 : 0,
    'reject_reason': rejectReason,
  };
  factory TrackPoint.fromRow(Map<String, Object?> r) => TrackPoint(
    activityId: r['activity_id'] as String,
    segmentId: r['segment_id'] as String,
    seq: r['seq'] as int,
    t: r['t'] as int,
    lat: (r['lat'] as num).toDouble(),
    lon: (r['lon'] as num).toDouble(),
    accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
    altitudeM: (r['altitude_m'] as num?)?.toDouble(),
    speedMps: (r['speed_mps'] as num?)?.toDouble(),
    accepted: (r['accepted'] as int? ?? 1) == 1,
    rejectReason: r['reject_reason'] as String?,
  );

  Map<String, Object?> toJson() => {
    'segmentId': segmentId,
    'seq': seq,
    't': t,
    'lat': lat,
    'lon': lon,
    'accuracyM': accuracyM,
    'altitudeM': altitudeM,
    'speedMps': speedMps,
    'accepted': accepted,
  };
}

enum SessionEventType { start, pause, resume, autoPause, autoResume, gpsLost, gpsRecovered, lock, unlock, finish, recovered, phaseStart, discard }

class SessionEvent {
  const SessionEvent({required this.id, required this.activityId, required this.seq, required this.type, required this.t, required this.monoMs, this.data});

  final String id;
  final String activityId;
  final int seq;
  final SessionEventType type;

  /// UTC epoch ms (đồng hồ tường, để hiển thị).
  final int t;

  /// Mili giây đơn điệu kể từ lúc start (để tính khoảng; không bị đổi giờ hệ thống làm sai).
  final int monoMs;
  final Map<String, Object?>? data;

  Map<String, Object?> toRow() => {
    'id': id,
    'activity_id': activityId,
    'seq': seq,
    'type': type.name,
    't': t,
    'mono_ms': monoMs,
    'data_json': data == null ? null : jsonEncode(data),
  };
  factory SessionEvent.fromRow(Map<String, Object?> r) => SessionEvent(
    id: r['id'] as String,
    activityId: r['activity_id'] as String,
    seq: r['seq'] as int,
    type: _enumByName(SessionEventType.values, r['type'] as String?, SessionEventType.start),
    t: r['t'] as int,
    monoMs: r['mono_ms'] as int,
    data: r['data_json'] == null ? null : (jsonDecode(r['data_json'] as String) as Map).cast<String, Object?>(),
  );
}

class Split {
  const Split({required this.index, required this.distanceM, required this.movingMs});

  final int index;

  /// 1000 cho split đầy đủ, lẻ ở split cuối.
  final double distanceM;
  final int movingMs;

  double? get paceSecPerKm => distanceM < 10 ? null : (movingMs / 1000) / (distanceM / 1000);
}
