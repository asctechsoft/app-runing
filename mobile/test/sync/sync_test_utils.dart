import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/network/api_client.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/data/activity_repository.dart';
import 'package:stride/data/owner_repository.dart';
import 'package:stride/data/settings_repository.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/features/auth/auth_repository.dart';
import 'package:stride/features/sync/sync_service.dart';

const baseUrl = 'http://test.local/api/v1';
const userId = '11111111-1111-4111-8111-111111111111';

/// Bộ dựng môi trường sync với DB thật (ffi in-memory) và server giả (MockClient).
class SyncHarness {
  late AppDatabase db;
  late FakeClock clock;
  late ActivityRepository activities;
  late SettingsRepository settings;
  late AuthRepository auth;
  late SyncService sync;
  late MemoryTokenStore tokens;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request req) handler = (_) async => http.Response('{}', 404);
  OwnerState owner = const OwnerState(ownerId: userId, isGuest: false, email: 'a@example.com', introSeen: true, profileSetupDone: true);

  Future<void> setUp() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
    activities = ActivityRepository(db, clock);
    settings = SettingsRepository(db, clock);
    SharedPreferences.setMockInitialValues({'auth_access_expires_at': clock.nowMs() + 3600 * 1000});
    final prefs = await SharedPreferences.getInstance();
    tokens = MemoryTokenStore();
    await tokens.save(access: 'access-1', refresh: 'refresh-1');
    final client = MockClient((req) async {
      requests.add(req);
      return handler(req);
    });
    auth = AuthRepository(
      api: buildAuthApiClient(baseUrl: baseUrl, tokens: tokens, client: client),
      tokens: tokens,
      prefs: prefs,
      clock: clock,
      http: client,
    );
    sync = SyncService(
      db: db,
      activities: activities,
      settings: settings,
      auth: auth,
      clock: clock,
      owner: () => owner,
      debounce: const Duration(milliseconds: 1),
    );
  }

  Future<void> tearDown() async {
    sync.dispose();
    await db.close();
  }

  Future<Activity> recordAndSave(String owner, {bool gps = false, int points = 0}) async {
    final (a, seg) = await activities.createSession(ownerId: owner, type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
    if (points > 0) {
      await activities.insertPoints([
        for (var i = 0; i < points; i++)
          TrackPoint(activityId: a.id, segmentId: seg.id, seq: i, t: clock.nowMs() + i * 1000, lat: 10 + i * 0.0001, lon: 106, accuracyM: 5),
      ]);
    }
    clock.advance(const Duration(minutes: 30));
    final summary = a.copyWith(distanceM: 5200, movingMs: 1800000, elapsedMs: 1800000, endedAt: clock.nowMs(), title: 'Morning run', hasGps: gps);
    await activities.finalizeSummary(summary);
    return activities.saveActivity(summary);
  }

  Future<List<Map<String, Object?>>> outbox() => db.db.query('sync_outbox', orderBy: 'created_at');

  Future<Map<String, Object?>> activityRow(String id) async => (await db.db.query('activities', where: 'id = ?', whereArgs: [id])).first;

  List<http.Request> calls(String pathSuffix) => requests.where((r) => r.url.path.endsWith(pathSuffix)).toList();
}

http.Response jsonRes(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> firstOp(http.Request r) => ((jsonDecode(r.body) as Map)['operations'] as List).first as Map<String, Object?>;

/// Phản hồi push "acked" cho operation trong request.
http.Response ackPush(http.Request r, {int revision = 1}) {
  final op = firstOp(r);
  return jsonRes({
    'results': [
      {'idempotencyKey': op['idempotencyKey'], 'entity': op['entity'], 'entityId': op['entityId'], 'status': 'acked', 'revision': revision, 'data': {}},
    ],
  });
}

http.Response emptyPull() => jsonRes({'items': [], 'nextCursor': '0', 'hasMore': false});
