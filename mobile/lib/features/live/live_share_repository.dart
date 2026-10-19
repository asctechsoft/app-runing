import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../domain/models/activity.dart';
import 'live_share_models.dart';

enum LiveShareErrorKind {
  network,
  notConfigured,
  unauthorized,

  /// Không còn dùng với Firestore (server không cần biết activity); giữ để tương thích.
  activityNotFound,
  activityNotActive,
  invalidViewers,
  alreadyActive,

  /// Share đã hết hạn / bị dừng.
  ended,
  viewerNotFound,

  /// Không còn dùng với Firestore (tra cứu qua `userLookup`); giữ để tương thích.
  lookupUnavailable,
  validation,
  server,
}

class LiveShareException implements Exception {
  LiveShareException(this.kind, this.message);
  final LiveShareErrorKind kind;
  final String message;

  bool get isNetwork => kind == LiveShareErrorKind.network;

  @override
  String toString() => 'LiveShareException($kind, $message)';
}

/// Điểm gửi cho người xem: chỉ toạ độ thật + thời điểm (không gửi số liệu suy đoán).
class LivePoint {
  const LivePoint({required this.t, required this.lat, required this.lon, this.accuracyM});
  final int t;
  final double lat;
  final double lon;
  final double? accuracyM;

  factory LivePoint.fromTrack(TrackPoint p) => LivePoint(t: p.t, lat: p.lat, lon: p.lon, accuracyM: p.accuracyM);

  Map<String, Object?> toJson({String? status}) => {'t': t, 'lat': lat, 'lon': lon, if (accuracyM != null) 'accuracyM': accuracyM, 'status': ?status};

  /// Dạng lưu trong `liveShares/{id}.lastPoint` (trạng thái nằm ở trường `status` của document).
  Map<String, Object?> toDoc() => {'t': t, 'lat': lat, 'lon': lon, if (accuracyM != null) 'accuracyM': accuracyM};
}

const maxLiveViewers = 20;
const _minTtlMinutes = 5;
const _maxTtlMinutes = 720;

/// Chuẩn hóa email để tra `userLookup/{emailLower}`.
String normalizeEmail(String email) => email.trim().toLowerCase();

/// Email hợp lệ để dùng làm document ID (có `@`, không có `/`, không khoảng trắng).
bool isLookupEmail(String email) {
  final e = normalizeEmail(email);
  return RegExp(r'^[^\s/@]+@[^\s/@]+\.[^\s/@]+$').hasMatch(e);
}

/// 1…20 người xem, không trùng, không gồm chính chủ.
List<String> validateViewerIds(List<String> viewerIds, {required String ownerId}) {
  final unique = viewerIds.toSet().toList();
  if (unique.isEmpty || unique.length > maxLiveViewers || unique.contains(ownerId)) {
    throw LiveShareException(LiveShareErrorKind.invalidViewers, 'One or more people can\'t follow this run. Check who you selected.');
  }
  return unique;
}

int clampTtlMinutes(int minutes) => minutes.clamp(_minTtlMinutes, _maxTtlMinutes);

/// Dựng [LiveShareSession] từ document `liveShares/{id}`.
LiveShareSession liveSessionFromDoc(String id, Map<String, Object?> d) {
  final status = d['status'];
  return LiveShareSession(
    id: id,
    activityId: (d['activityId'] as String?) ?? '',
    expiresAt: (d['expiresAt'] as num?)?.toInt() ?? 0,
    active: status == 'active' || status == 'paused',
    lastUpdateAt: (d['lastPointAt'] as num?)?.toInt(),
    viewerIds: [for (final v in (d['viewerIds'] as List?) ?? const []) '$v'],
  );
}

/// Share còn hiệu lực: chưa kết thúc và chưa quá hạn.
bool liveShareIsLive(Map<String, Object?> d, int nowMs) => d['status'] != 'ended' && ((d['expiresAt'] as num?)?.toInt() ?? 0) > nowMs;

/// Client M07 trên Firestore `liveShares`. Người xem chỉ đọc (không có trong client này). Chỉ lưu điểm mới nhất (ghi đè).
class LiveShareRepository {
  LiveShareRepository({
    required bool Function() ready,
    required FirebaseFirestore Function() firestore,
    required String? Function() uid,
    int Function()? nowMs,
    Duration timeout = const Duration(seconds: 15),
  }) : _ready = ready,
       _firestore = firestore,
       _uid = uid,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _timeout = timeout;

  final bool Function() _ready;
  final FirebaseFirestore Function() _firestore;
  final String? Function() _uid;
  final int Function() _nowMs;
  final Duration _timeout;
  static const _uuid = Uuid();

  /// Firebase đã sẵn sàng (có thể chia sẻ khi đã đăng nhập).
  bool get configured => _ready();

