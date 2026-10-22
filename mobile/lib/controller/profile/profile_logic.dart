import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../configs/env.dart';
import '../../utils/l10n.dart';
import '../../services/application/firebase_providers.dart';
import '../../utils/formatters.dart';
import '../../services/native/permission_coordinator.dart';
import '../providers.dart';
import '../../repository/activity_repository.dart';
import '../../repository/settings_repository.dart';
import '../../utils/calc/step_aggregate.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/steps.dart';

/// Phiên bản app — khớp `version: 1.0.0+1` trong pubspec (không thêm package đọc version).
const String profileAppVersion = '1.0.0';
const String profileAppBuild = '1';
String get profileVersionLabel => 'profile_version_label'.trArgs([profileAppVersion, profileAppBuild]);

// ---------------------------------------------------------------------------
// Khóa kv dùng chung với các feature khác.
// ---------------------------------------------------------------------------

/// Thứ tự ưu tiên nguồn bước: danh sách tên StepSource, phân tách bằng dấu phẩy.
const String kvStepSourcePriority = 'stepSourcePriority';

/// Quyền riêng tư mặc định cho hoạt động mới (tên enum Privacy). Mặc định onlyMe (J04).
const String kvDefaultPrivacy = 'defaultPrivacy';

/// Ngày tạo tài khoản (UTC ms) lấy từ GET /me, cache để hiển thị offline.
const String kvAccountCreatedAt = 'accountCreatedAt';

// ---------------------------------------------------------------------------
// Đơn vị: chỉ đổi hiển thị, dữ liệu gốc luôn cm/kg (J03).
// ---------------------------------------------------------------------------

const double cmPerInch = 2.54;

double kgToLb(double kg) => kg / kgPerLb;
double lbToKg(double lb) => lb * kgPerLb;

/// cm → (feet, inches) làm tròn tới inch gần nhất.
(int, int) cmToFtIn(double cm) {
  final totalIn = (cm / cmPerInch).round();
  return (totalIn ~/ 12, totalIn % 12);
}

double ftInToCm(int ft, num inches) => (ft * 12 + inches) * cmPerInch;

