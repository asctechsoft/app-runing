import '../../models/data_models/activity.dart';

enum RecordKind { longestRun, longestDuration, fastest1k, fastest5k }

class PersonalRecord {
  const PersonalRecord({required this.kind, required this.activityId, required this.value, required this.achievedAt});

  final RecordKind kind;
  final String activityId;

  /// longestRun → mét; longestDuration / fastest* → mili giây.
  final double value;
  final int achievedAt;
}

/// Hoạt động đủ điều kiện tính record: đã lưu, chưa xóa, là run ngoài trời có GPS.
bool isRecordEligible(Activity a) =>
    a.status == ActivityStatus.saved && a.deletedAt == null && a.type == ActivityType.run && a.hasGps && a.distanceSource == DistanceSource.gps;

/// Tính record từ danh sách activity + effort tốt nhất đã tính sẵn mỗi activity (I05).
/// [bestEfforts]: activityId → {1000: ms, 5000: ms} — chỉ có key khi activity thực sự phủ đủ quãng.
List<PersonalRecord> computeRecords(List<Activity> activities, Map<String, Map<int, int>> bestEfforts) {
  PersonalRecord? longest;
  PersonalRecord? duration;
  PersonalRecord? f1;
  PersonalRecord? f5;
  for (final a in activities.where(isRecordEligible)) {
    final d = a.distanceM;
    if (d != null && (longest == null || d > longest.value)) {
      longest = PersonalRecord(kind: RecordKind.longestRun, activityId: a.id, value: d, achievedAt: a.startedAt);
    }
    if (a.movingMs > 0 && (duration == null || a.movingMs > duration.value)) {
      duration = PersonalRecord(kind: RecordKind.longestDuration, activityId: a.id, value: a.movingMs.toDouble(), achievedAt: a.startedAt);
    }
    final e = bestEfforts[a.id];
    final e1 = e?[1000];
    if (e1 != null && d != null && d >= 1000 && (f1 == null || e1 < f1.value)) {
      f1 = PersonalRecord(kind: RecordKind.fastest1k, activityId: a.id, value: e1.toDouble(), achievedAt: a.startedAt);
    }
    final e5 = e?[5000];
    if (e5 != null && d != null && d >= 5000 && (f5 == null || e5 < f5.value)) {
      f5 = PersonalRecord(kind: RecordKind.fastest5k, activityId: a.id, value: e5.toDouble(), achievedAt: a.startedAt);
    }
  }
  return [?longest, ?duration, ?f1, ?f5];
}
