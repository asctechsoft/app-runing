import 'package:flutter_test/flutter_test.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/live/live_share_models.dart';
import 'package:stride/features/live/live_share_plugin.dart';
import 'package:stride/features/live/live_share_repository.dart';

class FakeLiveRepo extends LiveShareRepository {
  FakeLiveRepo(this.clock) : super(ready: () => true, firestore: () => throw UnimplementedError(), uid: () => 'user-1');

  final FakeClock clock;
  final starts = <Map<String, Object?>>[];
  final published = <(String, LivePoint, String?)>[];
  final stopped = <String>[];
  final ensured = <String>[];
  LiveShareException? startError;
  LiveShareException? publishError;

  /// Lần start đầu trả activityNotFound (server chưa có hoạt động).
  bool missingActivity = false;

  @override
  Future<LiveShareSession> start({required String activityId, required List<String> viewerIds, required int ttlMinutes, String? idempotencyKey}) async {
    starts.add({'activityId': activityId, 'viewerIds': viewerIds, 'ttl': ttlMinutes});
    if (missingActivity && ensured.isEmpty) throw LiveShareException(LiveShareErrorKind.activityNotFound, 'Activity not found');
    final e = startError;
    if (e != null) throw e;
    return LiveShareSession(id: 'share-1', activityId: activityId, expiresAt: clock.nowMs() + ttlMinutes * 60000, active: true, viewerIds: viewerIds);
  }

  @override
  Future<LiveShareSession> publishPoint(String shareId, LivePoint point, {String? status}) async {
    final e = publishError;
    if (e != null) throw e;
    published.add((shareId, point, status));
    return LiveShareSession(id: shareId, activityId: 'a', expiresAt: clock.nowMs() + 1, active: true, lastUpdateAt: clock.nowMs());
  }

  @override
  Future<void> stop(String shareId) async => stopped.add(shareId);

  @override
  Future<void> ensureRemoteActivity(Activity a) async => ensured.add(a.id);
}

const viewer = LiveShareViewer(userId: '11111111-1111-4111-8111-111111111111', label: 'Jamie');

