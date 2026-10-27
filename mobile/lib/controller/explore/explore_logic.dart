// Logic thuần của Explore trên Firestore (không phụ thuộc Firestore để test được).

import 'dart:convert';

import '../../models/data_models/activity.dart';
import '../../models/ui_models/explore_models.dart';
import '../../utils/calc/group_eligibility.dart';

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

/// Tiến độ thử thách tính từ hoạt động cục bộ trong [fromMs, toMs]. Chỉ hoạt động được đóng góp cho nhóm (TM24, ADR 0003):
/// run/walk có GPS thật, không vị trí giả, đủ ngưỡng tối thiểu, không riêng tư.
double computeChallengeProgress(
  Iterable<Activity> activities, {
  required ChallengeTarget metric,
  required Iterable<String> activityTypes,
  required int fromMs,
  required int toMs,
}) {
  final types = activityTypes.toSet();
  var total = 0.0;
  // TM62: hoạt động chồng thời gian chỉ tính một lần.
  for (final a in dropOverlapping(activities.where(isGroupEligible))) {
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

// ---- Tạo câu lạc bộ (TM01). Giới hạn khớp `firestore.rules` (clubs create, clubQuota).
const clubNameMin = 3;
const clubNameMax = 40;
const clubDescriptionMax = 300;
const clubRegionMax = 60;

/// Nội quy club (TM04): văn bản tự do, tùy chọn.
const clubRulesMax = 1000;

/// Mỗi người sở hữu tối đa [maxOwnedClubs] club, tạo cách nhau ít nhất [clubCreateCooldown] (chống spam, ADR 0003).
const maxOwnedClubs = 5;
const clubCreateCooldown = Duration(hours: 1);

enum ClubDraftError { nameTooShort, nameTooLong, descriptionTooLong, regionTooLong, rulesTooLong }

/// Lỗi theo trường của form tạo club; rỗng = hợp lệ. Độ dài tính trên chuỗi đã cắt khoảng trắng hai đầu.
Set<ClubDraftError> validateClubDraft({required String name, required String description, required String region, String rulesText = ''}) {
  final n = name.trim().length;
  return {
    if (n < clubNameMin) ClubDraftError.nameTooShort,
    if (n > clubNameMax) ClubDraftError.nameTooLong,
    if (description.trim().length > clubDescriptionMax) ClubDraftError.descriptionTooLong,
    if (region.trim().length > clubRegionMax) ClubDraftError.regionTooLong,
    if (rulesText.trim().length > clubRulesMax) ClubDraftError.rulesTooLong,
  };
}

/// TM04: các trường owner/admin được sửa (khớp nhánh update trong `firestore.rules`). Không đụng owner/bộ đếm.
Map<String, Object?> clubEditPatch({
  required String name,
  required String description,
  required String region,
  required bool isPrivate,
  required String rulesText,
}) => {
  'name': name.trim(),
  'nameLower': name.trim().toLowerCase(),
  'description': description.trim(),
  'region': region.trim(),
  'visibility': isPrivate ? 'private' : 'public',
  'rulesText': rulesText.trim(),
};

/// Document `clubs/{id}` khi tạo mới (người tạo là thành viên đầu tiên → memberCount = 1).
Map<String, Object?> newClubDoc({
  required String ownerId,
  required String name,
  required String description,
  required String region,
  required bool isPrivate,
  required int nowMs,
}) => {
  'name': name.trim(),
  'nameLower': name.trim().toLowerCase(),
  'description': description.trim(),
  'region': region.trim(),
  'visibility': isPrivate ? 'private' : 'public',
  'memberCount': 1,
  'ownerId': ownerId,
  'createdAt': nowMs,
};

/// Từ chối tạo club trước khi gửi (rules cũng chặn): đã đủ số club hoặc chưa hết thời gian chờ.
enum ClubQuotaBlock { limitReached, tooSoon }

ClubQuotaBlock? checkClubQuota({required int ownedCount, required int? lastCreatedAtMs, required int nowMs}) {
  if (ownedCount >= maxOwnedClubs) return ClubQuotaBlock.limitReached;
  if (lastCreatedAtMs != null && nowMs - lastCreatedAtMs < clubCreateCooldown.inMilliseconds) return ClubQuotaBlock.tooSoon;
  return null;
}

// ---- Quản lý thành viên (TM02). Khớp `firestore.rules` (clubs/{id}/members, bans).
enum MemberAction { approve, reject, makeAdmin, makeMember, remove, ban, transferOwnership }

/// Hành động người có vai trò [myRole] (thành viên active) được làm với [target]. Không có hành động lên chính mình
/// (rời club đi qua nút Rời; owner phải chuyển quyền trước).
Set<MemberAction> availableMemberActions({required String myRole, required String myUid, required ClubMember target}) {
  if (target.userId == myUid || target.role == 'owner') return const {};
  final owner = myRole == 'owner';
  final admin = myRole == 'admin';
  if (!owner && !admin) return const {};
  if (target.isPending) return const {MemberAction.approve, MemberAction.reject, MemberAction.ban};
  if (admin && target.role != 'member') return const {};
  return {
    if (owner && target.role == 'member') MemberAction.makeAdmin,
    if (owner && target.role == 'admin') MemberAction.makeMember,
    if (owner) MemberAction.transferOwnership,
    MemberAction.remove,
    MemberAction.ban,
  };
}

// ---- Bảng xếp hạng (TM30)
const leaderboardSize = 50;

/// Thứ tự bảng: điểm cao trước; bằng điểm → ai đạt trước (updatedAt nhỏ hơn) xếp trên; cuối cùng theo userId cho ổn định.
int compareLeaderboard(LeaderboardEntry a, LeaderboardEntry b) {
  final v = b.value.compareTo(a.value);
  if (v != 0) return v;
  final t = a.updatedAt.compareTo(b.updatedAt);
  if (t != 0) return t;
  return a.userId.compareTo(b.userId);
}

/// Sắp xếp + gán hạng 1..n theo [compareLeaderboard] rồi mới bỏ người bị chặn ([hidden]) — hạng của người khác
/// không đổi khi mình chặn ai đó (hạng là thứ hạng thật trên bảng chung).
List<LeaderboardEntry> rankLeaderboard(Iterable<LeaderboardEntry> entries, {Set<String> hidden = const {}}) {
  final sorted = [...entries]..sort(compareLeaderboard);
  return [
    for (var i = 0; i < sorted.length; i++)
      if (!hidden.contains(sorted[i].userId)) sorted[i].withRank(i + 1),
  ];
}

// ---- Mã mời club (TM03). Khớp `firestore.rules` (clubInvites). Link mở thẳng app cần domain App Links (X25) — chưa có.
/// Bảng chữ không có ký tự dễ nhầm (0/O, 1/I/L).
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const inviteCodeLength = 8;
const inviteDefaultTtl = Duration(days: 7);
const inviteMaxTtl = Duration(days: 30);
const inviteDefaultMaxUses = 50;
const inviteMaxUsesLimit = 100;

/// Sinh mã mời từ nguồn ngẫu nhiên [nextInt] (Random.secure trong app, cố định trong test).
String generateInviteCode(int Function(int max) nextInt) =>
    String.fromCharCodes([for (var i = 0; i < inviteCodeLength; i++) inviteAlphabet.codeUnitAt(nextInt(inviteAlphabet.length))]);

/// Chuẩn hóa mã người dùng gõ: bỏ khoảng trắng/gạch, viết hoa. Sai định dạng → null.
String? normalizeInviteCode(String input) {
  final c = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (c.length != inviteCodeLength) return null;
  for (final ch in c.split('')) {
    if (!inviteAlphabet.contains(ch)) return null;
  }
  return c;
}

enum InviteProblem { expired, usedUp }

InviteProblem? checkInvite({required int expiresAt, required int uses, required int maxUses, required int nowMs}) {
  if (expiresAt <= nowMs) return InviteProblem.expired;
  if (uses >= maxUses) return InviteProblem.usedUp;
  return null;
}

// ---- Đăng buổi chạy vào club (TM06). Chỉ số liệu tóm tắt: KHÔNG tọa độ, KHÔNG bản đồ (không lộ điểm đầu/cuối),
// không ghi chú/cảm nhận riêng tư. Khớp danh sách khóa `activity` trong `firestore.rules` (posts create).
const postActivityKeys = ['id', 'type', 'title', 'startedAt', 'distanceM', 'distanceEstimated', 'movingMs', 'avgPaceSecPerKm', 'steps'];

/// Tóm tắt [a] để nhúng vào bài đăng. Quãng đường suy từ bước → `distanceEstimated` (feed hiện pace là —).
Map<String, Object?> postActivityDoc(Activity a, {required String title}) => {
  'id': a.id,
  'type': a.type.name,
  'title': title,
  'startedAt': a.startedAt,
  'distanceM': ?a.distanceM,
  'distanceEstimated': a.distanceSource != DistanceSource.gps,
  'movingMs': a.movingMs,
  'avgPaceSecPerKm': ?a.avgPaceSecPerKm,
  'steps': ?a.steps,
};

// ---- Tạo thử thách trong club (TM31). Giới hạn khớp `validChallenge` trong `firestore.rules`.
const challengeTitleMin = 3;
const challengeTitleMax = 60;
const challengeDescriptionMax = 300;

/// Kỳ dài nhất (tính cả ngày đầu và cuối).
const challengeMaxDays = 92;

/// Theo ADR 0003 chỉ run/walk có GPS thật được tính cho nhóm (indoor không tính).
const clubChallengeActivityTypes = ['run', 'walk'];

/// Mục tiêu tối đa theo đơn vị gốc: 10.000 km, 1.000 buổi, 1.000 giờ.
double challengeTargetMax(ChallengeTarget t) => switch (t) {
  ChallengeTarget.distance => 10000 * 1000,
  ChallengeTarget.count => 1000,
  ChallengeTarget.time => 1000 * 3600 * 1000,
};

enum ChallengeDraftError { titleTooShort, titleTooLong, descriptionTooLong, targetInvalid, startInPast, endBeforeStart, tooLong }

/// [start]/[end] là ngày địa phương (giờ bị bỏ qua); [today] = hôm nay theo máy.
Set<ChallengeDraftError> validateChallengeDraft({
  required String title,
  required String description,
  required ChallengeTarget metric,
  required double? target,
  required DateTime start,
  required DateTime end,
  required DateTime today,
}) {
  final t = title.trim().length;
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  final days = DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
  return {
    if (t < challengeTitleMin) ChallengeDraftError.titleTooShort,
    if (t > challengeTitleMax) ChallengeDraftError.titleTooLong,
    if (description.trim().length > challengeDescriptionMax) ChallengeDraftError.descriptionTooLong,
    if (target == null || target <= 0 || target > challengeTargetMax(metric)) ChallengeDraftError.targetInvalid,
    if (s.isBefore(DateTime(today.year, today.month, today.day))) ChallengeDraftError.startInPast,
    if (e.isBefore(s)) ChallengeDraftError.endBeforeStart,
    if (days > challengeMaxDays) ChallengeDraftError.tooLong,
  };
}

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Document `challenges/{id}` của club: kỳ từ 00:00 ngày [start] tới hết ngày [end] theo giờ máy người tạo ([tzId]).
/// [target] theo đơn vị gốc (m / buổi / ms).
Map<String, Object?> newClubChallengeDoc({
  required String clubId,
  required String createdBy,
  required String title,
  required String description,
  required ChallengeTarget metric,
  required double target,
  required DateTime start,
  required DateTime end,
  required String tzId,
  required int nowMs,
}) => {
  'clubId': clubId,
  'createdBy': createdBy,
  'title': title.trim(),
  'description': description.trim(),
  'metric': metric.name,
  'target': metric == ChallengeTarget.distance ? target : target.roundToDouble(),
  'startsAt': DateTime(start.year, start.month, start.day).millisecondsSinceEpoch,
  'endsAt': DateTime(end.year, end.month, end.day + 1).millisecondsSinceEpoch - 1,
  'startDate': _dateKey(start),
  'endDate': _dateKey(end),
  'tzId': tzId,
  'activityTypes': clubChallengeActivityTypes,
  'participantCount': 0,
  'createdAt': nowMs,
};

/// Mẫu có sẵn (TM31). [titleKey] là key chuỗi XML, `.tr` ở nơi hiển thị.
enum ChallengeTemplate {
  distanceMonth('explore_template_100km', ChallengeTarget.distance, 100000),
  runs30('explore_template_30runs', ChallengeTarget.count, 30),
  hoursMonth('explore_template_10h', ChallengeTarget.time, 10 * 3600 * 1000);

  const ChallengeTemplate(this.titleKey, this.metric, this.target);
  final String titleKey;
  final ChallengeTarget metric;
  final double target;

  /// Kỳ mặc định: "100 km"/"10 giờ" → hết tháng hiện tại (từ [today]); "30 buổi" → 30 ngày từ [today].
  (DateTime, DateTime) period(DateTime today) {
    final s = DateTime(today.year, today.month, today.day);
    return switch (this) {
      ChallengeTemplate.runs30 => (s, DateTime(s.year, s.month, s.day + 29)),
      _ => (s, DateTime(s.year, s.month + 1, 0)),
    };
  }
}

// ---- Vòng đời thử thách (TM33). Kỳ là mốc tuyệt đối (UTC ms) nên người ở múi giờ khác vẫn cùng một cửa sổ; hoạt động
// tính theo `startedAt` (lúc chạy), không theo lúc đồng bộ.

/// Sau `endsAt` còn [challengeGrace] để hoạt động ghi offline kịp đồng bộ và được cộng; hết hạn thì kết quả khóa.
/// Khớp `challengeGraceMs` trong `firestore.rules`.
const challengeGrace = Duration(hours: 48);

enum ChallengePhase { upcoming, active, grace, finished, cancelled }

ChallengePhase challengePhase({required int startsAt, required int endsAt, required bool cancelled, required int nowMs}) {
  if (cancelled) return ChallengePhase.cancelled;
  if (nowMs < startsAt) return ChallengePhase.upcoming;
  if (nowMs <= endsAt) return ChallengePhase.active;
  if (nowMs <= endsAt + challengeGrace.inMilliseconds) return ChallengePhase.grace;
  return ChallengePhase.finished;
}

/// Chỉ cập nhật tiến độ khi đang diễn ra hoặc trong thời gian chờ; trước khi bắt đầu chưa có gì để tính, sau khi khóa
/// thì sửa/xóa hoạt động không đổi kết quả.
bool canUpdateChallengeProgress(ChallengePhase p) => p == ChallengePhase.active || p == ChallengePhase.grace;

/// Tham gia được trước khi kết thúc; rời được khi chưa khóa (sau khi khóa, kết quả giữ nguyên).
bool canJoinChallenge(ChallengePhase p) => p == ChallengePhase.upcoming || p == ChallengePhase.active;
bool canLeaveChallenge(ChallengePhase p) => p != ChallengePhase.finished;

// ---- Sự kiện chạy chung (TM05). Giới hạn khớp `validEvent` trong `firestore.rules`.
const eventTitleMin = 3;
const eventTitleMax = 80;
const eventDescriptionMax = 1000;
const eventLocationMax = 120;
const eventMaxGoingMin = 2;
const eventMaxGoingMax = 1000;

enum EventDraftError { titleTooShort, titleTooLong, descriptionTooLong, locationTooLong, startInPast, endBeforeStart, capacityInvalid }

Set<EventDraftError> validateEventDraft({
  required String title,
  required String description,
  required String location,
  required DateTime startsAt,
  DateTime? endsAt,
  int? maxGoing,
  required DateTime now,
}) {
  final t = title.trim().length;
  return {
    if (t < eventTitleMin) EventDraftError.titleTooShort,
    if (t > eventTitleMax) EventDraftError.titleTooLong,
    if (description.trim().length > eventDescriptionMax) EventDraftError.descriptionTooLong,
    if (location.trim().length > eventLocationMax) EventDraftError.locationTooLong,
    if (!startsAt.isAfter(now)) EventDraftError.startInPast,
    if (endsAt != null && !endsAt.isAfter(startsAt)) EventDraftError.endBeforeStart,
    if (maxGoing != null && (maxGoing < eventMaxGoingMin || maxGoing > eventMaxGoingMax)) EventDraftError.capacityInvalid,
  };
}

/// Các trường sửa được của sự kiện (tạo mới thêm clubId/createdBy/goingCount/cancelledAt/createdAt).
Map<String, Object?> eventFields({
  required String title,
  required String description,
  required String location,
  required DateTime startsAt,
  DateTime? endsAt,
  int? maxGoing,
  required String tzId,
  required int nowMs,
}) => {
  'title': title.trim(),
  'description': description.trim(),
  'location': location.trim(),
  'startsAt': startsAt.millisecondsSinceEpoch,
  'endsAt': endsAt?.millisecondsSinceEpoch,
  'maxGoing': maxGoing,
  'tzId': tzId,
  'updatedAt': nowMs,
};

/// Đã đủ chỗ (không áp dụng cho người đã đăng ký).
bool eventFull({required int goingCount, int? maxGoing}) => maxGoing != null && goingCount >= maxGoing;

/// Người tạo hoặc owner/admin club được sửa (trước giờ bắt đầu) và hủy sự kiện.
bool canManageEvent({required String createdBy, required String? myUid, required String? myRole}) =>
    (myUid != null && createdBy == myUid) || myRole == 'owner' || myRole == 'admin';

/// Nhắc trước sự kiện đã đăng ký: 1 ngày và 1 giờ trước giờ bắt đầu (bỏ mốc đã qua).
const eventReminderOffsets = [Duration(days: 1), Duration(hours: 1)];

List<DateTime> eventReminderTimes(int startsAtMs, DateTime now) => [
  for (final o in eventReminderOffsets)
    if (DateTime.fromMillisecondsSinceEpoch(startsAtMs).subtract(o).isAfter(now)) DateTime.fromMillisecondsSinceEpoch(startsAtMs).subtract(o),
];

String _icsTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}${two(d.second)}Z';
}