String _trimNum(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

/// Text hiển thị cho ô cân nặng theo đơn vị (không kèm đơn vị).
String weightFieldText(double? kg, WeightUnit unit) => kg == null ? '' : _trimNum(unit == WeightUnit.kg ? kg : kgToLb(kg));

/// Text hiển thị chiều cao: cm → "172"; ft-in → ("5", "8").
(String, String) heightFieldText(double? cm, HeightUnit unit) {
  if (cm == null) return ('', '');
  if (unit == HeightUnit.cm) return (cm.round().toString(), '');
  final (ft, inch) = cmToFtIn(cm);
  return ('$ft', '$inch');
}

const double minHeightCm = 100;
const double maxHeightCm = 250;
const double minWeightKg = 25;
const double maxWeightKg = 300;

/// Kết quả parse một số đo optional: value null + error null nghĩa là để trống.
class MeasureResult {
  const MeasureResult(this.value, this.error);
  final double? value;
  final String? error;
}

String? validateDisplayName(String v) {
  final t = v.trim();
  if (t.isEmpty) return 'profile_err_name_required'.tr;
  if (t.length > 60) return 'profile_err_name_too_long'.tr;
  return null;
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Parse chiều cao người dùng nhập; trả cm. [primary] = cm hoặc feet, [secondary] = inches.
MeasureResult parseHeightInput(HeightUnit unit, String primary, [String secondary = '']) {
  if (primary.trim().isEmpty && secondary.trim().isEmpty) return const MeasureResult(null, null);
  double cm;
  if (unit == HeightUnit.cm) {
    final v = _num(primary);
    if (v == null) return MeasureResult(null, 'profile_err_enter_number'.tr);
    cm = v;
  } else {
    final ft = primary.trim().isEmpty ? 0.0 : _num(primary);
    final inch = secondary.trim().isEmpty ? 0.0 : _num(secondary);
    if (ft == null || inch == null || ft != ft.roundToDouble()) return MeasureResult(null, 'profile_err_whole_feet'.tr);
    if (inch < 0 || inch >= 12) return MeasureResult(null, 'profile_err_inches_range'.tr);
    cm = ftInToCm(ft.toInt(), inch);
  }
  if (cm < minHeightCm || cm > maxHeightCm) {
    return MeasureResult(null, unit == HeightUnit.cm ? 'profile_err_height_cm'.tr : 'profile_err_height_ftin'.tr);
  }
  return MeasureResult(cm, null);
}

/// Parse cân nặng; trả kg.
MeasureResult parseWeightInput(WeightUnit unit, String text) {
  if (text.trim().isEmpty) return const MeasureResult(null, null);
  final v = _num(text);
  if (v == null) return MeasureResult(null, 'profile_err_enter_number'.tr);
  final kg = unit == WeightUnit.kg ? v : lbToKg(v);
  if (kg < minWeightKg || kg > maxWeightKg) {
    return MeasureResult(null, unit == WeightUnit.kg ? 'profile_err_weight_kg'.tr : 'profile_err_weight_lb'.tr);
  }
  return MeasureResult(kg, null);
}

/// Nếu người dùng không sửa ô (cùng đơn vị, cùng text), giữ nguyên giá trị gốc để tránh sai số làm tròn
/// (vd. 172 cm → 5′8″ → 172.72 cm).
double? keepStoredIfUnchanged({required double? stored, required bool unchanged, required double? parsed}) => unchanged ? stored : parsed;

String activityLevelLabel(ActivityLevel l) => switch (l) {
  ActivityLevel.newbie => 'profile_level_newbie'.tr,
  ActivityLevel.occasional => 'profile_level_occasional'.tr,
  ActivityLevel.regular => 'profile_level_regular'.tr,
  ActivityLevel.active => 'profile_level_active'.tr,
};

String activityLevelHelp(ActivityLevel l) => switch (l) {
  ActivityLevel.newbie => 'profile_level_newbie_help'.tr,
  ActivityLevel.occasional => 'profile_level_occasional_help'.tr,
  ActivityLevel.regular => 'profile_level_regular_help'.tr,
  ActivityLevel.active => 'profile_level_active_help'.tr,
};

String weekStartLabel(int d) => switch (d) {
  DateTime.sunday => 'profile_weekday_sunday'.tr,
  DateTime.saturday => 'profile_weekday_saturday'.tr,
  _ => 'profile_weekday_monday'.tr,
};

/// Áp dụng thay đổi đơn vị/ngôn ngữ — không đụng tới số đo hay hoạt động đã lưu.
UserSettings applyUnitPreferences(
  UserSettings s, {
  DistanceUnit? distanceUnit,
  WeightUnit? weightUnit,
  HeightUnit? heightUnit,
  int? weekStart,
  String? localeTag,
}) => s.copyWith(distanceUnit: distanceUnit, weightUnit: weightUnit, heightUnit: heightUnit, weekStart: weekStart, localeTag: localeTag);

// ---------------------------------------------------------------------------
// Ưu tiên nguồn bước (F19 / F02).
// ---------------------------------------------------------------------------

/// Parse chuỗi kv thành danh sách đầy đủ: bỏ tên lạ/trùng, bổ sung nguồn thiếu theo thứ tự mặc định.
List<StepSource> parseStepSourcePriority(String? raw) {
  final out = <StepSource>[];
  for (final part in (raw ?? '').split(',')) {
    final name = part.trim();
    for (final s in StepSource.values) {
      if (s.name == name && !out.contains(s)) out.add(s);
    }
  }
  for (final s in defaultSourcePriority) {
    if (!out.contains(s)) out.add(s);
  }
  for (final s in StepSource.values) {
    if (!out.contains(s)) out.add(s);
  }
  return out;
}

String encodeStepSourcePriority(List<StepSource> list) => parseStepSourcePriority(list.map((s) => s.name).join(',')).map((s) => s.name).join(',');

Future<List<StepSource>> loadStepSourcePriority(SettingsRepository repo, String ownerId) async =>
    parseStepSourcePriority(await repo.kvGet(ownerId, kvStepSourcePriority));

Future<void> saveStepSourcePriority(SettingsRepository repo, String ownerId, List<StepSource> list) =>
    repo.kvSet(ownerId, kvStepSourcePriority, encodeStepSourcePriority(list));

/// Nguồn hiển thị trong danh sách ưu tiên theo flag (nguồn tắt vẫn giữ vị trí trong chuỗi lưu).
List<StepSource> visibleStepSources(FeatureFlags flags, {required bool isIOS}) => [
  StepSource.phoneSensor,
  if (flags.devicesBle) StepSource.device,
  if (flags.stepsHealth) isIOS ? StepSource.healthKit : StepSource.healthConnect,
];

/// Đổi chỗ nguồn trong danh sách hiển thị, giữ nguyên vị trí tương đối của nguồn ẩn.
List<StepSource> reorderVisible(List<StepSource> full, List<StepSource> visibleOrder) {
  final visibleSet = visibleOrder.toSet();
  final slots = <int>[];
  for (var i = 0; i < full.length; i++) {
    if (visibleSet.contains(full[i])) slots.add(i);
  }
  final out = [...full];
  for (var i = 0; i < slots.length && i < visibleOrder.length; i++) {
    out[slots[i]] = visibleOrder[i];
  }
  return out;
}

String stepSourceLabel(StepSource s) => switch (s) {
  StepSource.phoneSensor => 'profile_source_phone'.tr,
  StepSource.healthConnect => 'profile_source_health_connect'.tr,
  StepSource.healthKit => 'profile_source_apple_health'.tr,
  StepSource.device => 'profile_source_devices'.tr,
};

// ---------------------------------------------------------------------------
// Quyền riêng tư mặc định (J04).
// ---------------------------------------------------------------------------

Privacy parseDefaultPrivacy(String? raw) => Privacy.values.firstWhere((p) => p.name == raw, orElse: () => Privacy.onlyMe);

Future<Privacy> loadDefaultPrivacy(SettingsRepository repo, String ownerId) async => parseDefaultPrivacy(await repo.kvGet(ownerId, kvDefaultPrivacy));

Future<void> saveDefaultPrivacy(SettingsRepository repo, String ownerId, Privacy p) => repo.kvSet(ownerId, kvDefaultPrivacy, p.name);

// ---------------------------------------------------------------------------
// Thống kê trọn đời cho header Profile.
// ---------------------------------------------------------------------------

class ProfileStats {
  const ProfileStats({required this.activityCount, required this.distanceM, required this.runCount, required this.activeDays});
  final int activityCount;
  final double distanceM;
  final int runCount;
  final int activeDays;
}

/// Số ngày địa phương khác nhau có hoạt động đã lưu (theo tz offset lúc ghi).
Future<int> countActiveDays(ActivityRepository repo, String ownerId) async {
  final r = await repo.raw.rawQuery(
    "SELECT COUNT(DISTINCT (started_at + tz_offset_min * 60000) / 86400000) AS d FROM activities WHERE owner_id = ? AND status = 'saved' AND deleted_at IS NULL",
    [ownerId],
  );
  return (r.first['d'] as num?)?.toInt() ?? 0;
}

final profileStatsProvider = FutureProvider.autoDispose<ProfileStats>((ref) async {
  ref.watch(activityRevisionProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final repo = ref.watch(activityRepositoryProvider);
  final all = await repo.totals(ActivityQuery(ownerId: owner));
  final runs = await repo.totals(ActivityQuery(ownerId: owner, types: const {ActivityType.run, ActivityType.indoorRun}));
  final days = await countActiveDays(repo, owner);
  return ProfileStats(activityCount: all.count, distanceM: all.distanceM, runCount: runs.count, activeDays: days);
});

/// Ngày tham gia: chỉ cho user đã đăng nhập, lấy từ cache kv hoặc users/{uid}.createdAt. Không có → null (không bịa).
final profileJoinedProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final owner = ref.watch(ownerProvider);
  if (owner.isGuest) return null;
  final repo = ref.watch(settingsRepositoryProvider);
  final cached = int.tryParse(await repo.kvGet(owner.ownerId, kvAccountCreatedAt) ?? '');
  if (cached != null) return DateTime.fromMillisecondsSinceEpoch(cached);
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid != owner.ownerId) return null;
  try {
    final snap = await ref.watch(firestoreProvider).collection('users').doc(uid).get();
    final created = (snap.data()?['createdAt'] as num?)?.toInt();
    if (created == null) return null;
    await repo.kvSet(owner.ownerId, kvAccountCreatedAt, '$created');
    return DateTime.fromMillisecondsSinceEpoch(created);
  } catch (_) {
    return null;
  }
});

