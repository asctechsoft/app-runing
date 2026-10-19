import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/explore/explore_logic.dart';
import 'package:stride/features/explore/explore_models.dart';
import 'package:stride/features/explore/explore_repository.dart';

Activity _act(
  String id, {
  ActivityType type = ActivityType.run,
  int startedAt = 1000,
  double? distanceM,
  int movingMs = 0,
  ActivityStatus status = ActivityStatus.saved,
}) => Activity(id: id, ownerId: 'u', type: type, status: status, startedAt: startedAt, tzId: 'UTC', tzOffsetMin: 0, distanceM: distanceM, movingMs: movingMs);

void main() {
  group('cursor', () {
    test('encode/decode vòng tròn, giữ cả số lẫn chuỗi', () {
      final c1 = decodeCursor(encodeCursor(1760000000000, 'p1'))!;
      expect(c1.value, 1760000000000);
      expect(c1.id, 'p1');
      final c2 = decodeCursor(encodeCursor('[DEV] Beach', 'dev-club-beach'))!;
      expect(c2.value, '[DEV] Beach');
      expect(c2.id, 'dev-club-beach');
    });

    test('null/rỗng → null; cursor hỏng → FormatException', () {
      expect(decodeCursor(null), isNull);
      expect(decodeCursor(''), isNull);
      expect(() => decodeCursor('not-base64!!'), throwsA(isA<FormatException>()));
    });
  });

  group('lọc client', () {
    test('matchesClubFilter: tên/vùng không phân biệt hoa thường', () {
      final d = {'name': '[DEV] Riverside Runners', 'nameLower': '[dev] riverside runners', 'region': 'Ho Chi Minh City'};
      expect(matchesClubFilter(d, query: 'RIVERSIDE'), isTrue);
      expect(matchesClubFilter(d, query: 'ho chi'), isTrue, reason: 'khớp cả vùng');
      expect(matchesClubFilter(d, region: 'hanoi'), isFalse);
      expect(matchesClubFilter(d, query: ' ', region: ''), isTrue);
      expect(matchesClubFilter(d, query: 'lake'), isFalse);
    });

    test('matchesRouteFilter: khoảng cách và bề mặt; thiếu distance bị loại khi có cận', () {
      final d = {'region': 'Da Nang', 'distanceM': 10300, 'surface': 'trail'};
      expect(matchesRouteFilter(d, minDistanceM: 5000, maxDistanceM: 12000, surface: 'trail'), isTrue);
      expect(matchesRouteFilter(d, maxDistanceM: 5000), isFalse);
      expect(matchesRouteFilter(d, surface: 'road'), isFalse);
      expect(matchesRouteFilter({'region': 'X'}, minDistanceM: 1), isFalse);
      expect(matchesRouteFilter({'region': 'X'}), isTrue);
    });
  });

  group('luật join/leave', () {
    test('CLB public → active, +1; private → pending, không đổi memberCount', () {
      final pub = decideJoin(visibility: 'public', alreadyMember: false)!;
      expect((pub.status, pub.memberCountDelta), ('active', 1));
      final priv = decideJoin(visibility: 'private', alreadyMember: false)!;
      expect((priv.status, priv.memberCountDelta), ('pending', 0));
    });

    test('đã là thành viên → idempotent (null)', () {
      expect(decideJoin(visibility: 'public', alreadyMember: true), isNull);
    });

    test('owner không được rời; member active -1; pending hoặc count 0 không đổi', () {
      expect(() => decideLeave(role: 'owner', status: 'active', memberCount: 5), throwsA(isA<OwnerCannotLeave>()));
      expect(decideLeave(role: 'member', status: 'active', memberCount: 5), -1);
      expect(decideLeave(role: 'member', status: 'pending', memberCount: 5), 0);
      expect(decideLeave(role: 'member', status: 'active', memberCount: 0), 0);
    });

    test('nextCounter không xuống dưới 0', () {
      expect(nextCounter(0, -1), 0);
      expect(nextCounter(3, 1), 4);
    });
  });

  group('tiến độ thử thách', () {
    final acts = [
      _act('a', startedAt: 1000, distanceM: 5000, movingMs: 1800000),
      _act('b', startedAt: 2000, distanceM: null, movingMs: 600000, type: ActivityType.walk),
      _act('c', startedAt: 3000, distanceM: 2000, movingMs: 900000, type: ActivityType.indoorRun),
      _act('out', startedAt: 9999, distanceM: 100000),
      _act('draft', startedAt: 1500, distanceM: 7000, status: ActivityStatus.awaitingSave),
    ];

    test('distance: chỉ loại hợp lệ, trong khoảng, đã lưu; thiếu distance tính 0', () {
      final v = computeChallengeProgress(acts, metric: ChallengeTarget.distance, activityTypes: ['run', 'indoorRun'], fromMs: 1000, toMs: 5000);
      expect(v, 7000);
    });

    test('count và time', () {
      expect(computeChallengeProgress(acts, metric: ChallengeTarget.count, activityTypes: ['run', 'walk', 'indoorRun'], fromMs: 1000, toMs: 5000), 3);
      expect(computeChallengeProgress(acts, metric: ChallengeTarget.time, activityTypes: ['run', 'walk'], fromMs: 1000, toMs: 5000), 2400000);
    });

    test('biên khoảng thời gian bao gồm cả hai đầu', () {
      expect(computeChallengeProgress(acts, metric: ChallengeTarget.count, activityTypes: ['run'], fromMs: 1000, toMs: 1000), 1);
      expect(computeChallengeProgress(acts, metric: ChallengeTarget.count, activityTypes: ['run'], fromMs: 1001, toMs: 2000), 0);
    });
  });

  group('map document → model', () {
    test('Club.fromDoc + membership active/pending', () {
      final c = Club.fromDoc('c1', {
        'name': 'A',
        'region': 'Hanoi',
        'memberCount': 3,
        'isDevFixture': true,
      }, membership: ClubMembership.fromDoc({'role': 'member', 'status': 'pending'}));
      expect((c.regionText, c.memberCount, c.isDevFixture), ('Hanoi', 3, true));
      expect(c.membership!.isPending, isTrue);
      expect(ClubMembership.fromDoc({'role': 'owner', 'status': 'active'}).isOwner, isTrue);
      expect(() => Club.fromDoc('c1', {'region': 'x'}), throwsA(isA<FormatException>()));
    });

    test('ClubPost/Comment/Event fromDoc', () {
      final p = ClubPost.fromDoc('p', {'clubId': 'c', 'authorId': 'u', 'authorName': 'Jo', 'text': 'hi', 'createdAt': 5, 'cheerCount': 2}, cheeredByMe: true);
      expect((p.authorName, p.cheerCount, p.cheeredByMe, p.createdAt), ('Jo', 2, true, 5));
      final cm = PostComment.fromDoc('k', 'p', {'authorId': 'u', 'text': 'yo', 'createdAt': 6});
      expect((cm.postId, cm.text), ('p', 'yo'));
      final e = ClubEvent.fromDoc('e', {'clubId': 'c', 'title': 'Run', 'startsAt': 100, 'location': 'Park', 'goingCount': 4}, going: true);
      expect((e.startAt, e.meetingPlace, e.goingCount, e.going), (100, 'Park', 4, true));
    });

    test('Challenge.fromDoc: metric/target, ngày dự phòng từ ms, metric lạ → lỗi', () {
      final ch = Challenge.fromDoc('x', {'title': 'T', 'metric': 'distance', 'target': 50000, 'startsAt': 1760000000000, 'endsAt': 1762600000000});
      expect(ch.targetType, ChallengeTarget.distance);
      expect(ch.targetValue, 50000);
      expect(ch.startDate, '2025-10-09');
      expect(ch.activityTypes, ['run', 'walk', 'indoorRun']);
      expect(ch.endDate, '2025-11-08');
      expect(() => Challenge.fromDoc('x', {'title': 'T', 'metric': 'steps', 'target': 1, 'startsAt': 1, 'endsAt': 2}), throwsA(isA<FormatException>()));
    });

    test('ChallengeParticipation.fromDoc: percent kẹp 0–100', () {
      final p = ChallengeParticipation.fromDoc({'joinedAt': 1, 'progressValue': 70000}, targetValue: 50000);
      expect(p.percent, 100);
      expect(ChallengeParticipation.fromDoc({'progressValue': 12500}, targetValue: 50000).percent, 25);
      expect(ChallengeParticipation.fromDoc({'progressValue': 5}, targetValue: 0).percent, 0);
    });

    test('RouteDetail.fromDoc giải mã polyline', () {
      final d = RouteDetail.fromDoc('r', {
        'name': 'N',
        'region': 'X',
        'distanceM': 1000,
        'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'attribution': 'a',
      }, saved: true);
      expect(d.points.length, 3);
      expect(d.summary.saved, isTrue);
    });
  });

  group('mapExploreError', () {
    test('Firebase: unavailable → offline, permission-denied → forbidden, not-found → notFound', () {
      expect(mapExploreError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')).kind, ExploreErrorKind.offline);
      expect(mapExploreError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')).kind, ExploreErrorKind.forbidden);
      expect(mapExploreError(FirebaseException(plugin: 'cloud_firestore', code: 'not-found')).kind, ExploreErrorKind.notFound);
    });

    test('ApiException: not_configured, 401, 409 kèm code, timeout, lỗi parse', () {
      expect(mapExploreError(ApiException(0, 'not_configured', '')).kind, ExploreErrorKind.notConfigured);
      expect(mapExploreError(ApiException(401, 'unauthorized', '')).kind, ExploreErrorKind.signedOut);
      final f = mapExploreError(ApiException(409, 'owner_cannot_leave', ''));
      expect(f.kind, ExploreErrorKind.conflict);
      expect(f.userMessage, 'Transfer club ownership before leaving.');
      expect(mapExploreError(TimeoutException('x')).kind, ExploreErrorKind.offline);
      expect(mapExploreError(const FormatException('bad')).kind, ExploreErrorKind.server);
    });
  });

  group('ExploreRepository: điều kiện đầu vào (không chạm Firestore)', () {
    ExploreRepository repo({required bool ready, String? uid}) =>
        ExploreRepository(ready: () => ready, firestore: () => throw StateError('không được gọi Firestore'), uid: () => uid);

    test('Firebase chưa sẵn sàng → notConfigured', () async {
      await expectLater(repo(ready: false).myClubs(), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.notConfigured)));
    });

    test('chưa đăng nhập → signedOut', () async {
      await expectLater(repo(ready: true).challenges(), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.signedOut)));
      await expectLater(repo(ready: true).requestJoin('c1'), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.signedOut)));
    });
  });
}
