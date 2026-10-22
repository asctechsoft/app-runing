import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';
import '../../utils/logger.dart';
import 'api_client.dart';
import '../../utils/clock.dart';
import '../../repository/activity_repository.dart';
import '../../repository/owner_repository.dart';
import '../../repository/settings_repository.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/sync.dart';
import 'sync_remote.dart';
import '../../utils/l10n.dart';

enum SyncPhase { idle, syncing, error, offline, signedOut, disabled }

/// Trạng thái đồng bộ cho UI (F20). `pending` = số thao tác chưa được server xác nhận.
@immutable
class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.pending = 0, this.conflicts = 0, this.lastError, this.lastSyncedAt});

  final SyncPhase phase;
  final int pending;
  final int conflicts;
  final String? lastError;
  final int? lastSyncedAt;

  SyncStatus copyWith({SyncPhase? phase, int? pending, int? conflicts, String? lastError, bool clearError = false, int? lastSyncedAt}) => SyncStatus(
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    conflicts: conflicts ?? this.conflicts,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
}

/// Một xung đột metadata đang chờ người dùng chọn (H04). Giữ cả hai bản trong kv.
class SyncConflict {
  const SyncConflict({
    required this.entity,
    required this.entityId,
    required this.opId,
    required this.code,
    required this.local,
    required this.server,
    required this.at,
  });

  final String entity;
  final String entityId;
  final String opId;
  final String code;
  final Map<String, Object?> local;
  final Map<String, Object?>? server;
  final int at;

  String get title {
    final t = (local['title'] as String?)?.trim();
    if (entity == 'activity') return (t == null || t.isEmpty) ? 'sync_conflict_activity'.tr : t;
    if (entity == 'profile' || entity == 'settings') return 'sync_conflict_profile_settings'.tr;
    return entity;
  }

  Map<String, Object?> toJson() => {'entity': entity, 'entityId': entityId, 'opId': opId, 'code': code, 'local': local, 'server': server, 'at': at};
  factory SyncConflict.fromJson(Map<String, Object?> j) => SyncConflict(
    entity: j['entity'] as String,
    entityId: j['entityId'] as String,
    opId: j['opId'] as String,
    code: j['code'] as String? ?? 'revision_conflict',
    local: (j['local'] as Map? ?? const {}).cast<String, Object?>(),
    server: (j['server'] as Map?)?.cast<String, Object?>(),
    at: (j['at'] as num?)?.toInt() ?? 0,
  );
}

class _Offline implements Exception {}

class _AuthLost implements Exception {}

/// Engine đồng bộ outbox ↔ server (H03/H04).
///
/// - Push: pending → sending → acked/error, backoff mũ ([SyncOperation.backoffMs]); ghi Firestore theo ID document nên lặp lại là idempotent.
/// - Activity có GPS: upsert summary → ghi track theo chunk (sha256) → mới đánh dấu synced.
/// - Pull: theo cursor serverUpdatedAt (µs, bảng sync_cursor), áp tombstone — bản đã xóa không bao giờ sống lại.
/// - Xung đột (revision lệch): giữ cả bản local và server trong kv, chờ người dùng chọn.
/// Chỉ chạy cho owner đã đăng nhập Firebase (uid == owner) khi Firebase sẵn sàng.
class SyncService {
  SyncService({
    required AppDatabase db,
    required ActivityRepository activities,
    required SettingsRepository settings,
    required SyncRemote remote,
    required String? Function() uid,
    bool Function()? ready,
    required Clock clock,
    required OwnerState Function() owner,
    this.enabled = true,
    Stream<bool>? online,
    this.debounce = const Duration(seconds: 3),
    this.chunkPoints = kTrackChunkPoints,
  }) : _db = db,
       _activities = activities,
       _settings = settings,
       _remote = remote,
       _uid = uid,
       _ready = ready ?? (() => true),
       _clock = clock,
       _owner = owner,
       _online = online;

  final AppDatabase _db;
  final ActivityRepository _activities;
  final SettingsRepository _settings;
  final SyncRemote _remote;
  final String? Function() _uid;
  final bool Function() _ready;
  final Clock _clock;
  final OwnerState Function() _owner;
  final Stream<bool>? _online;
  final bool enabled;
  final Duration debounce;
  final int chunkPoints;

  Database get _raw => _db.db;

  final status = ValueNotifier<SyncStatus>(const SyncStatus());
  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusChanges => _statusCtrl.stream;

  StreamSubscription<String>? _changesSub;
  StreamSubscription<bool>? _onlineSub;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Future<SyncStatus>? _running;
  StreamSubscription<String>? _settingsSub;
  bool _again = false;
  bool _started = false;
  bool _disposed = false;