/// Phiên đang mở → thay đổi run settings chỉ áp dụng từ phiên sau.
final profileOpenSessionProvider = FutureProvider.autoDispose<bool>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  return await ref.watch(activityRepositoryProvider).openSession(owner) != null;
});

// ---------------------------------------------------------------------------
// Giọng đọc thử (flutter_tts thật); override trong test.
// ---------------------------------------------------------------------------

abstract class ProfileVoice {
  /// true khi engine nhận lệnh đọc.
  Future<bool> speak(String text);
}

class FlutterTtsProfileVoice implements ProfileVoice {
  FlutterTts? _tts;
  @override
  Future<bool> speak(String text) async {
    final tts = _tts ??= FlutterTts();
    await tts.setLanguage('en-US');
    await tts.awaitSpeakCompletion(false);
    final r = await tts.speak(text);
    return r == 1 || r == true;
  }
}

final profileVoiceProvider = Provider<ProfileVoice>((ref) => FlutterTtsProfileVoice());

/// Câu đọc thử theo cài đặt hiện tại (dùng format thật, không số liệu giả từ hoạt động).
String voiceTestPhrase(AudioCueSettings cues, StrideFormat fmt) {
  final parts = <String>['profile_voice_on'.tr];
  final unit = fmt.distanceUnit == DistanceUnit.km ? 'profile_voice_unit_km'.tr : 'profile_voice_unit_mile'.tr;
  parts.add('profile_voice_interval'.trArgs([_trimNum(cueIntervalInUnit(cues.everyKm, fmt.distanceUnit)), unit]));
  if (cues.announceTime) parts.add('profile_voice_time'.tr);
  if (cues.announcePace) parts.add('profile_voice_pace'.tr);
  return parts.join(' ');
}