  static LiveShareException mapError(Object e, {bool lookup = false}) {
    if (e is LiveShareException) return e;
    if (e is TimeoutException) return LiveShareException(LiveShareErrorKind.network, 'No connection');
    if (e is FirebaseException) e = mapFirebaseError(e);
    if (e is! ApiException) return LiveShareException(LiveShareErrorKind.server, e.toString());
    if (e.status == 0) {
      return e.code == 'not_configured'
          ? LiveShareException(LiveShareErrorKind.notConfigured, 'Live sharing needs a connection to STRIDE online services.')
          : LiveShareException(LiveShareErrorKind.network, 'No connection');
    }
    if (e.status == 401) return LiveShareException(LiveShareErrorKind.unauthorized, 'Sign in again to share your live location.');
    if (e.status == 403) return LiveShareException(LiveShareErrorKind.unauthorized, 'You don\'t have permission to do that.');
    if (e.status == 404) {
      return lookup
          ? LiveShareException(LiveShareErrorKind.viewerNotFound, 'No STRIDE account uses that email.')
          : LiveShareException(LiveShareErrorKind.ended, 'Live sharing has ended.');
    }
    if (e.status == 409) {
      return switch (e.code) {
        'live_share_active' => LiveShareException(LiveShareErrorKind.alreadyActive, 'Live sharing is already on for this run.'),
        'live_share_ended' => LiveShareException(LiveShareErrorKind.ended, 'Live sharing has ended.'),
        _ => LiveShareException(LiveShareErrorKind.server, e.message),
      };
    }
    if (e.status == 400 || e.status == 422) return LiveShareException(LiveShareErrorKind.validation, e.message);
    return LiveShareException(LiveShareErrorKind.server, 'STRIDE couldn\'t complete the request.');
  }

  Future<T> _guard<T>(Future<T> Function(FirebaseFirestore db, String uid) f, {bool lookup = false}) async {
    try {
      if (!_ready()) throw ApiException(0, 'not_configured', 'Firebase is not configured');
      final uid = _uid();
      if (uid == null) throw ApiException(401, 'unauthorized', 'Sign in required');
      return await f(_firestore(), uid).timeout(_timeout);
    } catch (e) {
      throw mapError(e, lookup: lookup);
    }
  }

  /// Tạo `liveShares/{id}`. [idempotencyKey] dùng làm ID document → gọi lại sau lỗi mạng không tạo bản trùng.
  /// Đã có share còn hiệu lực cho activity (ID khác) → [LiveShareErrorKind.alreadyActive].
  Future<LiveShareSession> start({required String activityId, required List<String> viewerIds, required int ttlMinutes, String? idempotencyKey}) =>
      _guard((db, uid) async {
        final viewers = validateViewerIds(viewerIds, ownerId: uid);
        final id = idempotencyKey ?? _uuid.v4();
        final col = db.collection('liveShares');
        final now = _nowMs();
        final existing = await col.where('ownerId', isEqualTo: uid).where('activityId', isEqualTo: activityId).get();
        for (final d in existing.docs) {
          final data = Map<String, Object?>.from(d.data());
          if (d.id == id) return liveSessionFromDoc(d.id, data);
          if (liveShareIsLive(data, now)) throw ApiException(409, 'live_share_active', 'Live sharing already active');
        }
        final doc = <String, Object?>{
          'ownerId': uid,
          'activityId': activityId,
          'viewerIds': viewers,
          'startedAt': now,
          'expiresAt': now + clampTtlMinutes(ttlMinutes) * 60000,
          'status': 'active',
          'endedAt': null,
          'lastPoint': null,
          'lastPointAt': null,
        };
        await col.doc(id).set(doc);
        return liveSessionFromDoc(id, doc);
      });

  /// Ghi đè điểm mới nhất (không lưu lịch sử). Share đã kết thúc/hết hạn → [LiveShareErrorKind.ended].
  Future<LiveShareSession> publishPoint(String shareId, LivePoint point, {String? status}) => _guard((db, uid) {
    final ref = db.collection('liveShares').doc(shareId);
    return db.runTransaction<LiveShareSession>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw ApiException(409, 'live_share_ended', 'Share not found');
      final d = Map<String, Object?>.from(snap.data()!);
      final now = _nowMs();
      if (!liveShareIsLive(d, now)) throw ApiException(409, 'live_share_ended', 'Live sharing has ended');
      final st = status == 'paused' ? 'paused' : 'active';
      final update = {'lastPoint': point.toDoc(), 'lastPointAt': now, 'status': st};
      tx.update(ref, update);
      return liveSessionFromDoc(shareId, {...d, ...update});
    });
  });

  /// Idempotent: đã kết thúc hoặc không tồn tại → không làm gì.
  Future<void> stop(String shareId) => _guard((db, uid) {
    final ref = db.collection('liveShares').doc(shareId);
    return db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['status'] == 'ended') return;
      tx.update(ref, {'status': 'ended', 'endedAt': _nowMs()});
    });
  });

  /// Với Firestore server không cần biết activity đang ghi → no-op (giữ chữ ký cho plugin).
  Future<void> ensureRemoteActivity(Activity a) async {}

  /// Tra `userLookup/{emailLower}` → `{uid, displayName}`. Không có → [LiveShareErrorKind.viewerNotFound].
  Future<LiveShareViewer> lookupViewerByEmail(String email) => _guard((db, uid) async {
    final e = normalizeEmail(email);
    if (!isLookupEmail(e)) throw ApiException(404, 'not_found', 'Invalid email');
    final snap = await db.collection('userLookup').doc(e).get();
    final d = snap.data();
    final viewerUid = d?['uid'];
    if (!snap.exists || viewerUid is! String || viewerUid.isEmpty) throw ApiException(404, 'not_found', 'No account');
    if (viewerUid == uid) throw ApiException(400, 'validation_error', 'You can\'t follow your own run.');
    final name = (d?['displayName'] as String?)?.trim();
    return LiveShareViewer(userId: viewerUid, label: (name == null || name.isEmpty) ? e : name, email: e);
  }, lookup: true);
}
