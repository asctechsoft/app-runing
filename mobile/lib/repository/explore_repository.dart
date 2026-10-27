import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../controller/explore/explore_logic.dart';
import '../controller/providers.dart';
import '../models/data_models/activity.dart';
import '../models/ui_models/explore_models.dart';
import '../services/application/api_client.dart';
import '../services/application/firebase_providers.dart';
import '../utils/calc/badges.dart';
import '../utils/calc/group_stats.dart';
import '../utils/clock.dart';
import '../utils/l10n.dart';

enum ExploreErrorKind { offline, notConfigured, signedOut, notFound, forbidden, conflict, rateLimited, validation, server }

/// Lỗi Explore đã chuẩn hóa để UI hiển thị nguyên nhân cụ thể.
class ExploreFailure implements Exception {
  const ExploreFailure(this.kind, {this.code = '', this.message = ''});
  final ExploreErrorKind kind;
  final String code;
  final String message;

  String get title => switch (kind) {
    ExploreErrorKind.offline => 'explore_err_offline_title'.tr,
    ExploreErrorKind.notConfigured => 'explore_err_not_configured_title'.tr,
    ExploreErrorKind.signedOut => 'explore_err_signed_out_title'.tr,
    ExploreErrorKind.notFound => 'explore_err_not_found_title'.tr,
    ExploreErrorKind.forbidden => 'explore_err_forbidden_title'.tr,
    ExploreErrorKind.conflict => 'explore_err_conflict_title'.tr,
    ExploreErrorKind.rateLimited => 'explore_err_rate_limited_title'.tr,
    ExploreErrorKind.validation => 'explore_err_validation_title'.tr,
    ExploreErrorKind.server => 'explore_err_server_title'.tr,
  };

  String get userMessage => switch (kind) {
    ExploreErrorKind.offline => 'explore_err_offline_message'.tr,
    ExploreErrorKind.notConfigured => 'explore_err_not_configured_message'.tr,
    ExploreErrorKind.signedOut => 'explore_err_signed_out_message'.tr,
    ExploreErrorKind.notFound => code == 'invite_not_found' ? 'explore_err_invite_not_found'.tr : 'explore_err_not_found_message'.tr,
    ExploreErrorKind.forbidden => code == 'club_members_only' ? 'explore_err_club_members_only'.tr : 'explore_err_forbidden_message'.tr,
    ExploreErrorKind.conflict => _conflictMessage(code, message),
    ExploreErrorKind.rateLimited => code == 'club_too_soon' ? 'explore_err_club_too_soon'.tr : 'explore_err_rate_limited_message'.tr,
    // L12: luôn dùng câu đã dịch; message gốc (tiếng Anh từ Firebase/server) chỉ để log.
    ExploreErrorKind.validation => code == 'invite_invalid' ? 'explore_err_invite_invalid'.tr : 'explore_err_validation_message'.tr,
    ExploreErrorKind.server => 'explore_err_server_message'.tr,
  };

  static String _conflictMessage(String code, String message) => switch (code) {
    'owner_cannot_leave' => 'explore_err_owner_cannot_leave'.tr,
    'club_limit' => 'explore_err_club_limit'.trArgs([maxOwnedClubs]),
    'invite_expired' => 'explore_err_invite_expired'.tr,
    'invite_used_up' => 'explore_err_invite_used_up'.tr,
    'challenge_ended' => 'explore_err_challenge_ended'.tr,
    'challenge_cancelled' => 'explore_err_challenge_cancelled'.tr,
    'challenge_locked' => 'explore_err_challenge_locked'.tr,
    'team_locked' => 'explore_err_team_locked'.tr,
    'event_cancelled' => 'explore_err_event_cancelled'.tr,
    'event_past' => 'explore_err_event_past'.tr,
    'event_full' => 'explore_err_event_full'.tr,
    _ => 'explore_err_conflict_message'.tr,
  };

  @override
  String toString() => 'ExploreFailure($kind, $code)';
}

/// Map mọi lỗi (ApiException, FirebaseException, timeout, parse) sang ExploreFailure.
ExploreFailure mapExploreError(Object e) {
  if (e is ExploreFailure) return e;
  if (e is TimeoutException) return const ExploreFailure(ExploreErrorKind.offline, code: 'network');
  if (e is FirebaseException) e = mapFirebaseError(e);
  if (e is ApiException) {
    if (e.code == 'not_configured') return ExploreFailure(ExploreErrorKind.notConfigured, code: e.code, message: e.message);
    if (e.isNetwork) return ExploreFailure(ExploreErrorKind.offline, code: e.code, message: e.message);
    final kind = switch (e.status) {
      401 => ExploreErrorKind.signedOut,
      403 => ExploreErrorKind.forbidden,
      404 => ExploreErrorKind.notFound,
      409 => ExploreErrorKind.conflict,
      400 || 422 => ExploreErrorKind.validation,
      429 => ExploreErrorKind.rateLimited,
      _ => ExploreErrorKind.server,
    };
    return ExploreFailure(kind, code: e.code, message: e.message);
  }
  // FormatException / TypeError: dữ liệu không đúng hợp đồng.
  return const ExploreFailure(ExploreErrorKind.server, code: 'bad_response');
}

// TM63: mọi query đều có giới hạn (chi phí đọc dự đoán được — xem docs/firestore-cost.md).
const maxMyClubsRead = 100;
const maxBlocksRead = 500;
const maxEventRsvpsRead = 50;
const maxChallengeJoinsRead = 100;

typedef LocalActivitiesLoader = Future<List<Activity>> Function(int fromMs, int toMs);

Map<String, Object?> _data(DocumentSnapshot<Map<String, dynamic>> d) => Map<String, Object?>.from(d.data() ?? const {});