/// Khoảng cue theo đơn vị hiển thị (everyKm lưu theo km).
double cueIntervalInUnit(double everyKm, DistanceUnit unit) {
  if (unit == DistanceUnit.km) return everyKm;
  return ((everyKm * 1000 / metersPerMile) * 10).round() / 10;
}

double cueIntervalToKm(double value, DistanceUnit unit) => unit == DistanceUnit.km ? value : value * metersPerMile / 1000;

const cueIntervalChoices = [0.5, 1.0, 2.0, 5.0];

// ---------------------------------------------------------------------------
// Chẩn đoán (J06): không token, không tọa độ, không email.
// ---------------------------------------------------------------------------

String buildDiagnostics({
  required String env,
  required String platform,
  required FeatureFlags flags,
  required Map<PermKind, PermStatus> permissions,
  required bool isGuest,
  required int savedActivities,
  required int stepSamples,
  required int pendingSync,
  required String distanceUnit,
}) {
  final f = <String, bool>{
    'auth.email': flags.authEmail,
    'steps.health': flags.stepsHealth,
    'notifications.inbox': flags.notificationsInbox,
    'workout.intervals': flags.workoutIntervals,
    'workout.plans': flags.workoutPlans,
    'devices.ble': flags.devicesBle,
    'run.indoor': flags.runIndoor,
    'explore.clubs': flags.exploreClubs,
    'explore.challenges': flags.exploreChallenges,
    'explore.routes': flags.exploreRoutes,
    'live.sharing': flags.liveSharing,
    'sync': flags.sync,
  };
  final b = StringBuffer()
    ..writeln('STRIDE diagnostics')
    ..writeln('App version: $profileAppVersion ($profileAppBuild)')
    ..writeln('Environment: $env')
    ..writeln('Platform: $platform')
    ..writeln('Account: ${isGuest ? 'guest' : 'signed in'}')
    ..writeln('Distance unit: $distanceUnit')
    ..writeln('Saved activities: $savedActivities')
    ..writeln('Step samples: $stepSamples')
    ..writeln('Waiting to sync: $pendingSync')
    ..writeln('Permissions:');
  for (final e in permissions.entries) {
    b.writeln('  ${e.key.name}: ${e.value.name}');
  }
  b.writeln('Flags:');
  for (final e in f.entries) {
    b.writeln('  ${e.key}: ${e.value ? 'on' : 'off'}');
  }
  return b.toString().trimRight();
}
