// Logic thuần của Explore trên Firestore (không phụ thuộc Firestore để test được).

import 'dart:convert';

import '../../models/data_models/activity.dart';
import '../../models/ui_models/explore_models.dart';

/// Cursor phân trang: giá trị trường sắp xếp + id document, đóng gói base64url(JSON).
class PageCursor {
  const PageCursor(this.value, this.id);
  final Object? value;
  final String id;
}

String encodeCursor(Object? value, String id) => base64Url.encode(utf8.encode(jsonEncode([value, id])));

/// Giải mã cursor; null hoặc rỗng → null. Cursor hỏng → [FormatException].
PageCursor? decodeCursor(String? cursor) {
  if (cursor == null || cursor.isEmpty) return null;
  final raw = jsonDecode(utf8.decode(base64Url.decode(cursor)));
  if (raw is! List || raw.length != 2 || raw[1] is! String) throw const FormatException('Bad cursor');
  return PageCursor(raw[0], raw[1] as String);
}

/// Lọc CLB theo tên/vùng (không phân biệt hoa thường). Firestore không có full-text nên lọc phía client trong trang.
bool matchesClubFilter(Map<String, Object?> d, {String? query, String? region}) {
  final name = '${d['nameLower'] ?? d['name'] ?? ''}'.toLowerCase();
  final reg = '${d['region'] ?? ''}'.toLowerCase();
  final q = query?.trim().toLowerCase() ?? '';
  final r = region?.trim().toLowerCase() ?? '';
  if (q.isNotEmpty && !name.contains(q) && !reg.contains(q)) return false;
  if (r.isNotEmpty && !reg.contains(r)) return false;
  return true;
}

/// Lọc tuyến theo vùng, khoảng cách, bề mặt (phía client).
bool matchesRouteFilter(Map<String, Object?> d, {String? region, double? minDistanceM, double? maxDistanceM, String? surface}) {
  final reg = '${d['region'] ?? ''}'.toLowerCase();
  final r = region?.trim().toLowerCase() ?? '';
  if (r.isNotEmpty && !reg.contains(r)) return false;
  final dist = (d['distanceM'] as num?)?.toDouble();
  if (minDistanceM != null && (dist == null || dist < minDistanceM)) return false;
  if (maxDistanceM != null && (dist == null || dist > maxDistanceM)) return false;
  final s = surface?.trim() ?? '';
  if (s.isNotEmpty && d['surface'] != s) return false;
  return true;
}

/// Kết quả quyết định khi vào CLB.
class JoinDecision {
  const JoinDecision({required this.status, required this.memberCountDelta});

  /// `active` (CLB công khai) hoặc `pending` (CLB riêng, chờ duyệt).
  final String status;

  /// Chỉ thành viên `active` được tính vào memberCount.
  final int memberCountDelta;
}

/// Luật vào CLB: đã có bản ghi thì không đổi gì (idempotent); CLB private → pending.
JoinDecision? decideJoin({required String visibility, required bool alreadyMember}) {
  if (alreadyMember) return null;
  final pending = visibility == 'private';
  return JoinDecision(status: pending ? 'pending' : 'active', memberCountDelta: pending ? 0 : 1);
}

/// Luật rời CLB: trả độ đổi memberCount; owner không được rời (ném [StateError] có code).
class OwnerCannotLeave implements Exception {
  const OwnerCannotLeave();
}

int decideLeave({required String role, required String status, required int memberCount}) {
  if (role == 'owner') throw const OwnerCannotLeave();
  if (status != 'active' || memberCount <= 0) return 0;
  return -1;
}

/// Tiến độ thử thách tính từ hoạt động cục bộ đã lưu của người dùng trong [fromMs, toMs].
double computeChallengeProgress(
  Iterable<Activity> activities, {
  required ChallengeTarget metric,
  required Iterable<String> activityTypes,
  required int fromMs,
  required int toMs,
}) {
  final types = activityTypes.toSet();
  var total = 0.0;
  for (final a in activities) {
    if (a.status != ActivityStatus.saved) continue;
    if (a.startedAt < fromMs || a.startedAt > toMs) continue;
    if (types.isNotEmpty && !types.contains(a.type.name)) continue;
    total += switch (metric) {
      ChallengeTarget.distance => a.distanceM ?? 0,
      ChallengeTarget.time => a.movingMs.toDouble(),
      ChallengeTarget.count => 1,
    };
  }
  return total;
}

/// Đổi count của counter về số hợp lệ (không âm).
int nextCounter(int current, int delta) {
  final n = current + delta;
  return n < 0 ? 0 : n;
}