void main() {
  late FakeClock clock;
  late FakeLiveRepo repo;
  late LiveShareConfig config;
  late List<LiveShareStatus> statuses;
  late LiveSharePlugin plugin;
  late bool guest;
  const activity = Activity(
    id: 'act-1',
    ownerId: 'user-1',
    type: ActivityType.run,
    status: ActivityStatus.recording,
    startedAt: 0,
    tzId: 'UTC',
    tzOffsetMin: 0,
  );

  TrackPoint point(int seq) => TrackPoint(activityId: 'act-1', segmentId: 's', seq: seq, t: clock.nowMs(), lat: 10 + seq / 1000, lon: 106);

  setUp(() {
    clock = FakeClock(1760000000000);
    repo = FakeLiveRepo(clock);
    guest = false;
    config = LiveShareConfig(enabled: true, viewers: const [viewer], consentedAt: clock.nowMs());
    statuses = [];
    plugin = LiveSharePlugin(
      repository: repo,
      clock: clock,
      readConfig: () => config,
      clearConfig: () => config = const LiveShareConfig(),
      onStatus: statuses.add,
      isGuest: () => guest,
    );
  });

  test('mặc định tắt: chưa đồng ý → không start', () async {
    config = const LiveShareConfig(enabled: true, viewers: [viewer]);
    await plugin.onSessionStart(activity);
    await plugin.idle;
    expect(repo.starts, isEmpty);
    expect(plugin.status.phase, LiveSharePhase.off);
  });

  test('guest → không chia sẻ', () async {
    guest = true;
    await plugin.onSessionStart(activity);
    await plugin.idle;
    expect(repo.starts, isEmpty);
  });

  test('start với người xem đã chọn, cấu hình bị xóa sau khi dùng (run sau mặc định tắt)', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    expect(repo.starts.single['viewerIds'], [viewer.userId]);
    expect(repo.starts.single['ttl'], LiveShareExpiry.whenRunEnds.ttlMinutes);
    expect(plugin.status.phase, LiveSharePhase.active);
    expect(config.ready, isFalse);
  });

  test('throttle: tối đa 1 điểm mỗi 10 s, luôn là điểm mới nhất', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    for (var i = 0; i < 31; i++) {
      await plugin.onPoint(activity, point(i));
      await plugin.idle;
      clock.advance(const Duration(seconds: 1));
    }
    // Gửi ở t = 0, 10, 20, 30 s; mỗi lần là điểm mới nhất tại thời điểm đó.
    expect(repo.published.map((p) => p.$2.t - 1760000000000), [0, 10000, 20000, 30000]);
    expect(repo.published.map((p) => p.$2.lat), [10.0, 10.01, 10.02, 10.03]);
    expect(repo.published.every((p) => p.$3 == 'active'), isTrue);
  });

  test('mất mạng: báo interrupted kèm last update, chỉ giữ điểm mới nhất rồi gửi lại', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    clock.advance(const Duration(seconds: 10));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    final lastOk = plugin.status.lastUpdateAt;
    expect(lastOk, isNotNull);

    repo.publishError = LiveShareException(LiveShareErrorKind.network, 'No connection');
    clock.advance(const Duration(seconds: 10));
    await plugin.onPoint(activity, point(1));
    await plugin.idle;
    expect(plugin.status.phase, LiveSharePhase.interrupted);
    expect(plugin.status.lastUpdateAt, lastOk);

    // Nhiều điểm khi mất mạng; khi có mạng lại chỉ gửi điểm mới nhất.
    for (var i = 2; i < 6; i++) {
      clock.advance(const Duration(seconds: 1));
      await plugin.onPoint(activity, point(i));
      await plugin.idle;
    }
    repo.publishError = null;
    clock.advance(const Duration(seconds: 10));
    await plugin.onPoint(activity, point(6));
    await plugin.idle;
    expect(repo.published.map((p) => p.$2.lat), [10.0, 10.006]);
    expect(plugin.status.phase, LiveSharePhase.active);
  });

  test('pause gửi trạng thái paused', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    clock.advance(const Duration(seconds: 10));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    clock.advance(const Duration(seconds: 2));
    await plugin.onPoint(activity, point(1)); // bị throttle, còn chờ
    await plugin.idle;
    await plugin.onPause(activity);
    await plugin.idle;
    expect(plugin.status.phase, LiveSharePhase.paused);
    expect(repo.published.last.$3, 'paused');
  });

  test('kết thúc run → stop share', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    await plugin.onSessionEnd(activity, discarded: false);
    await plugin.idle;
    expect(repo.stopped, ['share-1']);
    expect(plugin.status.phase, LiveSharePhase.ended);
    // Điểm đến sau khi kết thúc không được gửi.
    clock.advance(const Duration(seconds: 30));
    await plugin.onPoint(activity, point(9));
    await plugin.idle;
    expect(repo.published, isEmpty);
  });

  test('huỷ run → stop share', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    await plugin.onSessionEnd(activity, discarded: true);
    await plugin.idle;
    expect(repo.stopped, ['share-1']);
  });

  test('server chưa có hoạt động → tạo bản ghi đang ghi rồi start lại', () async {
    repo.missingActivity = true;
    await plugin.onSessionStart(activity);
    await plugin.idle;
    expect(repo.ensured, ['act-1']);
    expect(repo.starts.length, 2);
    expect(plugin.status.phase, LiveSharePhase.active);
  });

  test('người xem không hợp lệ → failed, không thử lại', () async {
    repo.startError = LiveShareException(LiveShareErrorKind.invalidViewers, 'bad');
    await plugin.onSessionStart(activity);
    await plugin.idle;
    clock.advance(const Duration(seconds: 20));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    expect(repo.starts.length, 1);
    expect(plugin.status.phase, LiveSharePhase.failed);
  });

  test('start lỗi mạng → thử lại theo nhịp điểm', () async {
    repo.startError = LiveShareException(LiveShareErrorKind.network, 'No connection');
    await plugin.onSessionStart(activity);
    await plugin.idle;
    expect(plugin.status.phase, LiveSharePhase.interrupted);
    repo.startError = null;
    clock.advance(const Duration(seconds: 10));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    expect(repo.starts.length, 2);
    expect(repo.published.length, 1);
    expect(plugin.status.phase, LiveSharePhase.active);
  });

  test('hết hạn (1 giờ) → ended, ngừng gửi', () async {
    config = config.copyWith(expiry: LiveShareExpiry.oneHour);
    await plugin.onSessionStart(activity);
    await plugin.idle;
    clock.advance(const Duration(hours: 1, seconds: 1));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    expect(plugin.status.phase, LiveSharePhase.ended);
    expect(repo.published, isEmpty);
  });

  test('người dùng dừng giữa run → stop, không gửi tiếp', () async {
    await plugin.onSessionStart(activity);
    await plugin.idle;
    await plugin.stopSharing();
    await plugin.idle;
    expect(repo.stopped, ['share-1']);
    clock.advance(const Duration(seconds: 20));
    await plugin.onPoint(activity, point(0));
    await plugin.idle;
    expect(repo.published, isEmpty);
  });
}
