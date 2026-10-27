import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/providers.dart';
import '../../models/data_models/activity.dart';
import '../../repository/activity_repository.dart';
import '../../repository/settings_repository.dart';
import '../../utils/calc/records.dart';
import '../../utils/calc/run_metrics.dart';
import '../../utils/l10n.dart';

/// Khóa cache effort theo hoạt động; gắn revision để sửa/đồng bộ lại thì tính lại.
String effortCacheKey(String activityId) => 'records.effort.$activityId';

/// Effort tốt nhất 1 km / 5 km của một hoạt động, chỉ trong segment liên tục (I05).
/// Cache trong kv; key chỉ có khi hoạt động thực sự phủ đủ quãng (4.9 km không có key 5000).
Future<Map<int, int>> bestEffortsFor(ActivityRepository activities, SettingsRepository settings, Activity a) async {
  final cached = await settings.kvGet(a.ownerId, effortCacheKey(a.id));
  if (cached != null) {
    try {
      final j = (jsonDecode(cached) as Map).cast<String, Object?>();
      if (j['rev'] == a.revision) {
        return {
          for (final e in j.entries)
            if (e.key != 'rev' && e.value is int) int.parse(e.key): e.value as int,
        };
      }
    } catch (_) {
      // Cache hỏng → tính lại.
    }
  }
  final out = <int, int>{};
  if ((a.distanceM ?? 0) >= 1000) {
    final pts = await activities.points(a.id, acceptedOnly: true);
    for (final target in const [1000, 5000]) {
      final ms = fastestEffortMs(pts, target.toDouble());
      if (ms != null && ms > 0) out[target] = ms;
    }
  }
  await settings.kvSet(a.ownerId, effortCacheKey(a.id), jsonEncode({'rev': a.revision, for (final e in out.entries) '${e.key}': e.value}));
  return out;
}

/// Tính record từ hoạt động còn hợp lệ (đã lưu, chưa xóa, run ngoài trời có GPS).
/// Xóa hoạt động giữ record → lần tính sau tự lấy hoạt động hợp lệ tiếp theo.
Future<List<PersonalRecord>> loadPersonalRecords(ActivityRepository activities, SettingsRepository settings, String ownerId) async {
  final all = await activities.list(ActivityQuery(ownerId: ownerId, types: const {ActivityType.run}, limit: 100000));
  final eligible = all.where(isRecordEligible).toList();
  final efforts = <String, Map<int, int>>{};
  for (final a in eligible) {
    efforts[a.id] = await bestEffortsFor(activities, settings, a);
  }
  return computeRecords(eligible, efforts);
}

final personalRecordsProvider = FutureProvider.autoDispose<List<PersonalRecord>>((ref) async {
  ref.watch(activityRevisionProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  return loadPersonalRecords(ref.watch(activityRepositoryProvider), ref.watch(settingsRepositoryProvider), owner);
});

String recordTitle(RecordKind k) => switch (k) {
  RecordKind.longestRun => 'svc_record_longest_run_title'.tr,
  RecordKind.longestDuration => 'svc_record_longest_duration_title'.tr,
  RecordKind.fastest1k => 'svc_record_fastest_1k_title'.tr,
  RecordKind.fastest5k => 'svc_record_fastest_5k_title'.tr,
};

String recordDescription(RecordKind k) => switch (k) {
  RecordKind.longestRun => 'svc_record_longest_run_desc'.tr,
  RecordKind.longestDuration => 'svc_record_longest_duration_desc'.tr,
  RecordKind.fastest1k => 'svc_record_fastest_1k_desc'.tr,
  RecordKind.fastest5k => 'svc_record_fastest_5k_desc'.tr,
};

String recordEmptyHint(RecordKind k) => switch (k) {
  RecordKind.longestRun || RecordKind.longestDuration => 'svc_record_empty_longest'.tr,
  RecordKind.fastest1k => 'svc_record_empty_1k'.tr,
  RecordKind.fastest5k => 'svc_record_empty_5k'.tr,
};
