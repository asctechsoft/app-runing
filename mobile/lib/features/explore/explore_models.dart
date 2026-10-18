// Model Explore (M01–M06) parse từ API backend /api/v1. Parse phòng thủ: thiếu trường bắt buộc → FormatException.
// Không bao giờ giữ tọa độ đầu/cuối của hoạt động trong feed (bỏ qua trường `route`).

import 'package:latlong2/latlong.dart';

Map<String, Object?> _map(Object? v, String what) {
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('Expected object for $what');
}

String _str(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('Missing $k');
}

String? _optStr(Map<String, Object?> j, String k) => j[k] is String ? j[k] as String : null;
int? _optInt(Map<String, Object?> j, String k) => (j[k] as num?)?.toInt();
double? _optDouble(Map<String, Object?> j, String k) => (j[k] as num?)?.toDouble();
bool _bool(Map<String, Object?> j, String k) => j[k] == true;

/// Trang kết quả có cursor {items, nextCursor}.
class ExplorePage<T> {
  const ExplorePage(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;

  static ExplorePage<T> parse<T>(Object? json, T Function(Map<String, Object?>) item) {
    final j = _map(json, 'page');
    final raw = j['items'];
    if (raw is! List) throw const FormatException('Missing items');
    return ExplorePage(raw.map((e) => item(_map(e, 'item'))).toList(), _optStr(j, 'nextCursor'));
  }
}

enum MembershipStatus { pending, approved, rejected, left, unknown }

class ClubMembership {
  const ClubMembership({required this.role, required this.status});
  final String role; // owner | mod | member
  final MembershipStatus status;

  bool get isMember => status == MembershipStatus.approved;
  bool get isPending => status == MembershipStatus.pending;
  bool get isOwner => isMember && role == 'owner';

  static ClubMembership? parse(Object? json) {
    if (json == null) return null;
    final j = _map(json, 'membership');
    final s = MembershipStatus.values.firstWhere((v) => v.name == j['status'], orElse: () => MembershipStatus.unknown);
    return ClubMembership(role: _optStr(j, 'role') ?? 'member', status: s);
  }
}

class Club {
  const Club({
    required this.id,
    required this.name,
    required this.description,
    required this.regionText,
    required this.memberCount,
    this.membership,
    this.isDevFixture = false,
  });

  final String id;
  final String name;
  final String description;
  final String regionText;
  final int memberCount;
  final ClubMembership? membership;
  final bool isDevFixture;

  Club withMembership(ClubMembership? m) =>
      Club(id: id, name: name, description: description, regionText: regionText, memberCount: memberCount, membership: m, isDevFixture: isDevFixture);

  factory Club.fromJson(Map<String, Object?> j) => Club(
    id: _str(j, 'id'),
    name: _str(j, 'name'),
    description: _optStr(j, 'description') ?? '',
    regionText: _optStr(j, 'regionText') ?? '',
    memberCount: _optInt(j, 'memberCount') ?? 0,
    membership: ClubMembership.parse(j['myMembership']),
    isDevFixture: _bool(j, 'isDevFixture'),
  );
}

/// Tóm tắt hoạt động trong post — chỉ số liệu, không tọa độ.
class PostActivity {
  const PostActivity({
    required this.id,
    required this.type,
    this.title,
    this.startedAt,
    this.distanceM,
    this.distanceEstimated = false,
    this.movingMs,
    this.avgPaceSecPerKm,
    this.steps,
  });
  final String id;
  final String type;
  final String? title;
  final int? startedAt;
  final double? distanceM;
  final bool distanceEstimated;
  final int? movingMs;
  final double? avgPaceSecPerKm;
  final int? steps;