/// Explore trên Cloud Firestore (schema: docs/firestore-schema.md). Mọi thao tác ghi tuân thủ `firestore.rules`
/// (counter chỉ ±1, soft delete bằng `deletedAt`). Lỗi luôn là [ExploreFailure].
class ExploreRepository {
  ExploreRepository({
    required this._ready,
    required this._firestore,
    required this._uid,
    this._displayName,
    this._localActivities,
    int Function()? nowMs,
    this._timeout = const Duration(seconds: 20),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final bool Function() _ready;
  final FirebaseFirestore Function() _firestore;
  final String? Function() _uid;
  final String? Function()? _displayName;
  final LocalActivitiesLoader? _localActivities;
  final int Function() _nowMs;
  final Duration _timeout;
  static const _uuid = Uuid();

  String _key() => _uuid.v4();

  /// Kiểm Firebase sẵn sàng + đã đăng nhập rồi chạy [f]; mọi lỗi → [ExploreFailure]. Mất mạng quá [_timeout] → offline.
  Future<T> _run<T>(Future<T> Function(FirebaseFirestore db, String uid) f) async {
    try {
      if (!_ready()) throw ApiException(0, 'not_configured', 'Firebase is not configured for this build');
      final uid = _uid();
      if (uid == null) throw ApiException(401, 'unauthorized', 'Sign in required');
      return await f(_firestore(), uid).timeout(_timeout);
    } catch (e) {
      throw mapExploreError(e);
    }
  }

  CollectionReference<Map<String, dynamic>> _clubs(FirebaseFirestore db) => db.collection('clubs');

  Future<Map<String, ClubMembership>> _myMemberships(FirebaseFirestore db, String uid) async {
    final snap = await db.collectionGroup('members').where('userId', isEqualTo: uid).limit(maxMyClubsRead).get();
    final out = <String, ClubMembership>{};
    for (final d in snap.docs) {
      final clubId = d.reference.parent.parent?.id;
      if (clubId != null) out[clubId] = ClubMembership.fromDoc(_data(d));
    }
    return out;
  }

  Future<Set<String>> _blockedIds(FirebaseFirestore db, String uid) async {
    final snap = await db.collection('users').doc(uid).collection('blocks').limit(maxBlocksRead).get();
    return {for (final d in snap.docs) d.id};
  }

  /// Quét theo trang: sắp xếp theo [orderField] + id, lọc phía client bằng [keep], dừng khi đủ [limit] (hoặc hết dữ liệu /
  /// quá [maxBatches] lượt). Cursor trỏ tới document quét cuối cùng.
  Future<ExplorePage<T>> _scan<T>(
    Query<Map<String, dynamic>> base, {
    required String orderField,
    required int limit,
    String? cursor,
    bool descending = false,
    bool Function(Map<String, Object?> d)? keep,
    required Future<T> Function(String id, Map<String, Object?> d) map,
    int maxBatches = 5,
  }) async {
    PageCursor? cur;
    try {
      cur = decodeCursor(cursor);
    } on FormatException {
      throw ExploreFailure(ExploreErrorKind.validation, code: 'bad_cursor', message: 'explore_err_bad_cursor'.tr);
    }
    final batch = limit < 20 ? 20 : limit;
    final kept = <(String, Map<String, Object?>)>[];
    var hasMore = false;
    PageCursor? last;
    outer:
    for (var i = 0; i < maxBatches; i++) {
      var q = base.orderBy(orderField, descending: descending).orderBy(FieldPath.documentId, descending: descending);
      if (cur != null) q = q.startAfter([cur.value, cur.id]);
      final snap = await q.limit(batch).get();
      for (var j = 0; j < snap.docs.length; j++) {
        final d = snap.docs[j];
        final data = _data(d);
        last = cur = PageCursor(data[orderField], d.id);
        if (keep == null || keep(data)) {
          kept.add((d.id, data));
          if (kept.length >= limit) {
            hasMore = j < snap.docs.length - 1 || snap.docs.length >= batch;
            break outer;
          }
        }
      }
      if (snap.docs.length < batch) break;
      if (i == maxBatches - 1) hasMore = true;
    }
    final items = await Future.wait([for (final (id, d) in kept) map(id, d)]);
    return ExplorePage(items, hasMore && last != null ? encodeCursor(last.value, last.id) : null);
  }

  // ---- Clubs (M02)
  Future<ExplorePage<Club>> searchClubs({String? query, String? region, String? cursor, int limit = 20}) => _run((db, uid) async {
    final mine = await _myMemberships(db, uid);
    return _scan<Club>(
      _clubs(db),
      orderField: 'name',
      limit: limit,
      cursor: cursor,
      keep: (d) => d['archivedAt'] == null && matchesClubFilter(d, query: query, region: region),
      map: (id, d) async => Club.fromDoc(id, d, membership: mine[id]),
    );
  });

  Future<List<Club>> myClubs() => _run((db, uid) async {
    final mine = await _myMemberships(db, uid);
    final clubs = await Future.wait([
      for (final e in mine.entries) _clubs(db).doc(e.key).get().then<Club?>((s) => s.exists ? Club.fromDoc(s.id, _data(s), membership: e.value) : null),
    ]);
    return [for (final c in clubs) ?c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  Future<Club> club(String id) => _run((db, uid) async {
    final snap = await _clubs(db).doc(id).get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Club not found');
    final m = await _clubs(db).doc(id).collection('members').doc(uid).get();
    return Club.fromDoc(snap.id, _data(snap), membership: m.exists ? ClubMembership.fromDoc(_data(m)) : null);
  });

  /// TM04: owner giải tán club = lưu trữ (giữ lịch sử, chặn hoạt động mới). Không xóa dây chuyền vì chưa có Cloud Functions
  /// (ADR 0003) — xóa hẳn dữ liệu làm sau khi có server.
  Future<void> archiveClub(String clubId) => _run((db, uid) => _clubs(db).doc(clubId).update({'archivedAt': _nowMs()}));

  /// TM04: owner/admin sửa tên, mô tả, vùng, công khai/riêng tư và nội quy (rules kiểm vai trò + độ dài).
  Future<void> updateClub(
    String clubId, {
    required String name,
    required String description,
    required String region,
    required bool isPrivate,
    required String rulesText,
  }) => _run(
    (db, uid) => _clubs(db).doc(clubId).update(clubEditPatch(name: name, description: description, region: region, isPrivate: isPrivate, rulesText: rulesText)),
  );

  // ---- Số liệu nhóm (TM21/TM22). Ghi phần của chính mình; đọc của mọi thành viên đang chia sẻ.

  /// Ghi/ghi đè số liệu theo ngày của tôi vào club (chỉ khi tôi đã bật chia sẻ — app kiểm; rules kiểm thành viên).
  Future<void> publishMemberStats(String clubId, Map<String, MemberDay> days) => _run(
    (db, uid) => _clubs(db).doc(clubId).collection('memberStats').doc(uid).set({
      'userId': uid,
      'displayName': _displayName?.call() ?? '',
      'days': {for (final e in days.entries) e.key: e.value.toMap()},
      'updatedAt': _nowMs(),
    }),
  );

  /// Tắt chia sẻ: xóa hẳn số liệu của tôi khỏi club.
  Future<void> stopSharingStats(String clubId) => _run((db, uid) => _clubs(db).doc(clubId).collection('memberStats').doc(uid).delete());

  /// Số liệu của các thành viên đang chia sẻ (tối đa 200); bỏ người tôi đã chặn.
  Future<List<MemberStats>> clubMemberStats(String clubId) => _run((db, uid) async {
    final blocked = await _blockedIds(db, uid);
    final snap = await _clubs(db).doc(clubId).collection('memberStats').limit(200).get();
    return [
      for (final d in snap.docs)
        if (!blocked.contains(d.id)) MemberStats.fromDoc(d.id, _data(d)),
    ];
  });

  /// TM22: owner/admin đặt hoặc gỡ ([goal] null) mục tiêu nhóm.
  Future<void> setGroupGoal(String clubId, GroupGoal? goal) =>
      _run((db, uid) => _clubs(db).doc(clubId).update({'groupGoal': goal == null ? FieldValue.delete() : goal.toMap()}));

  /// TM01: tạo club + thành viên owner + cập nhật hạn mức trong MỘT transaction (rules kiểm cả ba bằng getAfter).
  /// Trả id club mới. Hết hạn mức → 409 `club_limit`, tạo quá nhanh → 429 `club_too_soon`.
  Future<String> createClub({required String name, required String description, required String region, required bool isPrivate}) => _run((db, uid) {
    final clubRef = _clubs(db).doc();
    final quotaRef = db.collection('clubQuota').doc(uid);
    return db.runTransaction<String>((tx) async {
      final quota = await tx.get(quotaRef);
      final qd = _data(quota);
      final count = (qd['count'] as num?)?.toInt() ?? 0;
      final last = qd['lastCreatedAt'];
      final block = checkClubQuota(ownedCount: count, lastCreatedAtMs: last is Timestamp ? last.millisecondsSinceEpoch : null, nowMs: _nowMs());
      if (block == ClubQuotaBlock.limitReached) throw ApiException(409, 'club_limit', 'Club limit reached');
      if (block == ClubQuotaBlock.tooSoon) throw ApiException(429, 'club_too_soon', 'Creating clubs too quickly');
      final now = _nowMs();
      tx.set(quotaRef, {'count': count + 1, 'lastCreatedAt': FieldValue.serverTimestamp()});
      tx.set(clubRef, newClubDoc(ownerId: uid, name: name, description: description, region: region, isPrivate: isPrivate, nowMs: now));
      tx.set(clubRef.collection('members').doc(uid), {
        'userId': uid,
        'clubId': clubRef.id,
        'role': 'owner',
        'status': 'active',
        'displayName': _displayName?.call() ?? '',
        'joinedAt': now,
      });
      return clubRef.id;
    });
  });

  Future<ClubMembership?> requestJoin(String clubId) => _run((db, uid) {
    final clubRef = _clubs(db).doc(clubId);
    final memberRef = clubRef.collection('members').doc(uid);
    return db.runTransaction<ClubMembership?>((tx) async {
      final club = await tx.get(clubRef);
      if (!club.exists) throw ApiException(404, 'not_found', 'Club not found');
      final existing = await tx.get(memberRef);
      final cd = _data(club);
      final decision = decideJoin(visibility: '${cd['visibility']}', alreadyMember: existing.exists);
      if (decision == null) return ClubMembership.fromDoc(_data(existing));
      tx.set(memberRef, {
        'userId': uid,
        'clubId': clubId,
        'role': 'member',
        'status': decision.status,
        'displayName': _displayName?.call() ?? '',
        'joinedAt': _nowMs(),
      });
      if (decision.memberCountDelta != 0) {
        tx.update(clubRef, {'memberCount': nextCounter((cd['memberCount'] as num?)?.toInt() ?? 0, decision.memberCountDelta)});
      }
      return ClubMembership(role: 'member', status: decision.status == 'active' ? MembershipStatus.approved : MembershipStatus.pending);
    });
  });

  Future<ClubMembership?> leaveClub(String clubId) => _run((db, uid) {
    final clubRef = _clubs(db).doc(clubId);
    final memberRef = clubRef.collection('members').doc(uid);
    return db.runTransaction<ClubMembership?>((tx) async {
      final club = await tx.get(clubRef);
      final member = await tx.get(memberRef);
      if (!member.exists) return null;
      final md = _data(member);
      final int delta;
      try {
        delta = decideLeave(
          role: '${md['role']}',
          status: '${md['status']}',
          memberCount: club.exists ? ((_data(club)['memberCount'] as num?)?.toInt() ?? 0) : 0,
        );
      } on OwnerCannotLeave {
        throw ApiException(409, 'owner_cannot_leave', 'Owner cannot leave the club');
      }
      tx.delete(memberRef);
      if (delta != 0 && club.exists) {
        tx.update(clubRef, {'memberCount': nextCounter((_data(club)['memberCount'] as num?)?.toInt() ?? 0, delta)});
      }
      return null;
    });
  });

  // ---- Thành viên (TM02). Mỗi thao tác là một transaction khớp `firestore.rules`.

  /// Thành viên của club, [pending] = yêu cầu chờ duyệt. Sắp theo thời gian vào, 50 người mỗi trang.
  Future<ExplorePage<ClubMember>> clubMembers(String clubId, {bool pending = false, String? cursor}) => _run((db, uid) async {
    Query<Map<String, dynamic>> q = _clubs(db)
        .doc(clubId)
        .collection('members')
        .where('status', isEqualTo: pending ? 'pending' : 'active')
        .orderBy('joinedAt')
        .orderBy(FieldPath.documentId);
    final c = decodeCursor(cursor);
    if (c != null) q = q.startAfter([c.value, c.id]);
    final snap = await q.limit(_membersPage + 1).get();
    final docs = snap.docs.take(_membersPage).toList();
    final items = [for (final d in docs) ClubMember.fromDoc(d.id, Map<String, Object?>.from(d.data()))];
    final next = snap.docs.length > _membersPage ? encodeCursor(items.last.joinedAt, docs.last.id) : null;
    return ExplorePage(items, next);
  });

  static const _membersPage = 50;

  /// Duyệt yêu cầu vào club riêng: pending → active, memberCount +1.
  Future<void> approveMember(String clubId, String userId) => _run((db, uid) {
    final clubRef = _clubs(db).doc(clubId);
    final memberRef = clubRef.collection('members').doc(userId);
    return db.runTransaction<void>((tx) async {
      final club = await tx.get(clubRef);
      final member = await tx.get(memberRef);
      if (!member.exists || _data(member)['status'] != 'pending') return;
      tx.update(memberRef, {'status': 'active'});
      tx.update(clubRef, {'memberCount': nextCounter((_data(club)['memberCount'] as num?)?.toInt() ?? 0, 1)});
    });
  });

  /// Từ chối yêu cầu / xóa thành viên; [ban] = thêm vào danh sách cấm để không vào lại được.
  Future<void> removeMember(String clubId, String userId, {bool ban = false}) => _run((db, uid) {
    final clubRef = _clubs(db).doc(clubId);
    final memberRef = clubRef.collection('members').doc(userId);
    return db.runTransaction<void>((tx) async {
      final club = await tx.get(clubRef);
      final member = await tx.get(memberRef);
      if (member.exists) {
        tx.delete(memberRef);
        if (_data(member)['status'] == 'active') {
          tx.update(clubRef, {'memberCount': nextCounter((_data(club)['memberCount'] as num?)?.toInt() ?? 0, -1)});
        }
      }
      if (ban) tx.set(clubRef.collection('bans').doc(userId), {'bannedBy': uid, 'createdAt': _nowMs()});
    });
  });

  /// Owner đổi vai trò admin ↔ member.
  Future<void> setMemberRole(String clubId, String userId, String role) =>
      _run((db, uid) => _clubs(db).doc(clubId).collection('members').doc(userId).update({'role': role}));

  /// Chuyển quyền chủ: người nhận thành owner, mình thành admin, club trỏ sang owner mới — cùng một transaction.
  Future<void> transferOwnership(String clubId, String newOwnerId) => _run((db, uid) {
    final clubRef = _clubs(db).doc(clubId);
    final members = clubRef.collection('members');
    return db.runTransaction<void>((tx) async {
      final target = await tx.get(members.doc(newOwnerId));
      if (!target.exists || _data(target)['status'] != 'active') throw ApiException(404, 'not_found', 'Member not found');
      tx.update(members.doc(newOwnerId), {'role': 'owner'});
      tx.update(members.doc(uid), {'role': 'admin'});
      tx.update(clubRef, {'ownerId': newOwnerId});
    });
  });

  // ---- Mã mời (TM03)

  /// Tạo mã mời [inviteDefaultTtl], tối đa [inviteDefaultMaxUses] lượt. Club công khai: mọi thành viên; club riêng: owner/admin.
  Future<ClubInvite> createInvite(String clubId) => _run((db, uid) async {
    final rnd = Random.secure();
    final now = _nowMs();
    final invite = ClubInvite(code: generateInviteCode(rnd.nextInt), clubId: clubId, expiresAt: now + inviteDefaultTtl.inMilliseconds);
    await db.collection('clubInvites').doc(invite.code).set({
      'clubId': clubId,
      'createdBy': uid,
      'createdAt': now,
      'expiresAt': invite.expiresAt,
      'maxUses': inviteDefaultMaxUses,
      'uses': 0,
    });
    return invite;
  });

  /// Vào club bằng mã: thành viên `active` ngay (kể cả club riêng — người mời đã cho phép), tăng lượt dùng và memberCount
  /// trong một transaction. Trả id club. Đã là thành viên → không đổi gì.
  Future<String> joinWithCode(String rawCode) => _run((db, uid) {
    final code = normalizeInviteCode(rawCode);
    if (code == null) throw ApiException(422, 'invite_invalid', 'Invalid invite code');
    final inviteRef = db.collection('clubInvites').doc(code);
    return db.runTransaction<String>((tx) async {
      final inv = await tx.get(inviteRef);
      if (!inv.exists) throw ApiException(404, 'invite_not_found', 'Invite not found');
      final d = _data(inv);
      final clubId = '${d['clubId']}';
      final clubRef = _clubs(db).doc(clubId);
      final memberRef = clubRef.collection('members').doc(uid);
      final club = await tx.get(clubRef);
      final member = await tx.get(memberRef);
      if (member.exists && _data(member)['status'] == 'active') return clubId;
      final problem = checkInvite(
        expiresAt: (d['expiresAt'] as num?)?.toInt() ?? 0,
        uses: (d['uses'] as num?)?.toInt() ?? 0,
        maxUses: (d['maxUses'] as num?)?.toInt() ?? 0,
        nowMs: _nowMs(),
      );
      if (problem != null) throw ApiException(409, problem == InviteProblem.expired ? 'invite_expired' : 'invite_used_up', 'Invite unusable');
      if (!club.exists) throw ApiException(404, 'not_found', 'Club not found');
      if (member.exists) {
        // Đang chờ duyệt → mã mời thay cho bước duyệt.
        tx.update(memberRef, {'status': 'active', 'inviteCode': code});
      } else {
        tx.set(memberRef, {
          'userId': uid,
          'clubId': clubId,
          'role': 'member',
          'status': 'active',
          'inviteCode': code,
          'displayName': _displayName?.call() ?? '',
          'joinedAt': _nowMs(),
        });
      }
      tx.update(inviteRef, {'uses': ((d['uses'] as num?)?.toInt() ?? 0) + 1});
      tx.update(clubRef, {'memberCount': nextCounter((_data(club)['memberCount'] as num?)?.toInt() ?? 0, 1)});
      return clubId;
    });
  });

  // ---- Feed (M03)
  Future<ExplorePage<ClubPost>> posts(String clubId, {String? cursor}) => _run((db, uid) async {
    final blocked = await _blockedIds(db, uid);
    return _scan<ClubPost>(
      db.collection('posts').where('clubId', isEqualTo: clubId),
      orderField: 'createdAt',
      descending: true,
      limit: 20,
      cursor: cursor,
      keep: (d) => d['deletedAt'] == null && !blocked.contains(d['authorId']),
      map: (id, d) async {
        final cheer = await db.collection('posts').doc(id).collection('cheers').doc(uid).get();
        return ClubPost.fromDoc(id, d, cheeredByMe: cheer.exists);
      },
    );
  });

  /// Bài đăng; [activity] (TM06, từ [postActivityDoc]) cho phép để trống chữ.
  Future<ClubPost> createPost(String clubId, {required String text, Map<String, Object?>? activity}) => _run((db, uid) async {
    final t = text.trim();
    if (t.isEmpty && activity == null) throw ApiException(400, 'validation_error', 'explore_err_post_empty'.tr);
    final id = _key();
    final data = <String, Object?>{
      'clubId': clubId,
      'authorId': uid,
      'authorName': _displayName?.call() ?? '',
      'text': t,
      'createdAt': _nowMs(),
      'cheerCount': 0,
      'commentCount': 0,
      'deletedAt': null,
      'activity': ?activity,
    };
    await db.collection('posts').doc(id).set(data);
    return ClubPost.fromDoc(id, data);
  });

  /// Một bài (bài ghim không nằm trong trang đầu). null nếu đã xóa hoặc không còn.
  Future<ClubPost?> post(String postId) => _run((db, uid) async {
    final s = await db.collection('posts').doc(postId).get();
    if (!s.exists || _data(s)['deletedAt'] != null) return null;
    final cheer = await s.reference.collection('cheers').doc(uid).get();
    return ClubPost.fromDoc(s.id, _data(s), cheeredByMe: cheer.exists);
  });

  /// TM04: owner/admin ghim ([postId]) hoặc bỏ ghim (null).
  Future<void> setPinnedPost(String clubId, String? postId) => _run((db, uid) => _clubs(db).doc(clubId).update({'pinnedPostId': postId}));

  Future<ClubPost> cheer(String postId, bool on) => _run((db, uid) {
    final postRef = db.collection('posts').doc(postId);
    final cheerRef = postRef.collection('cheers').doc(uid);
    return db.runTransaction<ClubPost>((tx) async {
      final post = await tx.get(postRef);
      if (!post.exists) throw ApiException(404, 'not_found', 'Post not found');
      final cheered = await tx.get(cheerRef);
      final d = _data(post);
      var count = (d['cheerCount'] as num?)?.toInt() ?? 0;
      var now = cheered.exists;
      if (on && !cheered.exists) {
        tx.set(cheerRef, {'createdAt': _nowMs()});
        count = nextCounter(count, 1);
        tx.update(postRef, {'cheerCount': count});
        now = true;
      } else if (!on && cheered.exists) {
        tx.delete(cheerRef);
        count = nextCounter(count, -1);
        tx.update(postRef, {'cheerCount': count});
        now = false;
      }
      return ClubPost.fromDoc(postId, {...d, 'cheerCount': count}, cheeredByMe: now);
    });
  });

  /// Soft delete: chỉ tác giả được đặt `deletedAt`.
  Future<void> deletePost(String postId) => _run((db, uid) async {
    await db.collection('posts').doc(postId).update({'deletedAt': _nowMs()});
  });

  Future<ExplorePage<PostComment>> comments(String postId, {String? cursor}) => _run((db, uid) async {
    final blocked = await _blockedIds(db, uid);
    return _scan<PostComment>(
      db.collection('posts').doc(postId).collection('comments'),
      orderField: 'createdAt',
      limit: 20,
      cursor: cursor,
      keep: (d) => d['deletedAt'] == null && !blocked.contains(d['authorId']),
      map: (id, d) async => PostComment.fromDoc(id, postId, d),
    );
  });

  Future<PostComment> addComment(String postId, String text) => _run((db, uid) async {
    final t = text.trim();
    if (t.isEmpty) throw ApiException(400, 'validation_error', 'explore_err_comment_empty'.tr);
    final postRef = db.collection('posts').doc(postId);
    final id = _key();
    final data = <String, Object?>{'authorId': uid, 'authorName': _displayName?.call() ?? '', 'text': t, 'createdAt': _nowMs(), 'deletedAt': null};
    await db.runTransaction<void>((tx) async {
      final post = await tx.get(postRef);
      if (!post.exists) throw ApiException(404, 'not_found', 'Post not found');
      tx.set(postRef.collection('comments').doc(id), data);
      tx.update(postRef, {'commentCount': nextCounter((_data(post)['commentCount'] as num?)?.toInt() ?? 0, 1)});
    });
    return PostComment.fromDoc(id, postId, data);
  });

  /// Cần [postId] vì comment nằm dưới `posts/{postId}/comments`.
  Future<void> deleteComment(String commentId, {required String postId}) => _run((db, uid) {
    final postRef = db.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    return db.runTransaction<void>((tx) async {
      final c = await tx.get(commentRef);
      if (!c.exists || _data(c)['deletedAt'] != null) return;
      final post = await tx.get(postRef);
      tx.update(commentRef, {'deletedAt': _nowMs()});
      if (post.exists) tx.update(postRef, {'commentCount': nextCounter((_data(post)['commentCount'] as num?)?.toInt() ?? 0, -1)});
    });
  });

  /// targetType: post | comment | user.
  Future<void> report({required String targetType, required String targetId, required String reason}) => _run((db, uid) async {
    await db.collection('reports').doc(_key()).set({
      'reporterId': uid,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'createdAt': _nowMs(),
    });
  });

  Future<void> blockUser(String userId) => _run((db, uid) async {
    if (userId == uid) throw ApiException(400, 'validation_error', 'explore_err_block_self'.tr);
    await db.collection('users').doc(uid).collection('blocks').doc(userId).set({'createdAt': _nowMs()});
  });

  // ---- Events (M04)
  Future<ExplorePage<ClubEvent>> events(String clubId, {String? cursor}) => _run(
    (db, uid) => _scan<ClubEvent>(
      db.collection('events').where('clubId', isEqualTo: clubId),
      orderField: 'startsAt',
      limit: 20,
      cursor: cursor,
      map: (id, d) async {
        final r = await db.collection('events').doc(id).collection('rsvps').doc(uid).get();
        return ClubEvent.fromDoc(id, d, going: r.exists);
      },
    ),
  );

  /// TM05: owner/admin tạo sự kiện cho club. Trả id mới.
  Future<String> createEvent(String clubId, Map<String, Object?> fields) => _run((db, uid) async {
    final ref = db.collection('events').doc();
    await ref.set({...fields, 'clubId': clubId, 'createdBy': uid, 'goingCount': 0, 'cancelledAt': null, 'createdAt': _nowMs()});
    return ref.id;
  });

  /// TM05: sửa trước giờ bắt đầu (người tạo hoặc owner/admin; rules kiểm).
  Future<void> updateEvent(String eventId, Map<String, Object?> fields) => _run((db, uid) => db.collection('events').doc(eventId).update(fields));

  Future<void> cancelEvent(String eventId) => _run((db, uid) => db.collection('events').doc(eventId).update({'cancelledAt': _nowMs()}));

  Future<ClubEvent> event(String eventId) => _run((db, uid) async {
    final snap = await db.collection('events').doc(eventId).get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Event not found');
    final r = await snap.reference.collection('rsvps').doc(uid).get();
    return ClubEvent.fromDoc(snap.id, _data(snap), going: r.exists);
  });

  /// TM05: người đã đăng ký (tối đa 200, theo thời gian đăng ký); ẩn người tôi đã chặn.
  Future<List<EventAttendee>> eventAttendees(String eventId) => _run((db, uid) async {
    final blocked = await _blockedIds(db, uid);
    final snap = await db.collection('events').doc(eventId).collection('rsvps').orderBy('createdAt').limit(200).get();
    return [
      for (final d in snap.docs)
        if (!blocked.contains(d.id)) EventAttendee(userId: d.id, displayName: '${_data(d)['displayName'] ?? ''}'),
    ];
  });

  /// TM05: sự kiện sắp tới tôi đã đăng ký (chưa hủy) — nguồn để lên lịch nhắc cục bộ. Bỏ sự kiện không còn đọc được
  /// (đã rời club, bị xóa).
  Future<List<ClubEvent>> myUpcomingEvents() => _run((db, uid) async {
    final mine = await db.collection('users').doc(uid).collection('eventRsvps').limit(maxEventRsvpsRead).get();
    final out = <ClubEvent>[];
    for (final m in mine.docs) {
      try {
        final s = await db.collection('events').doc(m.id).get();
        if (!s.exists) continue;
        final e = ClubEvent.fromDoc(s.id, _data(s), going: true);
        if (!e.isCancelled && e.startAt > _nowMs()) out.add(e);
      } catch (_) {}
    }
    return out..sort((a, b) => a.startAt.compareTo(b.startAt));
  });

  Future<ClubEvent> rsvp(String eventId, bool going) => _run((db, uid) {
    final eventRef = db.collection('events').doc(eventId);
    final rsvpRef = eventRef.collection('rsvps').doc(uid);
    return db.runTransaction<ClubEvent>((tx) async {
      final ev = await tx.get(eventRef);
      if (!ev.exists) throw ApiException(404, 'not_found', 'Event not found');
      final r = await tx.get(rsvpRef);
      final d = _data(ev);
      var count = (d['goingCount'] as num?)?.toInt() ?? 0;
      var isGoing = r.exists;
      final mirror = db.collection('users').doc(uid).collection('eventRsvps').doc(eventId);
      if (going && !r.exists) {
        if (d['cancelledAt'] != null) throw ApiException(409, 'event_cancelled', 'Event was cancelled');
        if (((d['endsAt'] ?? d['startsAt']) as num? ?? 0) < _nowMs()) throw ApiException(409, 'event_past', 'Event already happened');
        if (eventFull(goingCount: count, maxGoing: (d['maxGoing'] as num?)?.toInt())) throw ApiException(409, 'event_full', 'Event is full');
        tx.set(rsvpRef, {'createdAt': _nowMs(), 'displayName': _displayName?.call() ?? ''});
        // TM05: bản sao phía người dùng để lên lịch nhắc (giờ lấy lại từ events/{id} khi lên lịch, nên sửa giờ vẫn đúng).
        tx.set(mirror, {'clubId': d['clubId'], 'createdAt': _nowMs()});
        count = nextCounter(count, 1);
        tx.update(eventRef, {'goingCount': count});
        isGoing = true;
      } else if (!going && r.exists) {
        tx.delete(rsvpRef);
        tx.delete(mirror);
        count = nextCounter(count, -1);
        tx.update(eventRef, {'goingCount': count});
        isGoing = false;
      }
      return ClubEvent.fromDoc(eventId, {...d, 'goingCount': count}, going: isGoing);
    });
  });

  // ---- Challenges (M05)
  /// Thử thách chung ([clubId] null — bỏ thử thách của club) hoặc của một club (TM31). Thử thách đã hủy bị ẩn.
  Future<List<Challenge>> challenges({String? clubId}) => _run((db, uid) async {
    final base = clubId == null ? db.collection('challenges') : db.collection('challenges').where('clubId', isEqualTo: clubId);
    final all = await base.orderBy('endsAt', descending: true).limit(50).get();
    final snap = all.docs.where((c) {
      final d = _data(c);
      return d['cancelledAt'] == null && (clubId != null || d['clubId'] == null);
    });
    final joins = await db.collection('users').doc(uid).collection('challengeJoins').limit(maxChallengeJoinsRead).get();
    final active = {
      for (final j in joins.docs)
        if (_data(j)['status'] != 'left') j.id,
    };
    return Future.wait([
      for (final c in snap)
        () async {
          final d = _data(c);
          ChallengeParticipation? p;
          if (active.contains(c.id)) {
            final ps = await c.reference.collection('participants').doc(uid).get();
            if (ps.exists) p = ChallengeParticipation.fromDoc(_data(ps), targetValue: (d['target'] as num?)?.toDouble() ?? 0);
          }
          return Challenge.fromDoc(c.id, d, participation: p);
        }(),
    ]);
  });

  Future<Challenge> challenge(String id) => _run((db, uid) => _loadChallenge(db, uid, id));

  // ---- Đội (TM32)
  Future<List<ChallengeTeam>> teams(String challengeId) => _run((db, uid) async {
    final snap = await db.collection('challenges').doc(challengeId).collection('teams').get();
    return [for (final d in snap.docs) ChallengeTeam.fromDoc(d.id, _data(d))]..sort((a, b) => a.name.compareTo(b.name));
  });

  /// Owner/admin club tạo đội (rules kiểm vai trò + hạn đổi đội).
  Future<void> createTeam(String challengeId, {required String name, required int color}) => _run(
    (db, uid) => db.collection('challenges').doc(challengeId).collection('teams').doc().set({
      'name': name.trim(),
      'color': color,
      'createdBy': uid,
      'createdAt': _nowMs(),
    }),
  );

  /// Tiến độ người đã vào đội (một query mỗi đội — rules chỉ cho đọc người có `teamId`).
  Future<List<TeamMemberProgress>> teamProgress(String challengeId, List<ChallengeTeam> teams) => _run((db, uid) async {
    final out = <TeamMemberProgress>[];
    for (final t in teams) {
      final snap = await db.collection('challenges').doc(challengeId).collection('participants').where('teamId', isEqualTo: t.id).limit(500).get();
      for (final d in snap.docs) {
        out.add(TeamMemberProgress(userId: d.id, teamId: t.id, value: (_data(d)['progressValue'] as num?)?.toDouble() ?? 0));
      }
    }
    return out;
  });

  /// Chọn (lần đầu) hoặc đổi đội (tối đa [maxTeamChanges] lần, trước hạn khóa).
  Future<void> setMyTeam(String challengeId, String teamId) => _run((db, uid) {
    final ref = db.collection('challenges').doc(challengeId);
    final pRef = ref.collection('participants').doc(uid);
    return db.runTransaction<void>((tx) async {
      final c = await tx.get(ref);
      final p = await tx.get(pRef);
      if (!c.exists || !p.exists) throw ApiException(404, 'not_found', 'Not joined');
      final pd = _data(p);
      final current = pd['teamId'] as String?;
      if (current == teamId) return;
      final changes = (pd['teamChanges'] as num?)?.toInt() ?? 0;
      final choice = teamChoice(currentTeamId: current, teamChanges: changes, endsAt: (_data(c)['endsAt'] as num?)?.toInt() ?? 0, nowMs: _nowMs());
      if (choice == TeamChoice.locked) throw ApiException(409, 'team_locked', 'Team changes are closed');
      tx.update(pRef, {'teamId': teamId, if (choice == TeamChoice.change) 'teamChanges': changes + 1});
    });
  });

  /// TM34: thử thách tôi đang tham gia chưa khóa kết quả (nguồn nhắc cục bộ). Bỏ thử thách đã hủy/đã rời/không đọc được.
  Future<List<Challenge>> myOpenChallenges() => _run((db, uid) async {
    final joins = await db.collection('users').doc(uid).collection('challengeJoins').limit(maxChallengeJoinsRead).get();
    final out = <Challenge>[];
    for (final j in joins.docs) {
      if (_data(j)['status'] == 'left') continue;
      try {
        final s = await db.collection('challenges').doc(j.id).get();
        if (!s.exists) continue;
        final c = Challenge.fromDoc(s.id, _data(s));
        if (challengePhase(startsAt: c.startsAt, endsAt: c.endsAt, cancelled: c.cancelled, nowMs: _nowMs()) != ChallengePhase.finished && !c.cancelled) {
          out.add(c);
        }
      } catch (_) {}
    }
    return out;
  });

  /// TM40: thử thách tôi đã hoàn thành (participant có `completedAt`) — nguồn huy hiệu thử thách.
  Future<List<CompletedChallenge>> myCompletedChallenges() => _run((db, uid) async {
    final joins = await db.collection('users').doc(uid).collection('challengeJoins').limit(maxChallengeJoinsRead).get();
    final out = <CompletedChallenge>[];
    for (final j in joins.docs) {
      if (_data(j)['status'] == 'left') continue;
      final ref = db.collection('challenges').doc(j.id);
      final p = await ref.collection('participants').doc(uid).get();
      final done = (_data(p)['completedAt'] as num?)?.toInt();
      if (!p.exists || done == null) continue;
      final c = await ref.get();
      out.add((id: j.id, title: '${_data(c)['title'] ?? ''}', completedAt: done));
    }
    return out;
  });

  /// TM31: owner/admin tạo thử thách cho club (rules kiểm vai trò + dữ liệu). Trả id mới.
  Future<String> createChallenge(
    String clubId, {
    required String title,
    required String description,
    required ChallengeTarget metric,
    required double target,
    required DateTime start,
    required DateTime end,
  }) => _run((db, uid) async {
    final ref = db.collection('challenges').doc();
    await ref.set(
      newClubChallengeDoc(
        clubId: clubId,
        createdBy: uid,
        title: title,
        description: description,
        metric: metric,
        target: target,
        start: start,
        end: end,
        tzId: currentTzId(),
        nowMs: _nowMs(),
      ),
    );
    return ref.id;
  });

  /// TM31: hủy thử thách của club trước khi bắt đầu (rules chặn sau mốc bắt đầu).
  Future<void> cancelChallenge(String id) => _run((db, uid) => db.collection('challenges').doc(id).update({'cancelledAt': _nowMs()}));

  Future<Challenge> _loadChallenge(FirebaseFirestore db, String uid, String id) async {
    final ref = db.collection('challenges').doc(id);
    final snap = await ref.get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Challenge not found');
    final d = _data(snap);
    final ps = await ref.collection('participants').doc(uid).get();
    final p = ps.exists ? ChallengeParticipation.fromDoc(_data(ps), targetValue: (d['target'] as num?)?.toDouble() ?? 0) : null;
    return Challenge.fromDoc(id, d, participation: p);
  }

  /// Tính lại tiến độ từ hoạt động cục bộ và ghi vào participant khi đổi. Trả participant mới (hoặc null nếu chưa tham gia).
  Future<ChallengeParticipation?> _refreshProgress(FirebaseFirestore db, String uid, String id) async {
    final ref = db.collection('challenges').doc(id);
    final snap = await ref.get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Challenge not found');
    final pRef = ref.collection('participants').doc(uid);
    final ps = await pRef.get();
    if (!ps.exists) return null;
    final cd = _data(snap);
    final pd = _data(ps);
    final target = (cd['target'] as num?)?.toDouble() ?? 0;
    final loader = _localActivities;
    if (loader == null) return ChallengeParticipation.fromDoc(pd, targetValue: target);
    final ch = Challenge.fromDoc(id, cd);
    // TM33: ngoài [active, grace] thì giữ nguyên kết quả đã ghi (chưa bắt đầu / đã khóa / đã hủy).
    final phase = challengePhase(startsAt: ch.startsAt, endsAt: ch.endsAt, cancelled: ch.cancelled, nowMs: _nowMs());
    if (!canUpdateChallengeProgress(phase)) return ChallengeParticipation.fromDoc(pd, targetValue: target);
    final from = (cd['startsAt'] as num).toInt();
    final to = (cd['endsAt'] as num).toInt();
    final acts = await loader(from, to + 1);
    final value = computeChallengeProgress(acts, metric: ch.targetType, activityTypes: ch.activityTypes, fromMs: from, toMs: to);
    final complete = target > 0 && value >= target;
    final hadCompleted = pd['completedAt'] != null;
    final stored = (pd['progressValue'] as num?)?.toDouble() ?? 0;
    final next = {...pd, 'progressValue': value, if (complete && !hadCompleted) 'completedAt': _nowMs()};
    if (!complete) next.remove('completedAt');
    if (value != stored || complete != hadCompleted) {
      await pRef.update({
        'progressValue': value,
        'progressUpdatedAt': _nowMs(),
        if (complete && !hadCompleted) 'completedAt': _nowMs(),
        if (!complete && hadCompleted) 'completedAt': FieldValue.delete(),
      });
    }
    return ChallengeParticipation.fromDoc(next, targetValue: target);
  }

  Future<Challenge> joinChallenge(String id) => _run((db, uid) async {
    final ref = db.collection('challenges').doc(id);
    final pRef = ref.collection('participants').doc(uid);
    final joinRef = db.collection('users').doc(uid).collection('challengeJoins').doc(id);
    await db.runTransaction<void>((tx) async {
      final c = await tx.get(ref);
      if (!c.exists) throw ApiException(404, 'not_found', 'Challenge not found');
      final cd = _data(c);
      final p = await tx.get(pRef);
      if (p.exists) return;
      if (cd['cancelledAt'] != null) throw ApiException(409, 'challenge_cancelled', 'Challenge was cancelled');
      if (((cd['endsAt'] as num?) ?? 0) < _nowMs()) throw ApiException(409, 'challenge_ended', 'Challenge has ended');
      final cl = cd['clubId'];
      if (cl is String) {
        // Thử thách của club: chỉ thành viên active (rules cũng chặn); người bị cấm giữa kỳ không vào lại được.
        final m = await tx.get(_clubs(db).doc(cl).collection('members').doc(uid));
        if (!m.exists || _data(m)['status'] != 'active') throw ApiException(403, 'club_members_only', 'Club members only');
      }
      final now = _nowMs();
      tx.set(pRef, {
        'userId': uid,
        'joinedAt': now,
        'leaderboardOptIn': false,
        'displayName': _displayName?.call() ?? '',
        'progressValue': 0,
        'progressUpdatedAt': now,
      });
      tx.set(joinRef, {'joinedAt': now, 'leaderboardOptIn': false, 'status': 'active'});
      tx.update(ref, {'participantCount': nextCounter((cd['participantCount'] as num?)?.toInt() ?? 0, 1)});
    });
    final p = await _refreshProgress(db, uid, id);
    final c = await _loadChallenge(db, uid, id);
    return p == null ? c : c.withParticipation(p);
  });

  Future<Challenge> leaveChallenge(String id) => _run((db, uid) async {
    final ref = db.collection('challenges').doc(id);
    final pRef = ref.collection('participants').doc(uid);
    final joinRef = db.collection('users').doc(uid).collection('challengeJoins').doc(id);
    await db.runTransaction<void>((tx) async {
      final c = await tx.get(ref);
      if (!c.exists) throw ApiException(404, 'not_found', 'Challenge not found');
      final p = await tx.get(pRef);
      if (!p.exists) return;
      final cd = _data(c);
      final phase = challengePhase(
        startsAt: (cd['startsAt'] as num?)?.toInt() ?? 0,
        endsAt: (cd['endsAt'] as num?)?.toInt() ?? 0,
        cancelled: cd['cancelledAt'] != null,
        nowMs: _nowMs(),
      );
      if (!canLeaveChallenge(phase)) throw ApiException(409, 'challenge_locked', 'Results are final');
      tx.delete(pRef);
      tx.delete(joinRef);
      tx.update(ref, {'participantCount': nextCounter((_data(c)['participantCount'] as num?)?.toInt() ?? 0, -1)});
    });
    return (await _loadChallenge(db, uid, id)).withParticipation(null);
  });

  /// TM30: top [leaderboardSize] người bật `leaderboardOptIn` + vị trí của tôi. Query có `leaderboardOptIn == true` để
  /// rules (chỉ đọc người bật hiển thị) chứng minh được. Hạng của tôi = số người hơn điểm + số người bằng điểm đạt trước + 1.
  Future<ChallengeLeaderboard> challengeLeaderboard(String id) => _run((db, uid) async {
    final parts = db.collection('challenges').doc(id).collection('participants');
    final visible = parts.where('leaderboardOptIn', isEqualTo: true);
    final top = await visible.orderBy('progressValue', descending: true).orderBy('progressUpdatedAt').limit(leaderboardSize).get();
    final blocked = await _blockedIds(db, uid);
    final entries = rankLeaderboard([for (final d in top.docs) LeaderboardEntry.fromDoc(d.id, Map<String, Object?>.from(d.data()))], hidden: blocked);
    final mine = await parts.doc(uid).get();
    if (!mine.exists) return ChallengeLeaderboard(entries: entries, me: null, optedIn: false, joined: false);
    final md = _data(mine);
    var me = LeaderboardEntry.fromDoc(uid, md);
    final optedIn = md['leaderboardOptIn'] == true;
    if (optedIn) {
      final inTop = entries.where((e) => e.userId == uid);
      if (inTop.isNotEmpty) {
        me = inTop.first;
      } else {
        final ahead = await visible.where('progressValue', isGreaterThan: me.value).count().get();
        final tied = await visible.where('progressValue', isEqualTo: me.value).where('progressUpdatedAt', isLessThan: me.updatedAt).count().get();
        me = me.withRank((ahead.count ?? 0) + (tied.count ?? 0) + 1);
      }
    }
    return ChallengeLeaderboard(entries: entries, me: me, optedIn: optedIn, joined: true);
  });

  /// Bật/tắt hiện tên trên bảng xếp hạng (participant + bản sao trong challengeJoins của tôi).
  Future<void> setLeaderboardOptIn(String id, bool on) => _run((db, uid) async {
    final batch = db.batch()
      ..update(db.collection('challenges').doc(id).collection('participants').doc(uid), {'leaderboardOptIn': on})
      ..set(db.collection('users').doc(uid).collection('challengeJoins').doc(id), {'leaderboardOptIn': on}, SetOptions(merge: true));
    await batch.commit();
  });

  Future<ChallengeParticipation> challengeProgress(String id) => _run((db, uid) async {
    final p = await _refreshProgress(db, uid, id);
    if (p == null) throw ApiException(404, 'not_found', 'You haven’t joined this challenge');
    return p;
  });

  // ---- Routes (M06)
  Future<Set<String>> _savedRouteIds(FirebaseFirestore db, String uid) async {
    final snap = await db.collection('users').doc(uid).collection('savedRoutes').get();
    return {for (final d in snap.docs) d.id};
  }

  Future<ExplorePage<RouteSummary>> searchRoutes({String? region, double? minDistanceM, double? maxDistanceM, String? surface, String? cursor}) =>
      _run((db, uid) async {
        final saved = await _savedRouteIds(db, uid);
        return _scan<RouteSummary>(
          db.collection('routes'),
          orderField: 'name',
          limit: 20,
          cursor: cursor,
          keep: (d) => matchesRouteFilter(d, region: region, minDistanceM: minDistanceM, maxDistanceM: maxDistanceM, surface: surface),
          map: (id, d) async => RouteSummary.fromDoc(id, d, saved: saved.contains(id)),
        );
      });

  Future<List<RouteSummary>> savedRoutes() => _run((db, uid) async {
    final ids = await _savedRouteIds(db, uid);
    final routes = await Future.wait([
      for (final id in ids)
        db.collection('routes').doc(id).get().then<RouteSummary?>((s) => s.exists ? RouteSummary.fromDoc(s.id, _data(s), saved: true) : null),
    ]);
    return [for (final r in routes) ?r]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  Future<RouteDetail> route(String id) => _run((db, uid) async {
    final snap = await db.collection('routes').doc(id).get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Route not found');
    final saved = await db.collection('users').doc(uid).collection('savedRoutes').doc(id).get();
    return RouteDetail.fromDoc(id, _data(snap), saved: saved.exists);
  });

  Future<RouteSummary> saveRoute(String id, bool on) => _run((db, uid) async {
    final snap = await db.collection('routes').doc(id).get();
    if (!snap.exists) throw ApiException(404, 'not_found', 'Route not found');
    final ref = db.collection('users').doc(uid).collection('savedRoutes').doc(id);
    if (on) {
      await ref.set({'savedAt': _nowMs()});
    } else {
      await ref.delete();
    }
    return RouteSummary.fromDoc(id, _data(snap), saved: on);
  });
}

final exploreRepositoryProvider = Provider<ExploreRepository>((ref) {
  bool ready() => ref.read(firebaseReadyProvider);
  return ExploreRepository(
    ready: ready,
    firestore: () => ref.read(firestoreProvider),
    uid: () => ready() ? ref.read(firebaseAuthProvider).currentUser?.uid : null,
    displayName: () => ready() ? ref.read(firebaseAuthProvider).currentUser?.displayName : null,
    localActivities: (from, to) => ref.read(activityRepositoryProvider).allInRange(ref.read(ownerProvider).ownerId, from, to),
  );
});
