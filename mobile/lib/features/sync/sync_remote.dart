import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/network/api_client.dart';
import '../../domain/models/activity.dart';
import 'sha256.dart';

/// Số điểm tối đa mỗi chunk track (document Firestore phải < 1 MiB).
const kTrackChunkPoints = 500;

/// Kết quả đẩy một thao tác lên Firestore (thay cho phản hồi `/sync/push`).
enum PushStatus { acked, conflict, rejected }

class PushResult {
  const PushResult.acked(this.revision) : status = PushStatus.acked, code = null, server = null;
  const PushResult.conflict(this.code, this.server) : status = PushStatus.conflict, revision = null;
  const PushResult.rejected(this.code) : status = PushStatus.rejected, revision = null, server = null;

  final PushStatus status;
  final int? revision;
  final String? code;

  /// Snapshot phía server (đã chuẩn hóa) khi xung đột; `_handleConflict` dùng để giữ cả hai bản.
  final Map<String, Object?>? server;
}

/// Một trang kết quả pull; `items` đã ở dạng `{entity, entityId, op, revision, data}`.
class PullPage {
  const PullPage(this.items, this.nextCursorUs, this.hasMore);
  final List<Map<String, Object?>> items;
  final int? nextCursorUs;
  final bool hasMore;
}

/// Các thao tác Firestore mà engine sync cần. Có bản thật ([FirestoreSyncRemote]) và bản in-memory trong test.
abstract class SyncRemote {
  Future<PushResult> pushActivity(String uid, String id, {required int? expectedRevision, required Map<String, Object?>? body, required int nowMs});
  Future<PushResult> pushProfile(String uid, {required int? expectedRevision, required Map<String, Object?> profile, required int nowMs});
  Future<int?> profileRevision(String uid);
  Future<void> putGoal(String uid, String goalId, Map<String, Object?> data);
  Future<void> putTrackChunk(String uid, String activityId, int seq, Map<String, Object?> doc);
  Future<List<Map<String, Object?>>> getTrackChunks(String uid, String activityId);
  Future<PullPage> pullActivities(String uid, {int? afterUs, required int limit});
  Future<List<Map<String, Object?>>> pullGoals(String uid, {int? afterCreatedAt, required int limit});

  /// Tài liệu `users/{uid}` đã chuẩn hóa (null nếu chưa có).
  Future<Map<String, Object?>?> getUserDoc(String uid);
}

// ---------------- Hàm thuần (test được) ----------------

String trackChunkDocId(int seq) => seq.toString().padLeft(5, '0');

/// Đổi chunk từ [buildTrackChunksFn] thành document `{seq,count,sha256,json}`.
List<Map<String, Object?>> trackChunkDocs(List<Map<String, Object?>> chunks) => [
  for (var i = 0; i < chunks.length; i++) trackChunkDoc(i, chunks[i]),
];

Map<String, Object?> trackChunkDoc(int seq, Map<String, Object?> chunk) {
  final json = jsonEncode(chunk);
  return {'seq': seq, 'count': (chunk['points'] as List).length, 'sha256': sha256Hex(utf8.encode(json)), 'json': json};
}

/// Dựng segments/points từ các document chunk (đã sắp theo seq). Chunk sai checksum bị bỏ qua cả track (ném lỗi) để không bịa tuyến.
(List<TrackSegment>, List<TrackPoint>) parseTrackChunks(String activityId, List<Map<String, Object?>> docs) {
  final sorted = [...docs]..sort((a, b) => ((a['seq'] as num?) ?? 0).compareTo((b['seq'] as num?) ?? 0));
  final segments = <String, TrackSegment>{};
  final points = <TrackPoint>[];
  for (final d in sorted) {
    final json = d['json'] as String?;
    if (json == null) throw const FormatException('chunk thiếu json');
    final sum = d['sha256'] as String?;
    if (sum != null && sum != sha256Hex(utf8.encode(json))) throw const FormatException('chunk sai checksum');
    final chunk = (jsonDecode(json) as Map).cast<String, Object?>();
    for (final s in (chunk['segments'] as List? ?? const []).whereType<Map>()) {
      final id = s['id'] as String;
      segments.putIfAbsent(
        id,
        () => TrackSegment(
          id: id,
          activityId: activityId,
          seq: (s['seq'] as num).toInt(),
          startedAt: (s['startedAt'] as num).toInt(),
          endedAt: (s['endedAt'] as num?)?.toInt(),
          reason: SegmentReason.values.firstWhere((r) => r.name == s['reason'], orElse: () => SegmentReason.start),
        ),
      );
    }
    for (final p in (chunk['points'] as List? ?? const []).whereType<Map>()) {
      points.add(
        TrackPoint(
          activityId: activityId,
          segmentId: p['segmentId'] as String,
          seq: (p['seq'] as num).toInt(),
          t: (p['t'] as num).toInt(),
          lat: (p['lat'] as num).toDouble(),
          lon: (p['lon'] as num).toDouble(),
          accuracyM: (p['accuracyM'] as num?)?.toDouble(),
          altitudeM: (p['altitudeM'] as num?)?.toDouble(),
          speedMps: (p['speedMps'] as num?)?.toDouble(),
          accepted: p['accepted'] as bool? ?? true,
          rejectReason: p['rejectReason'] as String?,
        ),
      );
    }
  }
  final segList = segments.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  return (segList, points);
}

