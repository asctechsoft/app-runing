import '../../core/network/api_client.dart';
import '../../domain/models/activity.dart';
import 'live_share_models.dart';

enum LiveShareErrorKind {
  network,
  notConfigured,
  unauthorized,

  /// Server chưa có hoạt động này (chưa đồng bộ) → cần tạo bản ghi đang ghi rồi thử lại.
  activityNotFound,
  activityNotActive,
  invalidViewers,
  alreadyActive,

  /// Share đã hết hạn / bị dừng.
  ended,
  viewerNotFound,

  /// Server chưa có endpoint tra cứu tài khoản.
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

  Map<String, Object?> toJson({String? status}) => {
    't': t,
    'lat': lat,
    'lon': lon,
    if (accuracyM != null) 'accuracyM': accuracyM,
    // Trạng thái hoạt động (active/paused). Backend hiện chưa lưu trường này (zod bỏ qua key lạ) — xem báo cáo.
    'status': ?status,
  };
}

/// Client M07 trên các endpoint `/live-shares` của backend. Người xem chỉ đọc (GET), không có trong client này.
class LiveShareRepository {
  LiveShareRepository(this._api);
  final ApiClient _api;

  bool get configured => _api.configured;

  static LiveShareException mapError(Object e, {bool lookup = false}) {
    if (e is LiveShareException) return e;
    if (e is! ApiException) return LiveShareException(LiveShareErrorKind.server, e.toString());
    if (e.status == 0) {
      return e.code == 'not_configured'
          ? LiveShareException(LiveShareErrorKind.notConfigured, 'Live sharing needs a connection to STRIDE servers.')
          : LiveShareException(LiveShareErrorKind.network, 'No connection');
    }
    if (e.status == 401) return LiveShareException(LiveShareErrorKind.unauthorized, 'Sign in again to share your live location.');
    if (e.status == 404) {
      if (lookup) {
        // Envelope not_found = không có tài khoản; 404 không có envelope = route chưa tồn tại.
        return e.code == 'not_found'
            ? LiveShareException(LiveShareErrorKind.viewerNotFound, 'No verified STRIDE account uses that email.')
            : LiveShareException(LiveShareErrorKind.lookupUnavailable, 'Adding people by email isn\'t available on this server yet.');
      }
      return LiveShareException(LiveShareErrorKind.activityNotFound, e.message);
    }
    if (e.status == 409) {
      return switch (e.code) {
        'activity_not_active' => LiveShareException(LiveShareErrorKind.activityNotActive, 'Live sharing works only while a run is in progress.'),
        'live_share_active' => LiveShareException(LiveShareErrorKind.alreadyActive, 'Live sharing is already on for this run.'),
        'live_share_ended' => LiveShareException(LiveShareErrorKind.ended, 'Live sharing has ended.'),
        _ => LiveShareException(LiveShareErrorKind.server, e.message),
      };
    }
    if (e.status == 422 || e.status == 400) {
      return e.code == 'invalid_viewers'
          ? LiveShareException(LiveShareErrorKind.invalidViewers, 'One or more people can\'t follow this run. Check who you selected.')
          : LiveShareException(LiveShareErrorKind.validation, e.message);
    }
    return LiveShareException(LiveShareErrorKind.server, 'STRIDE servers couldn\'t complete the request.');
  }

  Future<T> _guard<T>(Future<T> Function() f, {bool lookup = false}) async {
    try {
      return await f();
    } catch (e) {
      throw mapError(e, lookup: lookup);
    }
  }

  /// POST /live-shares — viewerIds 1…20, ttlMinutes 5…720.
  Future<LiveShareSession> start({required String activityId, required List<String> viewerIds, required int ttlMinutes, String? idempotencyKey}) =>
      _guard(() async {
        final j = await _api.post(
          '/live-shares',
          body: {'activityId': activityId, 'viewerIds': viewerIds, 'ttlMinutes': ttlMinutes},
          idempotencyKey: idempotencyKey,
        );
        return LiveShareSession.fromJson((j as Map).cast<String, Object?>());
      });

  /// POST /live-shares/{id}/points — chỉ điểm mới nhất.
  Future<LiveShareSession> publishPoint(String shareId, LivePoint point, {String? status}) => _guard(() async {
    final j = await _api.post('/live-shares/$shareId/points', body: point.toJson(status: status));
    return LiveShareSession.fromJson((j as Map).cast<String, Object?>());
  });

  /// POST /live-shares/{id}/stop — idempotent phía server.
  Future<void> stop(String shareId) => _guard(() async {
    await _api.post('/live-shares/$shareId/stop', idempotencyKey: 'live-stop-$shareId');
  });

  /// PUT /activities/{id} với status đang ghi để server biết buổi chạy đang diễn ra (yêu cầu của POST /live-shares).
  Future<void> ensureRemoteActivity(Activity a) => _guard(() async {
    final title = a.title.trim().isNotEmpty
        ? a.title.trim()
        : switch (a.type) {
            ActivityType.run => 'Run',
            ActivityType.walk => 'Walk',
            ActivityType.indoorRun => 'Indoor run',
          };
    final status = a.status == ActivityStatus.paused ? 'paused' : 'recording';
    await _api.put(
      '/activities/${a.id}',
      body: {
        'activity': {
          'type': a.type.name,
          'status': status,
          'startedAt': a.startedAt,
          'tzId': a.tzId,
          'tzOffsetMin': a.tzOffsetMin,
          'distanceM': null,
          'movingMs': a.movingMs,
          'elapsedMs': a.elapsedMs,
          'title': title,
          'privacy': a.privacy.name,
          'shareRoute': false,
          'goal': a.goal.toJson(),
          'hasGps': a.hasGps,
          'distanceSource': a.distanceSource.name,
        },
      },
    );
  });

  /// Tra cứu tài khoản STRIDE đã xác minh theo email. ĐỀ XUẤT endpoint `GET /users/lookup?email=` → {id, displayName}
  /// (backend hiện chưa có — khi gọi sẽ ra lookupUnavailable).
  Future<LiveShareViewer> lookupViewerByEmail(String email) => _guard(() async {
    final e = email.trim().toLowerCase();
    final j = await _api.get('/users/lookup', query: {'email': e});
    final m = (j as Map).cast<String, Object?>();
    final name = (m['displayName'] as String?)?.trim();
    return LiveShareViewer(userId: m['id'] as String, label: (name == null || name.isEmpty) ? e : name, email: e);
  }, lookup: true);
}
