import 'dart:convert';

enum DistanceUnit { km, mi }

enum WeightUnit { kg, lb }

enum HeightUnit { cm, ftin }

enum ActivityLevel { newbie, occasional, regular, active }

enum GoalType { dailySteps, weeklyRuns, weeklyDistanceM }

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class AudioCueSettings {
  const AudioCueSettings({this.enabled = true, this.everyKm = 1.0, this.announcePace = true, this.announceTime = true});

  final bool enabled;
  final double everyKm;
  final bool announcePace;
  final bool announceTime;

  AudioCueSettings copyWith({bool? enabled, double? everyKm, bool? announcePace, bool? announceTime}) => AudioCueSettings(
    enabled: enabled ?? this.enabled,
    everyKm: everyKm ?? this.everyKm,
    announcePace: announcePace ?? this.announcePace,
    announceTime: announceTime ?? this.announceTime,
  );

  Map<String, Object?> toJson() => {'enabled': enabled, 'everyKm': everyKm, 'announcePace': announcePace, 'announceTime': announceTime};
  factory AudioCueSettings.fromJson(Map<String, Object?> j) => AudioCueSettings(
    enabled: j['enabled'] as bool? ?? true,
    everyKm: (j['everyKm'] as num?)?.toDouble() ?? 1.0,
    announcePace: j['announcePace'] as bool? ?? true,
    announceTime: j['announceTime'] as bool? ?? true,
  );
}

/// Hồ sơ + cài đặt của một owner. Trường đo cơ thể là optional, không tự điền mẫu.
class UserSettings {
  const UserSettings({
    required this.ownerId,
    this.displayName = '',
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.distanceUnit = DistanceUnit.km,
    this.weightUnit = WeightUnit.kg,
    this.heightUnit = HeightUnit.cm,
    this.weekStart = DateTime.monday,
    this.localeTag = 'en-US',
    this.audioCues = const AudioCueSettings(),
    this.autoPause = false,
    this.avatarPath,
    this.revision = 0,
    this.updatedAt = 0,
  });

  final String ownerId;
  final String displayName;
  final double? heightCm;
  final double? weightKg;
  final ActivityLevel? activityLevel;
  final DistanceUnit distanceUnit;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final int weekStart;
  final String localeTag;
  final AudioCueSettings audioCues;
  final bool autoPause;
  final String? avatarPath;
  final int revision;
  final int updatedAt;

  UserSettings copyWith({
    String? ownerId,
    String? displayName,
    double? heightCm,
    bool clearHeight = false,
    double? weightKg,
    bool clearWeight = false,
    ActivityLevel? activityLevel,
    DistanceUnit? distanceUnit,
    WeightUnit? weightUnit,
    HeightUnit? heightUnit,
    int? weekStart,
    String? localeTag,
    AudioCueSettings? audioCues,
    bool? autoPause,
    String? avatarPath,
    int? revision,
    int? updatedAt,
  }) => UserSettings(
    ownerId: ownerId ?? this.ownerId,
    displayName: displayName ?? this.displayName,
    heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
    weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
    activityLevel: activityLevel ?? this.activityLevel,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    weightUnit: weightUnit ?? this.weightUnit,
    heightUnit: heightUnit ?? this.heightUnit,
    weekStart: weekStart ?? this.weekStart,
    localeTag: localeTag ?? this.localeTag,
    audioCues: audioCues ?? this.audioCues,
    autoPause: autoPause ?? this.autoPause,
    avatarPath: avatarPath ?? this.avatarPath,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'displayName': displayName,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'activityLevel': activityLevel?.name,
    'distanceUnit': distanceUnit.name,
    'weightUnit': weightUnit.name,
    'heightUnit': heightUnit.name,
    'weekStart': weekStart,
    'locale': localeTag,
    'audioCues': audioCues.toJson(),
    'autoPause': autoPause,
    'revision': revision,
  };

  Map<String, Object?> toRow() => {
    'owner_id': ownerId,
    'json': jsonEncode({...toJson(), 'avatarPath': avatarPath}),
    'revision': revision,
    'updated_at': updatedAt,
  };

  factory UserSettings.fromJson(String ownerId, Map<String, Object?> j, {int? updatedAt}) => UserSettings(
    ownerId: ownerId,
    displayName: j['displayName'] as String? ?? '',
    heightCm: (j['heightCm'] as num?)?.toDouble(),
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    activityLevel: j['activityLevel'] == null ? null : _byName(ActivityLevel.values, j['activityLevel'], ActivityLevel.regular),
    distanceUnit: _byName(DistanceUnit.values, j['distanceUnit'], DistanceUnit.km),
    weightUnit: _byName(WeightUnit.values, j['weightUnit'], WeightUnit.kg),
    heightUnit: _byName(HeightUnit.values, j['heightUnit'], HeightUnit.cm),
    weekStart: (j['weekStart'] as num?)?.toInt() ?? DateTime.monday,
    localeTag: j['locale'] as String? ?? 'en-US',
    audioCues: j['audioCues'] is Map ? AudioCueSettings.fromJson((j['audioCues'] as Map).cast<String, Object?>()) : const AudioCueSettings(),
    autoPause: j['autoPause'] as bool? ?? false,
    avatarPath: j['avatarPath'] as String?,
    revision: (j['revision'] as num?)?.toInt() ?? 0,
    updatedAt: updatedAt ?? 0,
  );

  factory UserSettings.fromRow(Map<String, Object?> r) =>
      UserSettings.fromJson(r['owner_id'] as String, (jsonDecode(r['json'] as String) as Map).cast<String, Object?>(), updatedAt: r['updated_at'] as int?);
}

/// Phiên bản mục tiêu: append-only, hiệu lực từ ngày địa phương [effectiveFrom] (YYYY-MM-DD).
class GoalVersion {
  const GoalVersion({required this.id, required this.ownerId, required this.type, required this.value, required this.effectiveFrom, required this.createdAt});

  final String id;
  final String ownerId;
  final GoalType type;
  final double value;
  final String effectiveFrom;
  final int createdAt;

  Map<String, Object?> toRow() => {'id': id, 'owner_id': ownerId, 'type': type.name, 'value': value, 'effective_from': effectiveFrom, 'created_at': createdAt};
  factory GoalVersion.fromRow(Map<String, Object?> r) => GoalVersion(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    type: _byName(GoalType.values, r['type'], GoalType.dailySteps),
    value: (r['value'] as num).toDouble(),
    effectiveFrom: r['effective_from'] as String,
    createdAt: r['created_at'] as int,
  );
  Map<String, Object?> toJson() => {'id': id, 'type': type.name, 'value': value, 'effectiveFrom': effectiveFrom, 'createdAt': createdAt};
}

/// Chọn mục tiêu áp dụng cho ngày [localDate] (YYYY-MM-DD): version có effectiveFrom ≤ ngày, mới nhất.
GoalVersion? goalForDate(Iterable<GoalVersion> versions, GoalType type, String localDate) {
  GoalVersion? best;
  for (final v in versions) {
    if (v.type != type || v.effectiveFrom.compareTo(localDate) > 0) continue;
    if (best == null || v.effectiveFrom.compareTo(best.effectiveFrom) > 0 || (v.effectiveFrom == best.effectiveFrom && v.createdAt > best.createdAt)) {
      best = v;
    }
  }
  return best;
}