/// Timestamp → epoch ms (đệ quy qua Map/List); mọi giá trị khác giữ nguyên.
Object? normalizeFirestoreValue(Object? v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is Map) return {for (final e in v.entries) e.key as String: normalizeFirestoreValue(e.value)};
  if (v is List) return [for (final e in v) normalizeFirestoreValue(e)];
  return v;
}

Map<String, Object?> normalizeFirestoreMap(Map<String, Object?> m) => (normalizeFirestoreValue(m) as Map).cast<String, Object?>();

/// Thời điểm serverUpdatedAt (µs) của document đã đọc; null nếu chưa có.
int? serverUpdatedAtUs(Object? v) {
  if (v is Timestamp) return v.microsecondsSinceEpoch;
  if (v is num) return v.toInt();
  return null;
}

/// Cursor mới sau một trang: lớn nhất trong trang và cursor cũ (không bao giờ lùi).
int? nextCursorUs(int? previous, Iterable<int> pageValues) {
  var best = previous;
  for (final v in pageValues) {
    if (best == null || v > best) best = v;
  }
  return best;
}

/// Dạng item pull từ một document activity: tombstone → op 'delete'.
Map<String, Object?> pullItemFromActivityDoc(String id, Map<String, Object?> normalized) {
  final deletedAt = (normalized['deletedAt'] as num?)?.toInt();
  final data = {...normalized}
    ..remove('serverUpdatedAt')
    ..['id'] = id;
  return {'entity': 'activity', 'entityId': id, 'op': deletedAt != null ? 'delete' : 'upsert', 'revision': (normalized['revision'] as num?)?.toInt(), 'data': data};
}

/// Quyết định ghi activity theo revision (kiểm trong transaction).
/// - [existing] null: chưa có document.
/// - Ghi lặp lại của chính thao tác vừa thành công (revision = expected + 1 và nội dung giống) → ack, không tăng revision.
class ActivityPushDecision {
  const ActivityPushDecision.write(this.newRevision) : result = null;
  const ActivityPushDecision.done(this.result) : newRevision = null;
  final int? newRevision;
  final PushResult? result;
  bool get shouldWrite => newRevision != null;
}

ActivityPushDecision decideActivityPush({
  required Map<String, Object?>? existing,
  required int? expectedRevision,
  required Map<String, Object?>? body, // null = delete
  required String id,
}) {
  final isDelete = body == null;
  if (existing == null) {
    if (isDelete) return const ActivityPushDecision.done(PushResult.rejected('not_found'));
    return const ActivityPushDecision.write(1);
  }
  final rev = (existing['revision'] as num?)?.toInt() ?? 0;
  final deleted = existing['deletedAt'] != null;
  Map<String, Object?> serverSnap() => {...existing, 'id': id, 'revision': rev};
  if (deleted) {
    // Tombstone thắng; xóa lại là idempotent.
    return isDelete ? ActivityPushDecision.done(PushResult.acked(rev)) : ActivityPushDecision.done(PushResult.conflict('activity_deleted', serverSnap()));
  }
  if (isDelete) return ActivityPushDecision.write(rev + 1); // ý định xóa rõ ràng, không chặn theo revision
  if (expectedRevision == rev) return ActivityPushDecision.write(rev + 1);
  if (rev == (expectedRevision ?? 0) + 1 && deepEqualsLoose(body, {for (final k in body.keys) k: existing[k]})) {
    return ActivityPushDecision.done(PushResult.acked(rev)); // lần ghi trước đã thành công, phản hồi bị mất
  }
  return ActivityPushDecision.done(PushResult.conflict(expectedRevision == null ? 'revision_required' : 'revision_conflict', serverSnap()));
}

/// Tương tự [decideActivityPush] cho profile (`profileRevision`, mặc định 0).
ActivityPushDecision decideProfilePush({required Map<String, Object?>? existingDoc, required int? expectedRevision, required Map<String, Object?> profile}) {
  final rev = (existingDoc?['profileRevision'] as num?)?.toInt() ?? 0;
  final current = (existingDoc?['profile'] as Map?)?.cast<String, Object?>();
  if (expectedRevision == rev || (expectedRevision == null && rev == 0)) return ActivityPushDecision.write(rev + 1);
  if (rev == (expectedRevision ?? 0) + 1 && current != null && deepEqualsLoose(profile, current)) {
    return ActivityPushDecision.done(PushResult.acked(rev));
  }
  return ActivityPushDecision.done(PushResult.conflict(expectedRevision == null ? 'revision_required' : 'revision_conflict', {...?current, 'revision': rev}));
}