  static const _supported = {'activity', 'goal', 'profile', 'settings'};
  static const _farFuture = 8640000000000000;
  static const conflictMarker = 'conflict';

  // ---------------- Vòng đời ----------------

  /// Bật trigger: mở app, có mạng lại, repository đổi (debounce). Gọi lặp an toàn.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _changesSub = _activities.changes.listen((_) => requestSync());
    // Cài đặt sửa ở máy (dirty = 1) → đẩy profile; bản lấy từ server lưu với dirty = 0 nên không lặp.
    _settingsSub = _settings.changes.listen((owner) => unawaited(_enqueueDirtySettings(owner)));
    _onlineSub = _online?.listen((isOnline) {
      if (isOnline) unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  Future<void> _enqueueDirtySettings(String owner) async {
    if (owner.startsWith('guest:')) return;
    final r = await _raw.query('settings', columns: ['dirty'], where: 'owner_id = ?', whereArgs: [owner]);
    if (r.isEmpty || r.first['dirty'] != 1) return;
    await enqueueProfile(await _settings.load(owner));
    await _raw.update('settings', {'dirty': 0}, where: 'owner_id = ?', whereArgs: [owner]);
  }

  void stop() {
    _started = false;
    _changesSub?.cancel();
    _settingsSub?.cancel();
    _onlineSub?.cancel();
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _changesSub = null;
    _onlineSub = null;
  }

  void dispose() {
    stop();
    _disposed = true;
    _statusCtrl.close();
    status.dispose();
  }

  /// Gộp nhiều thay đổi liên tiếp thành một lần sync.
  void requestSync() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  void _emit(SyncStatus s) {
    if (_disposed) return;
    status.value = s;
    _statusCtrl.add(s);
  }

  // ---------------- Đếm / trạng thái ----------------

  Future<int> pendingCount(String ownerId) async {
    final r = await _raw.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_outbox WHERE owner_id = ? AND state != 'acked' AND entity IN (${_supported.map((_) => '?').join(',')})",
      [ownerId, ..._supported],
    );
    return r.first['c'] as int;
  }

  Future<List<SyncConflict>> conflicts([String? ownerId]) async {
    final owner = ownerId ?? _owner().ownerId;
    final rows = await _raw.query('kv', where: "owner_id = ? AND key LIKE 'sync.conflict.%'", whereArgs: [owner]);
    final out = <SyncConflict>[];
    for (final r in rows) {
      final v = r['value'] as String?;
      if (v == null) continue;
      try {
        out.add(SyncConflict.fromJson((jsonDecode(v) as Map).cast<String, Object?>()));
      } catch (_) {}
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Làm mới số pending/conflict mà không chạy sync (gọi sau khi màn hình thay đổi dữ liệu).
  Future<SyncStatus> refreshStatus() async {
    final o = _owner();
    final s = status.value.copyWith(pending: await pendingCount(o.ownerId), conflicts: (await conflicts(o.ownerId)).length);
    _emit(s);
    return s;
  }

  // ---------------- Chạy sync ----------------

  /// Chạy một vòng push + pull. [manual] = người dùng bấm Retry: bỏ qua lịch backoff (trừ xung đột).
  Future<SyncStatus> syncNow({bool manual = false}) {
    if (_disposed) return Future.value(status.value);
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final f = _runLoop(manual);
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  Future<SyncStatus> _runLoop(bool manual) async {
    var s = await _runOnce(manual);
    while (_again && !_disposed) {
      _again = false;
      s = await _runOnce(false);
    }
    _scheduleRetry();
    return s;
  }

  Future<SyncStatus> _runOnce(bool manual) async {
    final o = _owner();
    final pending = await pendingCount(o.ownerId);
    final nConflicts = (await conflicts(o.ownerId)).length;
    var s = status.value.copyWith(pending: pending, conflicts: nConflicts);
    if (!enabled) {
      _emit(s.copyWith(phase: SyncPhase.disabled));
      return status.value;
    }
    final uid = _ready() ? _uid() : null;
    if (o.isGuest || uid == null || uid != o.ownerId) {
      _emit(s.copyWith(phase: SyncPhase.signedOut, clearError: true));
      return status.value;
    }
    _emit(s.copyWith(phase: SyncPhase.syncing));
    var errors = 0;
    String? lastError;
    try {
      await _resetStuck(o.ownerId);
      final res = await _pushAll(o.ownerId, manual);
      errors = res.$1;
      lastError = res.$2;
      await _pullAll(o.ownerId);
      s = status.value.copyWith(
        phase: errors > 0 ? SyncPhase.error : SyncPhase.idle,
        lastError: lastError,
        clearError: errors == 0,
        lastSyncedAt: errors == 0 ? _clock.nowMs() : null,
      );
    } on _Offline {
      s = status.value.copyWith(phase: SyncPhase.offline, lastError: 'sync_offline'.tr);
    } on _AuthLost {
      s = status.value.copyWith(phase: SyncPhase.signedOut, lastError: 'sync_session_expired'.tr);
    } on ApiException catch (e) {
      // Lỗi ở bước pull (push đã xử lý lỗi theo từng op).
      if (e.isNetwork) {
        s = status.value.copyWith(phase: SyncPhase.offline, lastError: 'sync_offline'.tr);
      } else if (e.isUnauthorized) {
        s = status.value.copyWith(phase: SyncPhase.signedOut, lastError: 'sync_session_expired'.tr);
      } else {
        s = status.value.copyWith(phase: SyncPhase.error, lastError: lastError ?? 'sync_download_failed'.tr);
      }
    } catch (e, st) {
      StrideLog.e('sync', e, st);
      s = status.value.copyWith(phase: SyncPhase.error, lastError: 'sync_failed_later'.tr);
    }
    _emit(s.copyWith(pending: await pendingCount(o.ownerId), conflicts: (await conflicts(o.ownerId)).length));
    return status.value;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!_started || _disposed) return;
    final o = _owner();
    if (o.isGuest) return;
    unawaited(() async {
      final r = await _raw.rawQuery(
        "SELECT MIN(next_attempt_at) AS n FROM sync_outbox WHERE owner_id = ? AND state IN ('pending','error') AND (last_error IS NULL OR last_error != ?)",
        [o.ownerId, conflictMarker],
      );
      final next = r.first['n'] as int?;
      if (next == null || next >= _farFuture || _disposed || !_started) return;
      final wait = Duration(milliseconds: (next - _clock.nowMs()).clamp(1000, 30 * 60 * 1000));
      _retryTimer = Timer(wait, () => unawaited(syncNow()));
    }());
  }

  /// Thao tác kẹt ở `sending` (app bị kill giữa chừng) quay về pending; gửi lại an toàn vì ghi theo ID document + kiểm revision.
  Future<void> _resetStuck(String owner) =>
      _raw.update('sync_outbox', {'state': SyncOpState.pending.name}, where: "owner_id = ? AND state = 'sending'", whereArgs: [owner]);

  // ---------------- Push ----------------

  Future<(int, String?)> _pushAll(String owner, bool manual) async {
    final now = _clock.nowMs();
    final rows = await _raw.query(
      'sync_outbox',
      where:
          "owner_id = ? AND state IN ('pending','error') AND (last_error IS NULL OR last_error != ?) AND entity IN (${_supported.map((_) => '?').join(',')})${manual ? '' : ' AND next_attempt_at <= ?'}",
      whereArgs: [owner, conflictMarker, ..._supported, if (!manual) now],
      orderBy: 'created_at, id',
    );
    var errors = 0;
    String? lastError;
    for (final row in rows) {
      final op = SyncOperation.fromRow(row);
      final err = await _process(op);
      if (err != null) {
        errors++;
        lastError = err;
      }
    }
    return (errors, lastError);
  }

  Future<void> _setOp(String id, Map<String, Object?> values) => _raw.update('sync_outbox', values, where: 'id = ?', whereArgs: [id]);

  Future<void> _ack(SyncOperation op) => _setOp(op.id, {'state': SyncOpState.acked.name, 'last_error': null, 'next_attempt_at': 0});

  Future<void> _fail(SyncOperation op, String message, {bool permanent = false}) {
    final attempts = op.attempts + 1;
    final backoff = permanent ? SyncOperation.backoffMs(20) : SyncOperation.backoffMs(attempts);
    return _setOp(op.id, {'state': SyncOpState.error.name, 'attempts': attempts, 'next_attempt_at': _clock.nowMs() + backoff, 'last_error': message});
  }

  /// Xử lý một thao tác; trả thông báo lỗi (null = thành công/không cần báo).
  Future<String?> _process(SyncOperation op) async {
    await _setOp(op.id, {'state': SyncOpState.sending.name});
    try {
      switch (op.entity) {
        case 'activity':
          return await _pushActivity(op);
        case 'goal':
          return await _pushGoal(op);
        default:
          return await _pushProfile(op);
      }
    } on ApiException catch (e) {
      if (e.isNetwork) {
        await _fail(op, 'offline');
        throw _Offline();
      }
      if (e.isUnauthorized) {
        await _setOp(op.id, {'state': SyncOpState.pending.name});
        throw _AuthLost();
      }
      final transient = e.status >= 500 || e.status == 429;
      await _fail(op, e.code, permanent: !transient);
      return transient ? 'sync_server_unreachable'.tr : 'sync_changes_failed'.trArgs([e.code]);
    }
  }

  // kv theo owner
  Future<String?> _kvGet(String owner, String key) => _settings.kvGet(owner, key);
  Future<void> _kvSet(String owner, String key, String value) => _settings.kvSet(owner, key, value);
  Future<void> _kvDel(String owner, String key) => _raw.delete('kv', where: 'owner_id = ? AND key = ?', whereArgs: [owner, key]);

  static String revKey(String entity, String id) => 'sync.rev.$entity.$id';
  static String conflictKey(String entity, String id) => 'sync.conflict.$entity.$id';
  static String trackKey(String id) => 'sync.track.$id';
  static String _expKey(String opId) => 'sync.opexp.$opId';

  /// expectedRevision chốt ở lần gửi đầu và tái dùng khi retry — nếu lần trước đã ghi nhưng mất phản hồi, remote nhận ra ghi lặp (revision = expected + 1, nội dung giống) và ack.
  Future<int?> _expectedRevision(SyncOperation op, String revEntity, String entityId, {Future<int?> Function()? fetch}) async {
    final saved = await _kvGet(op.ownerId, _expKey(op.id));
    if (saved != null) return saved == 'none' ? null : int.tryParse(saved);
    var rev = int.tryParse(await _kvGet(op.ownerId, revKey(revEntity, entityId)) ?? '');
    if (rev == null && fetch != null) rev = await fetch();
    await _kvSet(op.ownerId, _expKey(op.id), rev?.toString() ?? 'none');
    return rev;
  }

  Future<bool> _hasOtherOpenOps(SyncOperation op) async {
    final r = await _raw.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_outbox WHERE owner_id = ? AND entity = ? AND entity_id = ? AND id != ? AND state != 'acked'",
      [op.ownerId, op.entity, op.entityId, op.id],
    );
    return (r.first['c'] as int) > 0;
  }

  Future<String?> _pushActivity(SyncOperation op) async {
    final isDelete = op.op == SyncOpType.delete;
    final expected = await _expectedRevision(op, 'activity', op.entityId);
    final result = await _remote.pushActivity(
      op.ownerId,
      op.entityId,
      expectedRevision: expected,
      body: isDelete ? null : activityBodyForServer(op.payload),
      nowMs: _clock.nowMs(),
    );
    if (result.status == PushStatus.acked) {
      final rev = result.revision;
      if (rev != null) await _kvSet(op.ownerId, revKey('activity', op.entityId), '$rev');
      if (!isDelete && op.payload['hasGps'] == true) {
        // Track phải lên đủ trước khi coi activity là synced.
        await _uploadTrack(op.ownerId, op.entityId);
      }
      await _ack(op);
      await _kvDel(op.ownerId, _expKey(op.id));
      if (!await _hasOtherOpenOps(op)) {
        await _raw.update('activities', {'sync_state': SyncState.synced.name}, where: 'id = ? AND owner_id = ?', whereArgs: [op.entityId, op.ownerId]);
      }
      return null;
    }
    final code = result.code ?? 'error';
    if (result.status == PushStatus.conflict) {
      await _handleConflict(op, code, result.server);
      return null;
    }
    // rejected
    if (isDelete && code == 'not_found') {
      // Chưa từng lên server → xóa local là đủ.
      await _ack(op);
      await _raw.update('activities', {'sync_state': SyncState.synced.name}, where: 'id = ? AND owner_id = ?', whereArgs: [op.entityId, op.ownerId]);
      return null;
    }
    await _fail(op, code, permanent: true);
    await _raw.update('activities', {'sync_state': SyncState.error.name}, where: 'id = ? AND owner_id = ?', whereArgs: [op.entityId, op.ownerId]);
    return 'sync_activity_failed'.trArgs([code]);
  }

  Future<String?> _pushGoal(SyncOperation op) async {
    final p = op.payload;
    await _remote.putGoal(op.ownerId, op.entityId, {
      'type': p['type'],
      'value': p['value'],
      'effectiveFrom': p['effectiveFrom'],
      'createdAt': (p['createdAt'] as num?)?.toInt() ?? _clock.nowMs(),
    });
    await _ack(op);
    return null;
  }

  Future<String?> _pushProfile(SyncOperation op) async {
    final userId = op.ownerId;
    final expected = await _expectedRevision(op, 'profile', userId, fetch: () => _remote.profileRevision(userId));
    final result = await _remote.pushProfile(userId, expectedRevision: expected, profile: op.payload, nowMs: _clock.nowMs());
    if (result.status == PushStatus.acked) {
      final rev = result.revision;
      if (rev != null) await _kvSet(op.ownerId, revKey('profile', userId), '$rev');
      await _ack(op);
      await _kvDel(op.ownerId, _expKey(op.id));
      return null;
    }
    final code = result.code ?? 'error';
    if (result.status == PushStatus.conflict) {
      await _handleConflict(op, code, result.server);
      return null;
    }
    await _fail(op, code, permanent: true);
    return 'sync_profile_failed'.trArgs([code]);
  }

  Future<void> _handleConflict(SyncOperation op, String code, Map<String, Object?>? server) async {
    if (op.entity == 'activity' && (code == 'activity_deleted' || server?['deletedAt'] != null)) {
      // Server đã xóa: tombstone thắng, không hồi sinh bản local.
      final deletedAt = (server?['deletedAt'] as num?)?.toInt() ?? _clock.nowMs();
      await _applyActivityTombstone(op.ownerId, op.entityId, deletedAt);
      await _ack(op);
      return;
    }
    final c = SyncConflict(
      entity: op.entity == 'settings' ? 'profile' : op.entity,
      entityId: op.entityId,
      opId: op.id,
      code: code,
      local: op.payload,
      server: server,
      at: _clock.nowMs(),
    );
    await _kvSet(op.ownerId, conflictKey(c.entity, op.entityId), jsonEncode(c.toJson()));
    await _setOp(op.id, {'state': SyncOpState.error.name, 'last_error': conflictMarker, 'next_attempt_at': _farFuture});
    if (op.entity == 'activity') {
      await _raw.update('activities', {'sync_state': SyncState.error.name}, where: 'id = ? AND owner_id = ?', whereArgs: [op.entityId, op.ownerId]);
    }
  }

  // ---------------- Track (H02) ----------------

  Future<void> _uploadTrack(String owner, String activityId) async {
    if (await _kvGet(owner, trackKey(activityId)) == 'done') return;
    final points = await _activities.points(activityId);
    final segments = await _activities.segments(activityId);
    if (points.isEmpty) {
      // Không có điểm GPS nào: không bịa tuyến.
      await _kvSet(owner, trackKey(activityId), 'done');
      return;
    }
    final docs = trackChunkDocs(buildTrackChunks(segments, points, chunkPoints));
    for (var i = 0; i < docs.length; i++) {
      await _remote.putTrackChunk(owner, activityId, i, docs[i]);
    }
    await _kvSet(owner, trackKey(activityId), 'done');
  }

  // ---------------- Pull ----------------

  static const _goalCursorKey = 'sync.cursor.goals';
  static const _pullPageSize = 200;

  Future<void> _pullAll(String owner) async {
    final r = await _raw.query('sync_cursor', where: 'owner_id = ?', whereArgs: [owner]);
    int? cursor = r.isEmpty ? null : int.tryParse((r.first['cursor'] as String?) ?? '');
    var changed = false;
    final needTrack = <String>[];
    for (var page = 0; page < 50; page++) {
      final res = await _remote.pullActivities(owner, afterUs: cursor, limit: _pullPageSize);
      for (final it in res.items) {
        final applied = await _applyItem(owner, it, needTrack);
        changed = changed || applied;
      }
      final next = res.nextCursorUs;
      if (next != null && next != cursor) {
        cursor = next;
        await _raw.insert('sync_cursor', {
          'owner_id': owner,
          'cursor': '$cursor',
          'last_pulled_at': _clock.nowMs(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (!res.hasMore) break;
    }
    await _pullGoals(owner);
    await _pullProfile(owner);
    for (final id in needTrack) {
      try {
        await _downloadTrack(owner, id);
      } catch (_) {
        // Best-effort: thiếu track thì màn bản đồ hiển thị trạng thái không có tuyến, không bịa.
      }
    }
    if (changed) _activities.notifyChanged(owner);
  }

  Future<void> _pullGoals(String owner) async {
    var cursor = int.tryParse(await _kvGet(owner, _goalCursorKey) ?? '');
    for (var page = 0; page < 20; page++) {
      final goals = await _remote.pullGoals(owner, afterCreatedAt: cursor, limit: _pullPageSize);
      var maxCreated = cursor;
      for (final g in goals) {
        final id = g['id'] as String?;
        if (id == null) continue;
        await _applyItem(owner, {'entity': 'goal', 'entityId': id, 'op': 'upsert', 'data': g}, []);
        final c = (g['createdAt'] as num?)?.toInt();
        if (c != null && (maxCreated == null || c > maxCreated)) maxCreated = c;
      }
      if (maxCreated != null && maxCreated != cursor) {
        cursor = maxCreated;
        await _kvSet(owner, _goalCursorKey, '$cursor');
      }
      if (goals.length < _pullPageSize) break;
    }
  }

  Future<void> _pullProfile(String owner) async {
    final doc = await _remote.getUserDoc(owner);
    final profile = (doc?['profile'] as Map?)?.cast<String, Object?>();
    if (profile == null) return;
    final rev = (doc?['profileRevision'] as num?)?.toInt();
    if (rev != null && await _kvGet(owner, revKey('profile', owner)) == '$rev') return; // đã áp
    await _applyItem(owner, {'entity': 'profile', 'entityId': owner, 'op': 'upsert', 'revision': rev, 'data': profile}, []);
  }

  Future<bool> _openOps(String owner, String entity, String id) async {
    final r = await _raw.rawQuery("SELECT COUNT(*) AS c FROM sync_outbox WHERE owner_id = ? AND entity = ? AND entity_id = ? AND state != 'acked'", [
      owner,
      entity,
      id,
    ]);
    return (r.first['c'] as int) > 0;
  }

  Future<bool> _applyItem(String owner, Map<String, Object?> it, List<String> needTrack) async {
    final entity = it['entity'] as String?;
    final id = it['entityId'] as String?;
    final data = (it['data'] as Map?)?.cast<String, Object?>();
    final rev = (it['revision'] as num?)?.toInt();
    if (entity == null || id == null) return false;
    switch (entity) {
      case 'activity':
        final local = await _raw.query('activities', columns: ['owner_id', 'deleted_at', 'has_gps'], where: 'id = ?', whereArgs: [id]);
        if (local.isNotEmpty && local.first['owner_id'] != owner) return false; // không bao giờ chạm dữ liệu owner khác
        if (it['op'] == 'delete') {
          final deletedAt = (data?['deletedAt'] as num?)?.toInt() ?? _clock.nowMs();
          await _applyActivityTombstone(owner, id, deletedAt);
          // Thao tác local còn treo cho bản đã xóa sẽ không được đẩy lên nữa.
          await _raw.delete('sync_outbox', where: "owner_id = ? AND entity = 'activity' AND entity_id = ? AND state != 'acked'", whereArgs: [owner, id]);
          await _kvDel(owner, conflictKey('activity', id));
          if (rev != null) await _kvSet(owner, revKey('activity', id), '$rev');
          return local.isNotEmpty;
        }
        if (data == null) return false;
        if (local.isNotEmpty && local.first['deleted_at'] != null) return false; // tombstone local thắng
        if (await _openOps(owner, 'activity', id)) return false; // sửa local chưa đẩy: push sẽ phát hiện xung đột
        final a = Activity.fromJson(data, ownerId: owner).copyWith(syncState: SyncState.synced);
        final row = a.toRow();
        if (local.isEmpty) {
          await _raw.insert('activities', row);
          if (a.hasGps) needTrack.add(id);
        } else {
          // UPDATE thay vì REPLACE: REPLACE sẽ xóa dòng cũ và cascade mất track_points.
          row.remove('id');
          await _raw.update('activities', row, where: 'id = ? AND owner_id = ?', whereArgs: [id, owner]);
        }
        if (rev != null) await _kvSet(owner, revKey('activity', id), '$rev');
        return true;
      case 'goal':
        if (data == null) return false;
        await _raw.insert('goal_versions', {
          'id': id,
          'owner_id': owner,
          'type': data['type'],
          'value': (data['value'] as num?)?.toDouble() ?? 0,
          'effective_from': data['effectiveFrom'],
          'created_at': (data['createdAt'] as num?)?.toInt() ?? _clock.nowMs(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return false;
      case 'profile':
        if (data == null) return false;
        if (await _openOps(owner, 'profile', owner) || await _openOps(owner, 'settings', owner)) return false;
        final current = await _settings.load(owner);
        await _settings.save(settingsFromServerProfile(current, data), markDirty: false);
        if (rev != null) await _kvSet(owner, revKey('profile', owner), '$rev');
        return false;
    }
    return false;
  }

  Future<void> _applyActivityTombstone(String owner, String id, int deletedAt) async {
    await _raw.rawUpdate('UPDATE activities SET deleted_at = COALESCE(deleted_at, ?), sync_state = ?, updated_at = ? WHERE id = ? AND owner_id = ?', [
      deletedAt,
      SyncState.synced.name,
      _clock.nowMs(),
      id,
      owner,
    ]);
  }

  Future<void> _downloadTrack(String owner, String activityId) async {
    if ((await _activities.points(activityId)).isNotEmpty) return;
    final docs = await _remote.getTrackChunks(owner, activityId);
    if (docs.isEmpty) return;
    final (segments, points) = parseTrackChunks(activityId, docs);
    final batch = _raw.batch();
    for (final s in segments) {
      batch.insert('track_segments', s.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    await _activities.insertPoints(points);
  }

  // ---------------- Giải quyết xung đột (H04) ----------------

  /// Giữ bản trên máy này: đẩy lại với revision của server (key mới để không trùng request cũ).
  Future<void> resolveKeepLocal(SyncConflict c) async {
    final owner = _owner().ownerId;
    final serverRev = (c.server?['revision'] as num?)?.toInt();
    final rows = await _raw.query('sync_outbox', where: 'id = ? AND owner_id = ?', whereArgs: [c.opId, owner]);
    if (rows.isNotEmpty) {
      final op = SyncOperation.fromRow(rows.first);
      final suffix = ':r${serverRev ?? 'x'}';
      var key = op.idempotencyKey.endsWith(suffix) ? op.idempotencyKey : '${op.idempotencyKey}$suffix';
      if (key.length > 128) key = key.substring(key.length - 128);
      await _setOp(op.id, {'state': SyncOpState.pending.name, 'attempts': 0, 'next_attempt_at': 0, 'last_error': null, 'idempotency_key': key});
      await _kvDel(owner, _expKey(op.id));
    }
    final revEntity = c.entity == 'activity' ? 'activity' : 'profile';
    if (serverRev != null) await _kvSet(owner, revKey(revEntity, c.entityId), '$serverRev');
    await _kvDel(owner, conflictKey(c.entity, c.entityId));
    if (c.entity == 'activity') {
      await _raw.update('activities', {'sync_state': SyncState.pending.name}, where: 'id = ? AND owner_id = ?', whereArgs: [c.entityId, owner]);
      _activities.notifyChanged(owner);
    }
    unawaited(syncNow());
  }

  /// Dùng bản từ server: áp vào local, bỏ thao tác đang treo.
  Future<void> resolveKeepServer(SyncConflict c) async {
    final owner = _owner().ownerId;
    final server = c.server;
    if (server != null) {
      if (c.entity == 'activity') {
        final row = Activity.fromJson({...server, 'id': c.entityId}, ownerId: owner).copyWith(syncState: SyncState.synced).toRow()..remove('id');
        await _raw.update('activities', row, where: 'id = ? AND owner_id = ?', whereArgs: [c.entityId, owner]);
      } else {
        final current = await _settings.load(owner);
        await _settings.save(settingsFromServerProfile(current, server), markDirty: false);
      }
      final rev = (server['revision'] as num?)?.toInt();
      if (rev != null) await _kvSet(owner, revKey(c.entity == 'activity' ? 'activity' : 'profile', c.entityId), '$rev');
    }
    await _raw.update('sync_outbox', {'state': SyncOpState.acked.name, 'last_error': null}, where: 'id = ? AND owner_id = ?', whereArgs: [c.opId, owner]);
    await _kvDel(owner, conflictKey(c.entity, c.entityId));
    if (c.entity == 'activity') _activities.notifyChanged(owner);
    await refreshStatus();
  }

  /// Đẩy hồ sơ/cài đặt hiện tại lên server (chỉ khi đã đăng nhập; entityId = userId).
  Future<void> enqueueProfile(UserSettings s) async {
    if (s.ownerId.startsWith('guest:')) return;
    await _activities.enqueue(s.ownerId, 'profile', s.ownerId, SyncOpType.upsert, profilePayloadForServer(s), revision: _clock.nowMs());
    requestSync();
  }

  /// Đưa phiên bản mục tiêu vào outbox (append-only, id ổn định nên retry không nhân đôi).
  Future<void> enqueueGoal(GoalVersion g) async {
    await _activities.enqueue(g.ownerId, 'goal', g.id, SyncOpType.upsert, g.toJson(), revision: 1);
    if (!g.ownerId.startsWith('guest:')) requestSync();
  }
}

// ---------------- Ánh xạ payload client ↔ server ----------------

const _activityKeys = [
  'type',
  'status',
  'startedAt',
  'endedAt',
  'tzId',
  'tzOffsetMin',
  'distanceM',
  'movingMs',
  'elapsedMs',
  'avgPaceSecPerKm',
  'steps',
  'caloriesKcal',
  'calorieModel',
  'weightKgUsed',
  'title',
  'feeling',
  'notes',
  'privacy',
  'goal',
  'hasGps',
  'distanceSource',
  'workoutExecutionId',
];

/// Body `activity` theo validators/activity.ts. Tiêu đề rỗng → nhãn theo loại (server yêu cầu title ≥ 1 ký tự).
Map<String, Object?> activityBodyForServer(Map<String, Object?> p) {
  final m = <String, Object?>{
    for (final k in _activityKeys)
      if (p.containsKey(k)) k: p[k],
  };
  final title = (m['title'] as String?)?.trim() ?? '';
  if (title.isEmpty) {
    m['title'] = switch (m['type']) {
      'walk' => 'Walk',
      'indoorRun' => 'Indoor run',
      _ => 'Run',
    };
  }
  final goal = m['goal'];
  if (goal is Map && goal['type'] == 'free') m['goal'] = {'type': 'free', 'value': null};
  return m;
}

/// Payload profile theo validators/me.ts (activityLevel `newbie` ↔ `new`).
Map<String, Object?> profilePayloadForServer(UserSettings s) => {
  'displayName': s.displayName.trim().isEmpty ? null : s.displayName.trim(),
  'heightCm': s.heightCm,
  'weightKg': s.weightKg,
  'activityLevel': switch (s.activityLevel) {
    null => null,
    ActivityLevel.newbie => 'new',
    final l => l.name,
  },
  'distanceUnit': s.distanceUnit.name,
  'weightUnit': s.weightUnit.name,
  'heightUnit': s.heightUnit.name,
  'weekStart': s.weekStart,
  'locale': s.localeTag,
  'autoPause': s.autoPause,
};

UserSettings settingsFromServerProfile(UserSettings current, Map<String, Object?> p) {
  T byName<T extends Enum>(List<T> values, Object? name, T fallback) => values.firstWhere((v) => v.name == name, orElse: () => fallback);
  final level = p['activityLevel'];
  return current.copyWith(
    displayName: p['displayName'] as String? ?? current.displayName,
    heightCm: (p['heightCm'] as num?)?.toDouble(),
    clearHeight: p.containsKey('heightCm') && p['heightCm'] == null,
    weightKg: (p['weightKg'] as num?)?.toDouble(),
    clearWeight: p.containsKey('weightKg') && p['weightKg'] == null,
    activityLevel: level == null ? null : (level == 'new' ? ActivityLevel.newbie : byName(ActivityLevel.values, level, ActivityLevel.regular)),
    distanceUnit: byName(DistanceUnit.values, p['distanceUnit'], current.distanceUnit),
    weightUnit: byName(WeightUnit.values, p['weightUnit'], current.weightUnit),
    heightUnit: byName(HeightUnit.values, p['heightUnit'], current.heightUnit),
    weekStart: (p['weekStart'] as num?)?.toInt(),
    localeTag: p['locale'] as String?,
    autoPause: p['autoPause'] as bool?,
  );
}

/// Chia track thành chunk tất định (cùng dữ liệu → cùng bytes → cùng sha256 khi retry).
/// Chunk 0 khai báo mọi segment; chunk sau khai báo lại segment mà điểm của nó tham chiếu.
List<Map<String, Object?>> buildTrackChunks(List<TrackSegment> segments, List<TrackPoint> points, int perChunk) {
  Map<String, Object?> seg(TrackSegment s) => {'id': s.id, 'seq': s.seq, 'startedAt': s.startedAt, 'endedAt': s.endedAt, 'reason': s.reason.name};
  Map<String, Object?> pt(TrackPoint p) => {
    'segmentId': p.segmentId,
    'seq': p.seq,
    't': p.t,
    'lat': p.lat,
    'lon': p.lon,
    'accuracyM': (p.accuracyM == null || p.accuracyM! < 0 || p.accuracyM! > 10000) ? null : p.accuracyM,
    'altitudeM': (p.altitudeM == null || p.altitudeM! < -1000 || p.altitudeM! > 10000) ? null : p.altitudeM,
    'speedMps': (p.speedMps == null || p.speedMps! < 0 || p.speedMps! > 200) ? null : p.speedMps,
    'accepted': p.accepted,
    'rejectReason': p.rejectReason,
  };
  final byId = {for (final s in segments) s.id: s};
  final sorted = [...points]..sort((a, b) => a.seq.compareTo(b.seq));
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < sorted.length; i += perChunk) {
    final slice = sorted.sublist(i, (i + perChunk).clamp(0, sorted.length));
    final segIds = i == 0 ? segments.map((s) => s.id).toList() : <String>[];
    for (final p in slice) {
      if (!segIds.contains(p.segmentId) && byId.containsKey(p.segmentId)) segIds.add(p.segmentId);
    }
    out.add({
      'segments': [for (final id in segIds) seg(byId[id]!)],
      'points': slice.map(pt).toList(),
    });
  }
  return out;
}
