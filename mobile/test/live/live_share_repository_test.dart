import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/live/live_share_repository.dart';

http.Response envelope(int status, String code, [String message = 'x']) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;

  LiveShareRepository repoWith(Future<http.Response> Function(http.Request) handler, {String baseUrl = 'http://test/api/v1'}) {
    requests = [];
    final client = MockClient((r) {
      requests.add(r);
      return handler(r);
    });
    final tokens = MemoryTokenStore()..save(access: 'tok', refresh: 'ref');
    return LiveShareRepository(ApiClient(baseUrl: baseUrl, tokens: tokens, client: client));
  }

  test('start gửi viewerIds + ttl và parse phản hồi', () async {
    final repo = repoWith(
      (r) async => http.Response(
        jsonEncode({
          'id': 's1',
          'activityId': 'a1',
          'ownerId': 'u',
          'startedAt': 1,
          'expiresAt': 99,
          'stoppedAt': null,
          'active': true,
          'lastPoint': null,
          'lastUpdateAt': null,
          'viewerIds': ['v1'],
        }),
        201,
      ),
    );
    final s = await repo.start(activityId: 'a1', viewerIds: ['v1'], ttlMinutes: 60);
    expect(s.id, 's1');
    expect(s.expiresAt, 99);
    expect(s.viewerIds, ['v1']);
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/api/v1/live-shares');
    expect(jsonDecode(r.body), {
      'activityId': 'a1',
      'viewerIds': ['v1'],
      'ttlMinutes': 60,
    });
    expect(r.headers['Authorization'], 'Bearer tok');
  });

  test('ánh xạ lỗi start', () async {
    Future<LiveShareErrorKind> kindFor(http.Response res) async {
      final repo = repoWith((_) async => res);
      try {
        await repo.start(activityId: 'a1', viewerIds: ['v1'], ttlMinutes: 60);
        fail('expected error');
      } on LiveShareException catch (e) {
        return e.kind;
      }
    }

    expect(await kindFor(envelope(422, 'invalid_viewers')), LiveShareErrorKind.invalidViewers);
    expect(await kindFor(envelope(422, 'validation_error')), LiveShareErrorKind.validation);
    expect(await kindFor(envelope(409, 'activity_not_active')), LiveShareErrorKind.activityNotActive);
    expect(await kindFor(envelope(409, 'live_share_active')), LiveShareErrorKind.alreadyActive);
    expect(await kindFor(envelope(404, 'not_found')), LiveShareErrorKind.activityNotFound);
    expect(await kindFor(envelope(500, 'internal')), LiveShareErrorKind.server);
  });

  test('publish khi share đã kết thúc → ended', () async {
    final repo = repoWith((_) async => envelope(409, 'live_share_ended'));
    await expectLater(
      repo.publishPoint('s1', const LivePoint(t: 1, lat: 10, lon: 106)),
      throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.ended)),
    );
    expect(requests.single.url.path, '/api/v1/live-shares/s1/points');
    expect(jsonDecode(requests.single.body), {'t': 1, 'lat': 10.0, 'lon': 106.0});
  });

  test('lỗi mạng → network', () async {
    final repo = repoWith((_) async => throw http.ClientException('offline'));
    await expectLater(
      repo.publishPoint('s1', const LivePoint(t: 1, lat: 10, lon: 106), status: 'paused'),
      throwsA(isA<LiveShareException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
    );
  });

  test('chưa cấu hình server → notConfigured', () async {
    final repo = repoWith((_) async => http.Response('', 200), baseUrl: '');
    expect(repo.configured, isFalse);
    await expectLater(repo.stop('s1'), throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.notConfigured)));
  });

  test('stop gọi endpoint stop', () async {
    final repo = repoWith((_) async => http.Response('{}', 200));
    await repo.stop('s1');
    expect(requests.single.url.path, '/api/v1/live-shares/s1/stop');
    expect(requests.single.method, 'POST');
  });

  test('lookup: tìm thấy / không có tài khoản / server chưa có endpoint', () async {
    var repo = repoWith((_) async => http.Response(jsonEncode({'id': 'u2', 'displayName': 'Jamie'}), 200));
    final v = await repo.lookupViewerByEmail(' Jamie@Example.com ');
    expect(v.userId, 'u2');
    expect(v.label, 'Jamie');
    expect(requests.single.url.queryParameters['email'], 'jamie@example.com');

    repo = repoWith((_) async => envelope(404, 'not_found'));
    await expectLater(repo.lookupViewerByEmail('a@b.co'), throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.viewerNotFound)));

    repo = repoWith((_) async => http.Response('<html>404</html>', 404));
    await expectLater(
      repo.lookupViewerByEmail('a@b.co'),
      throwsA(isA<LiveShareException>().having((e) => e.kind, 'kind', LiveShareErrorKind.lookupUnavailable)),
    );
  });

  test('ensureRemoteActivity PUT hoạt động đang ghi, riêng tư, có tiêu đề mặc định', () async {
    final repo = repoWith((_) async => http.Response('{}', 201));
    await repo.ensureRemoteActivity(
      const Activity(id: 'a1', ownerId: 'u', type: ActivityType.run, status: ActivityStatus.recording, startedAt: 5, tzId: 'UTC', tzOffsetMin: 0),
    );
    final r = requests.single;
    expect(r.method, 'PUT');
    expect(r.url.path, '/api/v1/activities/a1');
    final body = (jsonDecode(r.body) as Map)['activity'] as Map;
    expect(body['status'], 'recording');
    expect(body['privacy'], 'onlyMe');
    expect(body['title'], 'Run');
    expect(body['distanceM'], isNull);
  });
}