String _icsEscape(String v) => v.replaceAll(r'\', r'\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');

/// Tệp lịch `.ics` (RFC 5545) cho một sự kiện — giờ UTC nên ứng dụng lịch tự đổi theo múi giờ máy. Không kèm tọa độ.
/// Sự kiện không có giờ kết thúc mặc định dài 1 giờ.
String eventIcs({
  required String id,
  required String title,
  required String description,
  required String location,
  required int startsAt,
  int? endsAt,
  required int nowMs,
}) {
  final end = endsAt ?? startsAt + const Duration(hours: 1).inMilliseconds;
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//STRIDE//Club events//EN',
    'BEGIN:VEVENT',
    'UID:$id@stride',
    'DTSTAMP:${_icsTime(nowMs)}',
    'DTSTART:${_icsTime(startsAt)}',
    'DTEND:${_icsTime(end)}',
    'SUMMARY:${_icsEscape(title)}',
    if (description.isNotEmpty) 'DESCRIPTION:${_icsEscape(description)}',
    if (location.isNotEmpty) 'LOCATION:${_icsEscape(location)}',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

// ---- Đội vs đội (TM32, ADR 0003 câu 3: điểm đội = trung bình mỗi người, được đổi đội).

/// Đổi đội đóng 48 giờ trước khi kết thúc (khớp `teamsOpen` trong `firestore.rules`); đổi tối đa [maxTeamChanges] lần,
/// điểm của người đổi đi theo người đó sang đội mới (tiến độ là của cá nhân).
const teamChangeLock = Duration(hours: 48);
const maxTeamChanges = 1;
const teamNameMax = 30;
const teamColorCount = 8;

enum TeamChoice { choose, change, locked }

TeamChoice teamChoice({required String? currentTeamId, required int teamChanges, required int endsAt, required int nowMs}) {
  if (nowMs >= endsAt - teamChangeLock.inMilliseconds) return TeamChoice.locked;
  if (currentTeamId == null) return TeamChoice.choose;
  return teamChanges < maxTeamChanges ? TeamChoice.change : TeamChoice.locked;
}

/// Chia ngẫu nhiên cân bằng: đội ít người nhất (bằng nhau → theo tên, rồi id) — tự chọn cho người chưa có đội.
String? pickBalancedTeam(List<ChallengeTeam> teams, Map<String, int> counts) {
  if (teams.isEmpty) return null;
  final sorted = [...teams]
    ..sort((a, b) {
      final c = (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0);
      if (c != 0) return c;
      final n = a.name.compareTo(b.name);
      return n != 0 ? n : a.id.compareTo(b.id);
    });
  return sorted.first.id;
}

class TeamStanding {
  const TeamStanding({required this.team, required this.members, required this.total, required this.average, required this.rank});
  final ChallengeTeam team;
  final int members;
  final double total;

  /// Điểm đội = tổng ÷ số người (đội đông không tự thắng).
  final double average;
  final int rank;
}

/// Xếp hạng đội: trung bình giảm dần; bằng nhau → đội đông hơn trên (nhiều người cùng đạt), rồi theo tên. Đội không có ai
/// đứng cuối với điểm 0. Bằng điểm và bằng người thì cùng hạng.
List<TeamStanding> computeTeamStandings(List<ChallengeTeam> teams, List<TeamMemberProgress> members) {
  final rows =
      [
        for (final t in teams)
          () {
            final mine = members.where((m) => m.teamId == t.id).toList();
            final total = mine.fold<double>(0, (s, m) => s + m.value);
            return (team: t, members: mine.length, total: total, average: mine.isEmpty ? 0.0 : total / mine.length);
          }(),
      ]..sort((a, b) {
        final c = b.average.compareTo(a.average);
        if (c != 0) return c;
        final m = b.members.compareTo(a.members);
        return m != 0 ? m : a.team.name.compareTo(b.team.name);
      });
  final out = <TeamStanding>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final tied = i > 0 && rows[i - 1].average == r.average && rows[i - 1].members == r.members;
    out.add(TeamStanding(team: r.team, members: r.members, total: r.total, average: r.average, rank: tied ? out[i - 1].rank : i + 1));
  }
  return out;
}

// ---- Nhắc thử thách cục bộ (TM34 phần không cần push): 1 ngày trước khi bắt đầu, 1 ngày trước khi kết thúc (nhắc đồng
// bộ hoạt động), lúc kết quả chốt (hết thời gian chờ). Bỏ mốc đã qua.
enum ChallengeReminderKind { startsSoon, endsSoon, results }

List<(DateTime, ChallengeReminderKind)> challengeReminderTimes({required int startsAt, required int endsAt, required DateTime now}) {
  const day = Duration(days: 1);
  final out = <(DateTime, ChallengeReminderKind)>[
    (DateTime.fromMillisecondsSinceEpoch(startsAt).subtract(day), ChallengeReminderKind.startsSoon),
    (DateTime.fromMillisecondsSinceEpoch(endsAt).subtract(day), ChallengeReminderKind.endsSoon),
    (DateTime.fromMillisecondsSinceEpoch(endsAt + challengeGrace.inMilliseconds), ChallengeReminderKind.results),
  ];
  return [
    for (final r in out)
      if (r.$1.isAfter(now)) r,
  ];
}
