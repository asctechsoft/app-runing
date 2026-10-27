import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/data_models/activity.dart';
import '../providers.dart';

/// Ảnh đính kèm còn hiệu lực của hoạt động.
class ActivityPhoto {
  const ActivityPhoto({required this.id, required this.localPath});
  final String id;
  final String? localPath;

  bool get fileExists => localPath != null && File(localPath!).existsSync();
}

/// Dữ liệu màn chi tiết: luôn đọc từ DB local theo ID (Home/History/Progress cùng ID → cùng số).
class ActivityDetailData {
  const ActivityDetailData({required this.activity, required this.points, required this.photos, required this.heartRate});

  final Activity activity;

  /// Chỉ điểm accepted, theo seq.
  final List<TrackPoint> points;
  final List<ActivityPhoto> photos;
  final List<(int, int)> heartRate;

  bool get hasRoute => activity.hasGps && points.length >= 2;
}

/// null = không tồn tại / đã xóa / không thuộc owner / chưa lưu.
final activityDetailProvider = FutureProvider.autoDispose.family<ActivityDetailData?, String>((ref, id) async {
  ref.watch(activityRevisionProvider);
  final owner = ref.watch(ownerProvider).ownerId;
  final repo = ref.watch(activityRepositoryProvider);
  final a = await repo.byId(owner, id);
  if (a == null || a.status != ActivityStatus.saved) return null;
  final points = await repo.points(id, acceptedOnly: true);
  final att = await repo.attachments(id);
  final hr = await repo.raw.query('heart_rate_samples', columns: ['t', 'bpm'], where: 'activity_id = ?', whereArgs: [id], orderBy: 't');
  return ActivityDetailData(
    activity: a,
    points: points,
    photos: [for (final r in att) ActivityPhoto(id: r['id'] as String, localPath: r['local_path'] as String?)],
    heartRate: [for (final r in hr) (r['t'] as int, r['bpm'] as int)],
  );
});

/// Bật tile bản đồ thật (flutter_map). Test/preview override = false để không gọi mạng.
final activityMapTilesEnabledProvider = Provider<bool>((ref) => true);