  factory PostActivity.fromJson(Map<String, Object?> j) => PostActivity(
    id: _str(j, 'id'),
    type: _optStr(j, 'type') ?? 'run',
    title: _optStr(j, 'title'),
    startedAt: _optInt(j, 'startedAt'),
    distanceM: _optDouble(j, 'distanceM'),
    distanceEstimated: _bool(j, 'distanceEstimated'),
    movingMs: _optInt(j, 'movingMs'),
    avgPaceSecPerKm: _optDouble(j, 'avgPaceSecPerKm'),
    steps: _optInt(j, 'steps'),
  );
}

class ClubPost {
  const ClubPost({
    required this.id,
    required this.clubId,
    required this.authorId,
    this.authorName,
    required this.text,
    this.activity,
    this.activityHidden = false,
    required this.commentCount,
    required this.cheerCount,
    required this.cheeredByMe,
    required this.createdAt,
  });
  final String id;
  final String clubId;
  final String authorId;
  final String? authorName;
  final String text;
  final PostActivity? activity;
  final bool activityHidden;
  final int commentCount;
  final int cheerCount;
  final bool cheeredByMe;
  final int createdAt;

  factory ClubPost.fromJson(Map<String, Object?> j) => ClubPost(
    id: _str(j, 'id'),
    clubId: _str(j, 'clubId'),
    authorId: _str(j, 'authorId'),
    authorName: _optStr(j, 'authorDisplayName'),
    text: _optStr(j, 'text') ?? '',
    activity: j['activity'] == null ? null : PostActivity.fromJson(_map(j['activity'], 'activity')),
    activityHidden: _bool(j, 'activityHidden'),
    commentCount: _optInt(j, 'commentCount') ?? 0,
    cheerCount: _optInt(j, 'cheerCount') ?? 0,
    cheeredByMe: _bool(j, 'cheeredByMe'),
    createdAt: _optInt(j, 'createdAt') ?? 0,
  );
}

class PostComment {
  const PostComment({required this.id, required this.postId, required this.authorId, this.authorName, required this.text, required this.createdAt});
  final String id;
  final String postId;
  final String authorId;
  final String? authorName;
  final String text;
  final int createdAt;

  factory PostComment.fromJson(Map<String, Object?> j) => PostComment(
    id: _str(j, 'id'),
    postId: _str(j, 'postId'),
    authorId: _str(j, 'authorId'),
    authorName: _optStr(j, 'authorDisplayName'),
    text: _optStr(j, 'text') ?? '',
    createdAt: _optInt(j, 'createdAt') ?? 0,
  );
}

class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.clubId,
    required this.title,
    required this.description,
    required this.startAt,
    this.endAt,
    required this.tzId,
    required this.meetingPlace,
    this.cancelledAt,
    required this.goingCount,
    this.myRsvp,
  });
  final String id;
  final String clubId;
  final String title;
  final String description;
  final int startAt;
  final int? endAt;
  final String tzId;
  final String meetingPlace;
  final int? cancelledAt;
  final int goingCount;
  final String? myRsvp; // going | cancelled | null

  bool get isCancelled => cancelledAt != null;
  bool get going => myRsvp == 'going';
  bool isPast(int nowMs) => (endAt ?? startAt) < nowMs;

  factory ClubEvent.fromJson(Map<String, Object?> j) => ClubEvent(
    id: _str(j, 'id'),
    clubId: _str(j, 'clubId'),
    title: _str(j, 'title'),
    description: _optStr(j, 'description') ?? '',
    startAt: _optInt(j, 'startAt') ?? (throw const FormatException('Missing startAt')),
    endAt: _optInt(j, 'endAt'),
    tzId: _optStr(j, 'tzId') ?? 'UTC',
    meetingPlace: _optStr(j, 'meetingPlace') ?? '',
    cancelledAt: _optInt(j, 'cancelledAt'),
    goingCount: _optInt(j, 'goingCount') ?? 0,
    myRsvp: _optStr(j, 'myRsvp'),
  );
}

enum ChallengeTarget { distance, count, time }

class ChallengeParticipation {
  const ChallengeParticipation({required this.joinedAt, required this.progressValue, required this.targetValue, required this.percent, this.completedAt});
  final int joinedAt;
  final double progressValue;
  final double targetValue;
  final int percent;
  final int? completedAt;
  bool get completed => completedAt != null;

