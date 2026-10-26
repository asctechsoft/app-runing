import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/repository/live_share_repository.dart';

void main() {
  test('normalizeEmail/isLookupEmail', () {
    expect(normalizeEmail('  Jamie@Example.COM '), 'jamie@example.com');
    expect(isLookupEmail('jamie@example.com'), isTrue);
    expect(isLookupEmail('a/b@example.com'), isFalse);
    expect(isLookupEmail('no-at'), isFalse);
    expect(isLookupEmail('a b@example.com'), isFalse);
  });

  test('validateViewerIds: 1…20, bỏ trùng, không gồm chủ', () {
    expect(validateViewerIds(['a', 'a', 'b'], ownerId: 'me'), ['a', 'b']);
    expect(() => validateViewerIds([], ownerId: 'me'), throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.invalidViewers)));
    expect(() => validateViewerIds(['me'], ownerId: 'me'), throwsA(isA<LiveShareException>()));
    expect(() => validateViewerIds([for (var i = 0; i < 21; i++) 'v$i'], ownerId: 'me'), throwsA(isA<LiveShareException>()));
    expect(validateViewerIds([for (var i = 0; i < 20; i++) 'v$i'], ownerId: 'me').length, 20);
  });

  test('clampTtlMinutes giữ 5…720', () {
    expect(clampTtlMinutes(1), 5);
    expect(clampTtlMinutes(60), 60);
    expect(clampTtlMinutes(5000), 720);
  });

  test('liveSessionFromDoc / liveShareIsLive', () {
    final d = {
      'activityId': 'a1',
      'expiresAt': 2000,
      'status': 'paused',
      'lastPointAt': 1500,
      'viewerIds': ['u2'],
    };
    final s = liveSessionFromDoc('s1', d);
    expect((s.id, s.activityId, s.active, s.lastUpdateAt), ('s1', 'a1', true, 1500));
    expect(s.viewerIds, ['u2']);
    expect(liveShareIsLive(d, 1999), isTrue);
    expect(liveShareIsLive(d, 2000), isFalse, reason: 'quá hạn');
    expect(liveShareIsLive({...d, 'status': 'ended'}, 1000), isFalse);
    expect(liveSessionFromDoc('s1', {...d, 'status': 'ended'}).active, isFalse);
  });

  test('LivePoint.toDoc không chứa trạng thái', () {
    const p = LivePoint(t: 1, lat: 10, lon: 106, accuracyM: 5);
    expect(p.toDoc(), {'t': 1, 'lat': 10.0, 'lon': 106.0, 'accuracyM': 5.0});
    expect(const LivePoint(t: 1, lat: 1, lon: 2).toDoc().containsKey('accuracyM'), isFalse);
  });

  test('mapError: Firebase/timeout/401/lookup 404', () {
    expect(LiveShareRepository.mapError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')).kind, LiveShareErrorKind.network);
    expect(LiveShareRepository.mapError(TimeoutException('x')).kind, LiveShareErrorKind.network);
    expect(LiveShareRepository.mapError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')).kind, LiveShareErrorKind.unauthorized);
    expect(LiveShareRepository.mapError(ApiException(0, 'not_configured', '')).kind, LiveShareErrorKind.notConfigured);
    expect(LiveShareRepository.mapError(ApiException(409, 'live_share_active', '')).kind, LiveShareErrorKind.alreadyActive);
    expect(LiveShareRepository.mapError(ApiException(404, 'not_found', ''), lookup: true).kind, LiveShareErrorKind.viewerNotFound);
  });

  group('điều kiện đầu vào (không chạm Firestore)', () {
    LiveShareRepository repo({required bool ready, String? uid}) =>
        LiveShareRepository(ready: () => ready, firestore: () => throw StateError('không được gọi Firestore'), uid: () => uid);

    test('configured theo Firebase sẵn sàng', () {
      expect(repo(ready: true).configured, isTrue);
      expect(repo(ready: false).configured, isFalse);
    });

    test('chưa cấu hình → notConfigured; chưa đăng nhập → unauthorized', () async {
      await expectLater(repo(ready: false).stop('s'), throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.notConfigured)));
      await expectLater(
        repo(ready: true).lookupViewerByEmail('a@b.co'),
        throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.unauthorized)),
      );
    });

    test('ensureRemoteActivity là no-op an toàn', () async {
      // Không ném và không gọi Firestore.
      const a = Activity(id: 'a', ownerId: 'u', type: ActivityType.run, status: ActivityStatus.recording, startedAt: 0, tzId: 'UTC', tzOffsetMin: 0);
      await repo(ready: false).ensureRemoteActivity(a);
    });
  });
}
