import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/features/explore/explore_models.dart';
import 'package:stride/features/explore/explore_repository.dart';

const _club = {
  'id': '11111111-1111-4111-8111-111111111111',
  'name': 'Central Park Runners',
  'description': 'Weekly easy runs',
  'regionText': 'New York, NY',
  'lat': 40.78,
  'lon': -73.96,
  'ownerId': '22222222-2222-4222-8222-222222222222',
  'memberCount': 246,
  'isDevFixture': false,
  'createdAt': 1760000000000,
  'myMembership': {'role': 'member', 'status': 'pending', 'updatedAt': 1760000000000},
};

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> requests;

  ExploreRepository repoWith(http.Response Function(http.Request r) handler) {
    requests = [];
    final client = MockClient((r) async {
      requests.add(r);
      return handler(r);
    });
    final tokens = MemoryTokenStore();
    tokens.save(access: 'a', refresh: 'r');
    return ExploreRepository(ApiClient(baseUrl: 'https://api.test/api/v1', tokens: tokens, client: client));
  }

  test('searchClubs: gửi q/region, parse page + membership pending', () async {
    final repo = repoWith(
      (_) => _json({
        'items': [_club],
        'nextCursor': 'abc',
      }),
    );
    final page = await repo.searchClubs(query: ' park ', region: 'New York', limit: 20);
    expect(requests.single.url.path, '/api/v1/clubs');
    expect(requests.single.url.queryParameters, {'q': 'park', 'region': 'New York', 'limit': '20'});
    expect(page.nextCursor, 'abc');
    final c = page.items.single;
    expect(c.name, 'Central Park Runners');
    expect(c.memberCount, 246);
    expect(c.membership!.isPending, isTrue);
    expect(c.membership!.isMember, isFalse);
  });

  test('requestJoin: POST có Idempotency-Key, parse membership', () async {
    final repo = repoWith(
      (_) => _json({
        'membership': {'role': 'member', 'status': 'pending', 'updatedAt': 1},
      }),
    );
    final m = await repo.requestJoin(_club['id'] as String);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/clubs/${_club['id']}/join');
    expect(requests.single.headers['Idempotency-Key'], isNotEmpty);
    expect(m!.isPending, isTrue);
  });

  test('feed post không giữ tọa độ dù server gửi route', () async {
    final repo = repoWith(
      (_) => _json({
        'items': [
          {
            'id': 'p1',
            'clubId': 'c1',
            'authorId': 'u1',
            'authorDisplayName': 'Maya',
            'text': 'Great 5 km',
            'activity': {
              'id': 'a1',
              'type': 'run',
              'distanceM': 5000,
              'distanceEstimated': false,
              'movingMs': 1934000,
              'avgPaceSecPerKm': 372,
              'route': {
                'start': {'lat': 1, 'lon': 2},
              },
            },
            'activityHidden': false,
            'commentCount': 4,
            'cheerCount': 28,
            'cheeredByMe': true,
            'createdAt': 1760000000000,
          },
        ],
        'nextCursor': null,
      }),
    );
    final page = await repo.posts('c1');
    final p = page.items.single;
    expect(p.activity!.distanceM, 5000);
    expect(p.cheeredByMe, isTrue);
    expect(page.nextCursor, isNull);
  });

  test('challenge + participation + route polyline', () async {
    final repo = repoWith((r) {
      if (r.url.path.endsWith('/challenges/ch1')) {
        return _json({
          'id': 'ch1',
          'title': 'October 50K',
          'description': '',
          'activityTypes': ['run', 'indoorRun'],
          'startDate': '2026-10-01',
          'endDate': '2026-10-31',
          'tzId': 'America/New_York',
          'targetType': 'distance',
          'targetValue': 50000,
          'participation': {'joinedAt': 1, 'progressValue': 12500, 'targetValue': 50000, 'percent': 25, 'completedAt': null},
        });
      }
      return _json({
        'id': 'r1',
        'name': 'Reservoir loop',
        'region': 'New York',
        'distanceM': 2500,
        'surface': 'trail',
        'attribution': '© OpenStreetMap contributors',
        'saved': false,
        'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'polylineEncoding': 'google-polyline-5',
      });
    });
    final c = await repo.challenge('ch1');
    expect(c.targetType, ChallengeTarget.distance);
    expect(c.participation!.percent, 25);
    expect(c.participation!.completed, isFalse);
    final r = await repo.route('r1');
    expect(r.points.length, 3);
    expect(r.points.first.latitude, closeTo(38.5, 1e-6));
    expect(r.points.first.longitude, closeTo(-120.2, 1e-6));
    expect(r.points.last.latitude, closeTo(43.252, 1e-6));
    expect(r.summary.attribution, contains('OpenStreetMap'));
  });

  group('map lỗi', () {
    Future<ExploreFailure> failWith(http.Response res) async {
      final repo = repoWith((_) => res);
      try {
        await repo.club('x');
      } on ExploreFailure catch (f) {
        return f;
      }
      fail('expected ExploreFailure');
    }

    test('403 not_member → forbidden', () async {
      final f = await failWith(
        _json({
          'error': {'code': 'not_member', 'message': 'Club membership required'},
        }, 403),
      );
      expect(f.kind, ExploreErrorKind.forbidden);
      expect(f.code, 'not_member');
    });

    test('409 owner_cannot_leave → conflict có thông điệp cụ thể', () async {
      final f = await failWith(
        _json({
          'error': {'code': 'owner_cannot_leave', 'message': 'x'},
        }, 409),
      );
      expect(f.kind, ExploreErrorKind.conflict);
      expect(f.userMessage, contains('ownership'));
    });

    test('404/429/500/422', () async {
      expect((await failWith(_json({}, 404))).kind, ExploreErrorKind.notFound);
      expect((await failWith(_json({}, 429))).kind, ExploreErrorKind.rateLimited);
      expect((await failWith(_json({}, 500))).kind, ExploreErrorKind.server);
      expect((await failWith(_json({}, 422))).kind, ExploreErrorKind.validation);
    });

    test('phản hồi sai hợp đồng → server bad_response', () async {
      final f = await failWith(_json({'id': 'only-id'}));
      expect(f.kind, ExploreErrorKind.server);
      expect(f.code, 'bad_response');
    });

    test('mất mạng → offline', () async {
      final repo = ExploreRepository(
        ApiClient(baseUrl: 'https://api.test/api/v1', tokens: MemoryTokenStore(), client: MockClient((_) async => throw http.ClientException('no route'))),
      );
      await expectLater(repo.challenges(), throwsA(isA<ExploreFailure>().having((f) => f.kind, 'kind', ExploreErrorKind.offline)));
    });

    test('build không cấu hình server → notConfigured', () async {
      final repo = ExploreRepository(ApiClient(baseUrl: '', tokens: MemoryTokenStore()));
      await expectLater(repo.myClubs(), throwsA(isA<ExploreFailure>().having((f) => f.kind, 'kind', ExploreErrorKind.notConfigured)));
    });

    test('401 sau khi refresh thất bại → signedOut', () async {
      final f = await failWith(
        _json({
          'error': {'code': 'unauthorized', 'message': 'x'},
        }, 401),
      );
      expect(f.kind, ExploreErrorKind.signedOut);
    });
  });
}