/// So sánh sâu, coi 5200 == 5200.0 (số qua Firestore có thể đổi int/double).
bool deepEqualsLoose(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEqualsLoose(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEqualsLoose(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Document activity ghi lên Firestore (chưa gồm `serverUpdatedAt`, do remote đặt).
Map<String, Object?> activityDocFields(Map<String, Object?>? body, int revision, int nowMs) => body == null
    ? {'deletedAt': nowMs, 'revision': revision, 'updatedAt': nowMs}
    : {...body, 'deletedAt': null, 'revision': revision, 'updatedAt': nowMs};

// ---------------- Bản Firestore thật ----------------

class FirestoreSyncRemote implements SyncRemote {
  FirestoreSyncRemote(this._db);

  /// Lazy để không chạm `FirebaseFirestore.instance` khi Firebase chưa sẵn sàng.
  final FirebaseFirestore Function() _db;

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db().collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> _acts(String uid) => _user(uid).collection('activities');

  @override
  Future<PushResult> pushActivity(String uid, String id, {required int? expectedRevision, required Map<String, Object?>? body, required int nowMs}) =>
      guardFirebase(
        () => _db().runTransaction<PushResult>((tx) async {
          final ref = _acts(uid).doc(id);
          final snap = await tx.get(ref);
          final existing = snap.exists ? normalizeFirestoreMap(snap.data()!.cast<String, Object?>()) : null;
          final d = decideActivityPush(existing: existing, expectedRevision: expectedRevision, body: body, id: id);
          if (!d.shouldWrite) return d.result!;
          final fields = {...activityDocFields(body, d.newRevision!, nowMs), 'serverUpdatedAt': FieldValue.serverTimestamp()};
          if (body == null) {
            tx.set(ref, fields, SetOptions(merge: true));
          } else {
            tx.set(ref, fields);
          }
          return PushResult.acked(d.newRevision);
        }),
      );

  @override
  Future<PushResult> pushProfile(String uid, {required int? expectedRevision, required Map<String, Object?> profile, required int nowMs}) => guardFirebase(
    () => _db().runTransaction<PushResult>((tx) async {
      final ref = _user(uid);
      final snap = await tx.get(ref);
      final existing = snap.exists ? normalizeFirestoreMap(snap.data()!.cast<String, Object?>()) : null;
      final d = decideProfilePush(existingDoc: existing, expectedRevision: expectedRevision, profile: profile);
      if (!d.shouldWrite) return d.result!;
      // mergeFields: không đè displayName/email/emailLower/createdAt do tầng auth quản.
      tx.set(ref, {'profile': profile, 'profileRevision': d.newRevision, 'profileUpdatedAt': nowMs}, SetOptions(mergeFields: ['profile', 'profileRevision', 'profileUpdatedAt']));
      return PushResult.acked(d.newRevision);
    }),
  );

  @override
  Future<int?> profileRevision(String uid) => guardFirebase(() async {
    final snap = await _user(uid).get();
    return (snap.data()?['profileRevision'] as num?)?.toInt();
  });

  @override
  Future<void> putGoal(String uid, String goalId, Map<String, Object?> data) => guardFirebase(() => _user(uid).collection('goals').doc(goalId).set(data));

  @override
  Future<void> putTrackChunk(String uid, String activityId, int seq, Map<String, Object?> doc) =>
      guardFirebase(() => _acts(uid).doc(activityId).collection('trackChunks').doc(trackChunkDocId(seq)).set(doc));

  @override
  Future<List<Map<String, Object?>>> getTrackChunks(String uid, String activityId) => guardFirebase(() async {
    final q = await _acts(uid).doc(activityId).collection('trackChunks').orderBy('seq').get();
    return [for (final d in q.docs) d.data().cast<String, Object?>()];
  });

  @override
  Future<PullPage> pullActivities(String uid, {int? afterUs, required int limit}) => guardFirebase(() async {
    var q = _acts(uid).orderBy('serverUpdatedAt');
    if (afterUs != null) q = q.startAfter([Timestamp.fromMicrosecondsSinceEpoch(afterUs)]);
    final res = await q.limit(limit).get();
    final items = <Map<String, Object?>>[];
    final stamps = <int>[];
    for (final d in res.docs) {
      final raw = d.data().cast<String, Object?>();
      final us = serverUpdatedAtUs(raw['serverUpdatedAt']);
      if (us != null) stamps.add(us);
      items.add(pullItemFromActivityDoc(d.id, normalizeFirestoreMap(raw)));
    }
    return PullPage(items, nextCursorUs(afterUs, stamps), res.docs.length >= limit);
  });

  @override
  Future<List<Map<String, Object?>>> pullGoals(String uid, {int? afterCreatedAt, required int limit}) => guardFirebase(() async {
    var q = _user(uid).collection('goals').orderBy('createdAt');
    if (afterCreatedAt != null) q = q.startAfter([afterCreatedAt]);
    final res = await q.limit(limit).get();
    return [
      for (final d in res.docs) {...normalizeFirestoreMap(d.data().cast<String, Object?>()), 'id': d.id},
    ];
  });

  @override
  Future<Map<String, Object?>?> getUserDoc(String uid) => guardFirebase(() async {
    final snap = await _user(uid).get();
    return snap.exists ? normalizeFirestoreMap(snap.data()!.cast<String, Object?>()) : null;
  });
}
