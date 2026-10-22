import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/application/firebase_providers.dart';
import '../services/application/api_client.dart';
import '../controller/providers.dart';
import '../models/data_models/activity.dart';
import '../controller/explore/explore_logic.dart';
import '../models/ui_models/explore_models.dart';

enum ExploreErrorKind { offline, notConfigured, signedOut, notFound, forbidden, conflict, rateLimited, validation, server }

/// Lỗi Explore đã chuẩn hóa để UI hiển thị nguyên nhân cụ thể.
class ExploreFailure implements Exception {
  const ExploreFailure(this.kind, {this.code = '', this.message = ''});
  final ExploreErrorKind kind;
  final String code;
  final String message;

  String get title => switch (kind) {
    ExploreErrorKind.offline => 'You’re offline',
    ExploreErrorKind.notConfigured => 'Not available in this build',
    ExploreErrorKind.signedOut => 'Sign in required',
    ExploreErrorKind.notFound => 'Not found',
    ExploreErrorKind.forbidden => 'Members only',
    ExploreErrorKind.conflict => 'Couldn’t complete that',
    ExploreErrorKind.rateLimited => 'Slow down a little',
    ExploreErrorKind.validation => 'Check your input',
    ExploreErrorKind.server => 'Something went wrong on our side',
  };

  String get userMessage => switch (kind) {
    ExploreErrorKind.offline => 'Check your connection and try again. Explore needs the internet.',
    ExploreErrorKind.notConfigured => 'This build isn’t connected to STRIDE online services.',
    ExploreErrorKind.signedOut => 'Sign in to use clubs, challenges and routes.',
    ExploreErrorKind.notFound => 'It may have been removed or you no longer have access.',
    ExploreErrorKind.forbidden => 'Join this club to see its posts and events.',
    ExploreErrorKind.conflict => _conflictMessage(code, message),
    ExploreErrorKind.rateLimited => 'You’ve done that a lot recently. Try again in a minute.',
    ExploreErrorKind.validation => message.isEmpty ? 'Some details aren’t valid.' : message,
    ExploreErrorKind.server => 'Please try again in a moment.',
  };

  static String _conflictMessage(String code, String message) => switch (code) {
    'owner_cannot_leave' => 'Transfer club ownership before leaving.',
    'challenge_ended' => 'This challenge has ended.',
    'event_cancelled' => 'This event was cancelled.',
    'event_past' => 'This event has already happened.',
    _ => message.isEmpty ? 'Please refresh and try again.' : message,
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

typedef LocalActivitiesLoader = Future<List<Activity>> Function(int fromMs, int toMs);

Map<String, Object?> _data(DocumentSnapshot<Map<String, dynamic>> d) => Map<String, Object?>.from(d.data() ?? const {});

/// Explore trên Cloud Firestore (schema: docs/firestore-schema.md). Mọi thao tác ghi tuân thủ `firestore.rules`
/// (counter chỉ ±1, soft delete bằng `deletedAt`). Lỗi luôn là [ExploreFailure].
class ExploreRepository {
  ExploreRepository({
    required bool Function() ready,
    required FirebaseFirestore Function() firestore,
    required String? Function() uid,
    String? Function()? displayName,
    LocalActivitiesLoader? localActivities,
    int Function()? nowMs,
    Duration timeout = const Duration(seconds: 20),
  }) : _ready = ready,
       _firestore = firestore,
       _uid = uid,
       _displayName = displayName,
       _localActivities = localActivities,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _timeout = timeout;

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
    final snap = await db.collectionGroup('members').where('userId', isEqualTo: uid).get();
    final out = <String, ClubMembership>{};
    for (final d in snap.docs) {
      final clubId = d.reference.parent.parent?.id;
      if (clubId != null) out[clubId] = ClubMembership.fromDoc(_data(d));
    }
    return out;
  }

  Future<Set<String>> _blockedIds(FirebaseFirestore db, String uid) async {
    final snap = await db.collection('users').doc(uid).collection('blocks').get();
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
      throw const ExploreFailure(ExploreErrorKind.validation, code: 'bad_cursor', message: 'Invalid page cursor.');
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
      keep: (d) => matchesClubFilter(d, query: query, region: region),
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

  Future<ClubPost> createPost(String clubId, {required String text}) => _run((db, uid) async {
    final t = text.trim();
    if (t.isEmpty) throw ApiException(400, 'validation_error', 'Write something before posting.');
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
    };
    await db.collection('posts').doc(id).set(data);
    return ClubPost.fromDoc(id, data);
  });

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
    if (t.isEmpty) throw ApiException(400, 'validation_error', 'Write a comment first.');
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
    if (userId == uid) throw ApiException(400, 'validation_error', 'You can’t block yourself.');
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
      if (going && !r.exists) {
        if (d['cancelledAt'] != null) throw ApiException(409, 'event_cancelled', 'Event was cancelled');
        if (((d['endsAt'] ?? d['startsAt']) as num? ?? 0) < _nowMs()) throw ApiException(409, 'event_past', 'Event already happened');
        tx.set(rsvpRef, {'createdAt': _nowMs()});
        count = nextCounter(count, 1);
        tx.update(eventRef, {'goingCount': count});
        isGoing = true;
      } else if (!going && r.exists) {
        tx.delete(rsvpRef);
        count = nextCounter(count, -1);
        tx.update(eventRef, {'goingCount': count});
        isGoing = false;
      }
      return ClubEvent.fromDoc(eventId, {...d, 'goingCount': count}, going: isGoing);
    });
  });

  // ---- Challenges (M05)
  Future<List<Challenge>> challenges() => _run((db, uid) async {
    final snap = await db.collection('challenges').orderBy('endsAt', descending: true).limit(50).get();
    final joins = await db.collection('users').doc(uid).collection('challengeJoins').get();
    final active = {
      for (final j in joins.docs)
        if (_data(j)['status'] != 'left') j.id,
    };
    return Future.wait([
      for (final c in snap.docs)
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
      if (((cd['endsAt'] as num?) ?? 0) < _nowMs()) throw ApiException(409, 'challenge_ended', 'Challenge has ended');
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
      tx.delete(pRef);
      tx.delete(joinRef);
      tx.update(ref, {'participantCount': nextCounter((_data(c)['participantCount'] as num?)?.toInt() ?? 0, -1)});
    });
    return (await _loadChallenge(db, uid, id)).withParticipation(null);
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
