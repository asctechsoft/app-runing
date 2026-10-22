import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/repository/activity_repository.dart';
import 'package:stride/repository/owner_repository.dart';
import 'package:stride/repository/settings_repository.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/services/application/sync_remote.dart';
import 'package:stride/services/application/sync_service.dart';

const userId = '11111111-1111-4111-8111-111111111111';

/// Bản Firestore in-memory dùng đúng các hàm quyết định thuần của bản thật (revision, tombstone, cursor).
class InMemorySyncRemote implements SyncRemote {
  final activities = <String, Map<String, Map<String, Object?>>>{}; // uid -> id -> doc (kèm _us)
  final users = <String, Map<String, Object?>>{};
  final goals = <String, Map<String, Map<String, Object?>>>{};
  final chunks = <String, Map<String, Map<int, Map<String, Object?>>>>{}; // uid -> activityId -> seq -> doc
  final calls = <String>[];
  int _us = 1000;

  /// Gọi trước mỗi thao tác; ném để giả lập lỗi mạng/quyền.
  Future<void> Function(String method)? hook;

  int count(String method) => calls.where((c) => c == method).length;

  Future<void> _enter(String m) async {
    calls.add(m);
    await hook?.call(m);
  }

  Map<String, Map<String, Object?>> _acts(String uid) => activities.putIfAbsent(uid, () => {});

  /// Giả lập máy khác ghi activity (đi qua cùng logic revision).
  void seedActivity(String uid, String id, Map<String, Object?> fields, {int revision = 1, int? deletedAt}) {
    _acts(uid)[id] = {...fields, 'revision': revision, 'deletedAt': deletedAt, '_us': ++_us};
  }

  @override
  Future<PushResult> pushActivity(String uid, String id, {required int? expectedRevision, required Map<String, Object?>? body, required int nowMs}) async {
    await _enter('pushActivity');
    final stored = _acts(uid)[id];
    final existing = stored == null ? null : ({...stored}..remove('_us'));
    final d = decideActivityPush(existing: existing, expectedRevision: expectedRevision, body: body, id: id);
    if (!d.shouldWrite) return d.result!;
    final fields = activityDocFields(body, d.newRevision!, nowMs);
    _acts(uid)[id] = body == null ? {...?stored, ...fields, '_us': ++_us} : {...fields, '_us': ++_us};
    return PushResult.acked(d.newRevision);
  }

  @override
  Future<PushResult> pushProfile(String uid, {required int? expectedRevision, required Map<String, Object?> profile, required int nowMs}) async {
    await _enter('pushProfile');
    final d = decideProfilePush(existingDoc: users[uid], expectedRevision: expectedRevision, profile: profile);
    if (!d.shouldWrite) return d.result!;
    users[uid] = {...?users[uid], 'profile': profile, 'profileRevision': d.newRevision, 'profileUpdatedAt': nowMs};
    return PushResult.acked(d.newRevision);
  }

  @override
  Future<int?> profileRevision(String uid) async {
    await _enter('profileRevision');
    return (users[uid]?['profileRevision'] as num?)?.toInt();
  }

  @override
  Future<void> putGoal(String uid, String goalId, Map<String, Object?> data) async {
    await _enter('putGoal');
    goals.putIfAbsent(uid, () => {})[goalId] = data;
  }

  @override
  Future<void> putTrackChunk(String uid, String activityId, int seq, Map<String, Object?> doc) async {
    await _enter('putTrackChunk');
    chunks.putIfAbsent(uid, () => {}).putIfAbsent(activityId, () => {})[seq] = doc;
  }

  @override
  Future<List<Map<String, Object?>>> getTrackChunks(String uid, String activityId) async {
    await _enter('getTrackChunks');
    final m = chunks[uid]?[activityId] ?? const <int, Map<String, Object?>>{};
    return [for (final k in (m.keys.toList()..sort())) m[k]!];
  }

  @override
  Future<PullPage> pullActivities(String uid, {int? afterUs, required int limit}) async {
    await _enter('pullActivities');
    final entries = _acts(uid).entries.where((e) => afterUs == null || (e.value['_us'] as int) > afterUs).toList()
      ..sort((a, b) => (a.value['_us'] as int).compareTo(b.value['_us'] as int));
    final page = entries.take(limit).toList();
    return PullPage(
      [
        for (final e in page) pullItemFromActivityDoc(e.key, ({...e.value}..remove('_us'))),
      ],
      nextCursorUs(afterUs, [for (final e in page) e.value['_us'] as int]),
      page.length >= limit,
    );
  }

  @override
  Future<List<Map<String, Object?>>> pullGoals(String uid, {int? afterCreatedAt, required int limit}) async {
    await _enter('pullGoals');
    final all =
        [
            for (final e in (goals[uid] ?? const <String, Map<String, Object?>>{}).entries) {...e.value, 'id': e.key},
          ].where((g) => afterCreatedAt == null || (g['createdAt'] as int) > afterCreatedAt).toList()
          ..sort((a, b) => (a['createdAt'] as int).compareTo(b['createdAt'] as int));
    return all.take(limit).toList();
  }

  @override
  Future<Map<String, Object?>?> getUserDoc(String uid) async {
    await _enter('getUserDoc');
    return users[uid];
  }
}

/// Bộ dựng môi trường sync với DB thật (ffi in-memory) và Firestore giả (in-memory).
class SyncHarness {
  late AppDatabase db;
  late FakeClock clock;
  late ActivityRepository activities;
  late SettingsRepository settings;
  late SyncService sync;
  SyncHarness([InMemorySyncRemote? shared]) : remote = shared ?? InMemorySyncRemote();
  final InMemorySyncRemote remote;
  String? uid = userId;
  bool firebaseReady = true;
  OwnerState owner = const OwnerState(ownerId: userId, isGuest: false, email: 'a@example.com', introSeen: true, profileSetupDone: true);

  Future<void> setUp() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
    activities = ActivityRepository(db, clock);
    settings = SettingsRepository(db, clock);
    SharedPreferences.setMockInitialValues({});
    sync = makeSync();
  }

  SyncService makeSync({int? chunkPoints}) => SyncService(
    db: db,
    activities: activities,
    settings: settings,
    remote: remote,
    uid: () => uid,
    ready: () => firebaseReady,
    clock: clock,
    owner: () => owner,
    debounce: const Duration(milliseconds: 1),
    chunkPoints: chunkPoints ?? kTrackChunkPoints,
  );

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
}

/// Lỗi mạng như Firestore `unavailable` sau [mapFirebaseError].
ApiException offlineError() => ApiException(0, 'network', 'unavailable');
