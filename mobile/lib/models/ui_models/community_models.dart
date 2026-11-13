import 'dart:convert';
import 'dart:typed_data';

import '../data_models/activity.dart';

/// Bài chia sẻ buổi chạy lên Cộng đồng. Số liệu tóm tắt + (tùy chọn) ảnh tuyến đường đã ẩn đầu/cuối — không tọa độ thô, ghi chú hay id hoạt động.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    required this.type,
    required this.startedAt,
    required this.movingMs,
    this.distanceM,
    this.distanceEstimated = false,
    this.avgPaceSecPerKm,
    this.likeCount = 0,
    this.likedByMe = false,
    this.image,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final int createdAt;
  final ActivityType type;
  final int startedAt;
  final int movingMs;
  final double? distanceM;
  final bool distanceEstimated;
  final double? avgPaceSecPerKm;
  final int likeCount;
  final bool likedByMe;

  /// Ảnh PNG tuyến đường kèm bài (null = không đính kèm).
  final Uint8List? image;

  CommunityPost copyWith({int? likeCount, bool? likedByMe}) => CommunityPost(
    id: id,
    authorId: authorId,
    authorName: authorName,
    text: text,
    createdAt: createdAt,
    type: type,
    startedAt: startedAt,
    movingMs: movingMs,
    distanceM: distanceM,
    distanceEstimated: distanceEstimated,
    avgPaceSecPerKm: avgPaceSecPerKm,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    image: image,
  );

  /// Chuỗi base64 lưu trong document → byte; chuỗi hỏng thì coi như không có ảnh.
  static Uint8List? decodeImage(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Trường `activity` của document (khớp `firestore.rules`: `communityActivityKeys`).
  static Map<String, Object?> activityDoc(Activity a) => {
    'type': a.type.name,
    'startedAt': a.startedAt,
    'distanceM': a.distanceM,
    'distanceEstimated': a.distanceSource == DistanceSource.steps,
    'movingMs': a.movingMs,
    'avgPaceSecPerKm': a.avgPaceSecPerKm,
  };

  factory CommunityPost.fromDoc(String id, Map<String, Object?> d, {bool likedByMe = false}) {
    final act = (d['activity'] as Map?)?.cast<String, Object?>() ?? const {};
    final typeName = act['type'] as String?;
    return CommunityPost(
      id: id,
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as num?)?.toInt() ?? 0,
      type: ActivityType.values.firstWhere((t) => t.name == typeName, orElse: () => ActivityType.run),
      startedAt: (act['startedAt'] as num?)?.toInt() ?? 0,
      movingMs: (act['movingMs'] as num?)?.toInt() ?? 0,
      distanceM: (act['distanceM'] as num?)?.toDouble(),
      distanceEstimated: act['distanceEstimated'] as bool? ?? false,
      avgPaceSecPerKm: (act['avgPaceSecPerKm'] as num?)?.toDouble(),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: likedByMe,
      image: decodeImage(d['image']),
    );
  }
}

/// Một trang bảng tin. [nextCursor] là `createdAt` của bài cuối (null khi hết); dùng làm điều kiện `createdAt <` cho truy vấn sắp xếp giảm dần.
class CommunityPage {
  const CommunityPage(this.posts, this.nextCursor);
  final List<CommunityPost> posts;
  final int? nextCursor;
}
