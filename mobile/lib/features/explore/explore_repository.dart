import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import 'explore_models.dart';

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
    ExploreErrorKind.notConfigured => 'This build isn’t connected to a STRIDE server.',
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

/// Map mọi lỗi (ApiException, parse) sang ExploreFailure.
ExploreFailure mapExploreError(Object e) {
  if (e is ExploreFailure) return e;
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
  // FormatException / TypeError: phản hồi không đúng hợp đồng.
  return const ExploreFailure(ExploreErrorKind.server, code: 'bad_response');
}

/// Client Explore trên ApiClient (base .../api/v1). Path theo backend/app/api/v1/**.
class ExploreRepository {
  ExploreRepository(this._api);
  final ApiClient _api;
  static const _uuid = Uuid();

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw mapExploreError(e);
    }
  }

  Map<String, String> _q(Map<String, Object?> m) => {
    for (final e in m.entries)
      if (e.value != null && '${e.value}'.trim().isNotEmpty) e.key: '${e.value}'.trim(),
  };

  Map<String, Object?> _obj(Object? j) => j is Map ? j.cast<String, Object?>() : throw const FormatException('Expected object');

  String _key() => _uuid.v4();

  // ---- Clubs (M02)
  Future<ExplorePage<Club>> searchClubs({String? query, String? region, String? cursor, int limit = 20}) =>
      _run(() async => ExplorePage.parse(await _api.get('/clubs', query: _q({'q': query, 'region': region, 'cursor': cursor, 'limit': limit})), Club.fromJson));

  Future<List<Club>> myClubs() => _run(() async => ExplorePage.parse(await _api.get('/me/clubs'), Club.fromJson).items);

  Future<Club> club(String id) => _run(() async => Club.fromJson(_obj(await _api.get('/clubs/$id'))));

  Future<ClubMembership?> requestJoin(String clubId) =>
      _run(() async => ClubMembership.parse(_obj(await _api.post('/clubs/$clubId/join', idempotencyKey: _key()))['membership']));

  Future<ClubMembership?> leaveClub(String clubId) =>
      _run(() async => ClubMembership.parse(_obj(await _api.post('/clubs/$clubId/leave', idempotencyKey: _key()))['membership']));

  // ---- Feed (M03)
  Future<ExplorePage<ClubPost>> posts(String clubId, {String? cursor}) =>
      _run(() async => ExplorePage.parse(await _api.get('/clubs/$clubId/posts', query: _q({'cursor': cursor})), ClubPost.fromJson));

  Future<ClubPost> createPost(String clubId, {required String text}) =>
      _run(() async => ClubPost.fromJson(_obj(await _api.post('/clubs/$clubId/posts', body: {'id': _key(), 'text': text}, idempotencyKey: _key()))));

  Future<ClubPost> cheer(String postId, bool on) => _run(
    () async => ClubPost.fromJson(_obj(on ? await _api.post('/posts/$postId/cheers', idempotencyKey: _key()) : await _api.delete('/posts/$postId/cheers'))),
  );

  Future<void> deletePost(String postId) => _run(() async => _api.delete('/posts/$postId', idempotencyKey: _key()));

  Future<ExplorePage<PostComment>> comments(String postId, {String? cursor}) =>
      _run(() async => ExplorePage.parse(await _api.get('/posts/$postId/comments', query: _q({'cursor': cursor})), PostComment.fromJson));

  Future<PostComment> addComment(String postId, String text) =>
      _run(() async => PostComment.fromJson(_obj(await _api.post('/posts/$postId/comments', body: {'text': text}, idempotencyKey: _key()))));

  Future<void> deleteComment(String commentId) => _run(() async => _api.delete('/comments/$commentId', idempotencyKey: _key()));

  /// targetType: post | comment | user.
  Future<void> report({required String targetType, required String targetId, required String reason}) =>
      _run(() async => _api.post('/reports', body: {'targetType': targetType, 'targetId': targetId, 'reason': reason}, idempotencyKey: _key()));

  Future<void> blockUser(String userId) => _run(() async => _api.post('/me/blocks', body: {'userId': userId}, idempotencyKey: _key()));

  // ---- Events (M04)
  Future<ExplorePage<ClubEvent>> events(String clubId, {String? cursor}) =>
      _run(() async => ExplorePage.parse(await _api.get('/clubs/$clubId/events', query: _q({'cursor': cursor})), ClubEvent.fromJson));

  Future<ClubEvent> rsvp(String eventId, bool going) => _run(
    () async => ClubEvent.fromJson(_obj(going ? await _api.post('/events/$eventId/rsvp', idempotencyKey: _key()) : await _api.delete('/events/$eventId/rsvp'))),
  );

  // ---- Challenges (M05)
  Future<List<Challenge>> challenges() => _run(() async => ExplorePage.parse(await _api.get('/challenges'), Challenge.fromJson).items);

  Future<Challenge> challenge(String id) => _run(() async => Challenge.fromJson(_obj(await _api.get('/challenges/$id'))));

  Future<Challenge> joinChallenge(String id) =>
      _run(() async => Challenge.fromJson(_obj(await _api.post('/challenges/$id/join', body: {'leaderboardOptIn': false}, idempotencyKey: _key()))));

  Future<Challenge> leaveChallenge(String id) => _run(() async => Challenge.fromJson(_obj(await _api.post('/challenges/$id/leave', idempotencyKey: _key()))));

  Future<ChallengeParticipation> challengeProgress(String id) =>
      _run(() async => ChallengeParticipation.fromJson(_obj(await _api.get('/challenges/$id/progress'))));

  // ---- Routes (M06)
  Future<ExplorePage<RouteSummary>> searchRoutes({String? region, double? minDistanceM, double? maxDistanceM, String? surface, String? cursor}) => _run(
    () async => ExplorePage.parse(
      await _api.get(
        '/routes',
        query: _q({'region': region, 'minDistanceM': minDistanceM?.round(), 'maxDistanceM': maxDistanceM?.round(), 'surface': surface, 'cursor': cursor}),
      ),
      RouteSummary.fromJson,
    ),
  );

  Future<List<RouteSummary>> savedRoutes() => _run(() async => ExplorePage.parse(await _api.get('/me/saved-routes'), RouteSummary.fromJson).items);

  Future<RouteDetail> route(String id) => _run(() async => RouteDetail.fromJson(_obj(await _api.get('/routes/$id'))));

  Future<RouteSummary> saveRoute(String id, bool on) =>
      _run(() async => RouteSummary.fromJson(_obj(on ? await _api.post('/routes/$id/save', idempotencyKey: _key()) : await _api.delete('/routes/$id/save'))));
}

final exploreRepositoryProvider = Provider<ExploreRepository>((ref) => ExploreRepository(ref.watch(apiClientProvider)));