  factory ChallengeParticipation.fromJson(Map<String, Object?> j) => ChallengeParticipation(
    joinedAt: _optInt(j, 'joinedAt') ?? 0,
    progressValue: _optDouble(j, 'progressValue') ?? 0,
    targetValue: _optDouble(j, 'targetValue') ?? 0,
    percent: (_optInt(j, 'percent') ?? 0).clamp(0, 100),
    completedAt: _optInt(j, 'completedAt'),
  );
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.activityTypes,
    required this.startDate,
    required this.endDate,
    required this.tzId,
    required this.targetType,
    required this.targetValue,
    this.badgeKey,
    this.participation,
  });
  final String id;
  final String title;
  final String description;
  final List<String> activityTypes;
  final String startDate; // YYYY-MM-DD theo tz của challenge
  final String endDate;
  final String tzId;
  final ChallengeTarget targetType;
  final double targetValue;
  final String? badgeKey;
  final ChallengeParticipation? participation;

  bool get joined => participation != null;

  Challenge withParticipation(ChallengeParticipation? p) => Challenge(
    id: id,
    title: title,
    description: description,
    activityTypes: activityTypes,
    startDate: startDate,
    endDate: endDate,
    tzId: tzId,
    targetType: targetType,
    targetValue: targetValue,
    badgeKey: badgeKey,
    participation: p,
  );

  factory Challenge.fromJson(Map<String, Object?> j) => Challenge(
    id: _str(j, 'id'),
    title: _str(j, 'title'),
    description: _optStr(j, 'description') ?? '',
    activityTypes: (j['activityTypes'] is List) ? (j['activityTypes'] as List).whereType<String>().toList() : const [],
    startDate: _str(j, 'startDate'),
    endDate: _str(j, 'endDate'),
    tzId: _optStr(j, 'tzId') ?? 'UTC',
    targetType: ChallengeTarget.values.firstWhere((t) => t.name == j['targetType'], orElse: () => throw const FormatException('Unknown targetType')),
    targetValue: _optDouble(j, 'targetValue') ?? (throw const FormatException('Missing targetValue')),
    badgeKey: _optStr(j, 'badgeKey'),
    participation: j['participation'] == null ? null : ChallengeParticipation.fromJson(_map(j['participation'], 'participation')),
  );
}

class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.name,
    required this.region,
    this.distanceM,
    this.surface,
    required this.attribution,
    required this.saved,
  });
  final String id;
  final String name;
  final String region;
  final double? distanceM;
  final String? surface;
  final String attribution;
  final bool saved;

  RouteSummary withSaved(bool s) =>
      RouteSummary(id: id, name: name, region: region, distanceM: distanceM, surface: surface, attribution: attribution, saved: s);

  factory RouteSummary.fromJson(Map<String, Object?> j) => RouteSummary(
    id: _str(j, 'id'),
    name: _str(j, 'name'),
    region: _optStr(j, 'region') ?? '',
    distanceM: _optDouble(j, 'distanceM'),
    surface: _optStr(j, 'surface'),
    attribution: _optStr(j, 'attribution') ?? '',
    saved: _bool(j, 'saved'),
  );
}

class RouteDetail {
  const RouteDetail({required this.summary, required this.points});
  final RouteSummary summary;
  final List<LatLng> points;

  factory RouteDetail.fromJson(Map<String, Object?> j) {
    final enc = _optStr(j, 'polylineEncoding');
    final raw = _optStr(j, 'polyline');
    List<LatLng> pts = const [];
    if (raw != null && raw.isNotEmpty) {
      if (enc != null && enc != 'google-polyline-5') throw FormatException('Unsupported polyline encoding $enc');
      pts = decodePolyline5(raw);
    }
    return RouteDetail(summary: RouteSummary.fromJson(j), points: pts);
  }
}

/// Giải mã Google encoded polyline (precision 5).
List<LatLng> decodePolyline5(String encoded) {
  final out = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      if (index >= encoded.length) throw const FormatException('Truncated polyline');
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    out.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return out;
}
