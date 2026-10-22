import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../services/storage/app_database.dart';
import '../utils/clock.dart';
import '../models/data_models/activity.dart';
import '../models/data_models/sync.dart';

/// Bộ lọc danh sách hoạt động (I01).
class ActivityQuery {
  const ActivityQuery({required this.ownerId, this.types, this.fromMs, this.toMs, this.limit = 30, this.beforeStartedAt, this.beforeId});

  final String ownerId;
  final Set<ActivityType>? types;

  /// [fromMs, toMs) theo startedAt UTC.
  final int? fromMs;
  final int? toMs;
  final int limit;

  /// Keyset pagination: lấy các bản ghi trước (startedAt, id) này.
  final int? beforeStartedAt;
  final String? beforeId;
}

class ActivityTotals {
  const ActivityTotals({required this.count, required this.distanceM, required this.movingMs, required this.gpsDistanceM, required this.gpsMovingMs});
  final int count;
  final double distanceM;
  final int movingMs;

  /// Chỉ tính hoạt động có distance GPS — dùng cho pace tổng kỳ (Full_luong §11).
  final double gpsDistanceM;
  final int gpsMovingMs;
}

/// Lưu trữ hoạt động, track, event, checkpoint, ảnh và outbox (C03, G03, G08, G10, I03).
/// Mọi truy vấn đều scope theo owner_id.
class ActivityRepository {
  ActivityRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final _uuid = const Uuid();
  final _changes = StreamController<String>.broadcast();

  /// Phát ownerId mỗi khi hoạt động của owner thay đổi (save/edit/delete/sync).
  Stream<String> get changes => _changes.stream;

  void notifyChanged(String ownerId) => _changes.add(ownerId);

  Database get raw => _db.db;

  // ---------------- Phiên đang ghi ----------------

  /// Phiên chưa chốt của owner (recording/paused/awaitingSave/recoveryNeeded). Tối đa một (C05).
  Future<Activity?> openSession(String ownerId) async {
    final rows = await _db.db.query(
      'activities',
      where: "owner_id = ? AND status IN ('recording','paused','awaitingSave','recoveryNeeded') AND deleted_at IS NULL",
      whereArgs: [ownerId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Activity.fromRow(rows.first);
  }

  /// Tạo draft + event start + segment đầu trong một transaction. Ném [StateError] nếu đã có phiên mở.
  Future<(Activity, TrackSegment)> createSession({
    required String ownerId,
    required ActivityType type,
    required RunGoal goal,
    required int monoMs,
    required String tzId,
    required int tzOffsetMin,
  }) async {
    return _db.db.transaction((txn) async {
      final existing = await txn.query(
        'activities',
        columns: ['id'],
        where: "owner_id = ? AND status IN ('recording','paused','awaitingSave','recoveryNeeded') AND deleted_at IS NULL",
        whereArgs: [ownerId],
        limit: 1,
      );
      if (existing.isNotEmpty) throw StateError('session-already-open');
      final now = _clock.nowMs();
      final a = Activity(
        id: _uuid.v4(),
        ownerId: ownerId,
        type: type,
        status: ActivityStatus.recording,
        startedAt: now,
        tzId: tzId,
        tzOffsetMin: tzOffsetMin,
        goal: goal,
        hasGps: false,
        distanceSource: type == ActivityType.indoorRun ? DistanceSource.steps : DistanceSource.gps,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('activities', a.toRow());
      final seg = TrackSegment(id: _uuid.v4(), activityId: a.id, seq: 0, startedAt: now, reason: SegmentReason.start);
      await txn.insert('track_segments', seg.toRow());
      await txn.insert('session_events', SessionEvent(id: _uuid.v4(), activityId: a.id, seq: 0, type: SessionEventType.start, t: now, monoMs: monoMs).toRow());
      return (a, seg);
    });
  }

  Future<int> _nextEventSeq(DatabaseExecutor ex, String activityId) async {
    final r = await ex.rawQuery('SELECT COALESCE(MAX(seq), -1) + 1 AS n FROM session_events WHERE activity_id = ?', [activityId]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// Ghi event + đổi status (+ mở segment mới nếu cần) trong một transaction — lưu trước khi đổi UI (G06).
  Future<SessionEvent> appendEvent({
    required String activityId,
    required SessionEventType type,
    required int monoMs,
    ActivityStatus? newStatus,
    SegmentReason? openSegment,
    Map<String, Object?>? data,
  }) async {
    return _db.db.transaction((txn) async {
      final now = _clock.nowMs();
      final seq = await _nextEventSeq(txn, activityId);
      final e = SessionEvent(id: _uuid.v4(), activityId: activityId, seq: seq, type: type, t: now, monoMs: monoMs, data: data);
      await txn.insert('session_events', e.toRow());
      if (newStatus != null) {
        await txn.update('activities', {'status': newStatus.name, 'updated_at': now}, where: 'id = ?', whereArgs: [activityId]);
      }
      if (openSegment != null) {
        await txn.update('track_segments', {'ended_at': now}, where: 'activity_id = ? AND ended_at IS NULL', whereArgs: [activityId]);
        final r = await txn.rawQuery('SELECT COALESCE(MAX(seq), -1) + 1 AS n FROM track_segments WHERE activity_id = ?', [activityId]);
        await txn.insert(
          'track_segments',
          TrackSegment(id: _uuid.v4(), activityId: activityId, seq: r.first['n'] as int, startedAt: now, reason: openSegment).toRow(),
        );
      }
      return e;
    });
  }

  Future<TrackSegment?> currentSegment(String activityId) async {
    final r = await _db.db.query('track_segments', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'seq DESC', limit: 1);
    return r.isEmpty ? null : TrackSegment.fromRow(r.first);
  }

  /// Ghi batch điểm theo sequence (G08). Bỏ qua điểm trùng seq khi retry.
  Future<void> insertPoints(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final b = _db.db.batch();
    for (final p in points) {
      b.insert('track_points', p.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await b.commit(noResult: true);
  }

  Future<int> nextPointSeq(String activityId) async {
    final r = await _db.db.rawQuery('SELECT COALESCE(MAX(seq), -1) + 1 AS n FROM track_points WHERE activity_id = ?', [activityId]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// Checkpoint transactional: cập nhật tổng tạm thời trên activity + bảng checkpoint (G08).
  Future<void> checkpoint({
    required String activityId,
    required String phase,
    required int movingMs,
    required double distanceM,
    int? steps,
    bool? hasGps,
    int? lastPointSeq,
    int? lastEventSeq,
    String? extraJson,
  }) async {
    await _db.db.transaction((txn) async {
      final now = _clock.nowMs();
      await txn.insert('session_checkpoints', {
        'activity_id': activityId,
        'saved_at': now,
        'moving_ms': movingMs,
        'distance_m': distanceM,
        'last_point_seq': lastPointSeq,
        'last_event_seq': lastEventSeq,
        'phase': phase,
        'extra_json': extraJson,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        'activities',
        {'moving_ms': movingMs, 'distance_m': distanceM, 'steps': ?steps, 'has_gps': ?(hasGps == null ? null : (hasGps ? 1 : 0)), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [activityId],
      );
    });
  }

  Future<Map<String, Object?>?> loadCheckpoint(String activityId) async {
    final r = await _db.db.query('session_checkpoints', where: 'activity_id = ?', whereArgs: [activityId]);
    return r.isEmpty ? null : r.first;
  }

  /// Đánh dấu phiên chưa đóng thành recoveryNeeded khi mở app (G08).
  Future<Activity?> detectUnclosedSession(String ownerId) async {
    final a = await openSession(ownerId);
    if (a == null) return null;
    if (a.status == ActivityStatus.recording || a.status == ActivityStatus.paused) {
      await _db.db.update('activities', {'status': ActivityStatus.recoveryNeeded.name, 'updated_at': _clock.nowMs()}, where: 'id = ?', whereArgs: [a.id]);
      return a.copyWith(status: ActivityStatus.recoveryNeeded);
    }
    return a;
  }

  // ---------------- Lưu / bỏ ----------------

  /// Chốt summary khi Finish (awaitingSave). Không thu thập thêm sau bước này.
  Future<Activity> finalizeSummary(Activity summary) async {
    await _db.db.update('activities', {...summary.toRow(), 'status': ActivityStatus.awaitingSave.name}, where: 'id = ?', whereArgs: [summary.id]);
    return summary.copyWith(status: ActivityStatus.awaitingSave);
  }

  /// Save: activity + outbox trong một transaction (G10). Gọi lặp với cùng id không tạo bản thứ hai.
  Future<Activity> saveActivity(Activity a, {bool enqueueSync = true}) async {
    final saved = await _db.db.transaction((txn) async {
      final now = _clock.nowMs();
      final next = a.copyWith(
        status: ActivityStatus.saved,
        syncState: enqueueSync ? SyncState.pending : SyncState.local,
        revision: a.revision + 1,
        updatedAt: now,
      );
      // Không dùng INSERT OR REPLACE: REPLACE xóa dòng cũ → CASCADE xóa track/event/ảnh.
      final n = await txn.update('activities', next.toRow(), where: 'id = ?', whereArgs: [next.id]);
      if (n == 0) await txn.insert('activities', next.toRow());
      await txn.delete('session_checkpoints', where: 'activity_id = ?', whereArgs: [a.id]);
      if (enqueueSync) await _enqueue(txn, next.ownerId, 'activity', next.id, SyncOpType.upsert, next.toJson(), revision: next.revision);
      return next;
    });
    _changes.add(saved.ownerId);
    return saved;
  }

  /// Discard: xóa bản nháp chưa lưu (khác Delete hoạt động đã lưu).
  Future<void> discardDraft(String activityId) async {
    final a = await byIdAnyOwner(activityId);
    await _db.db.delete('activities', where: "id = ? AND status != 'saved'", whereArgs: [activityId]);
    if (a != null) _changes.add(a.ownerId);
  }

  /// Sửa metadata (I03). Route/distance không đổi ở core.
  Future<Activity> updateMetadata(Activity a, {String? title, Feeling? feeling, bool clearFeeling = false, String? notes, Privacy? privacy}) async {
    final next = await _db.db.transaction((txn) async {
      final n = a.copyWith(
        title: title,
        feeling: feeling,
        clearFeeling: clearFeeling,
        notes: notes,
        privacy: privacy,
        revision: a.revision + 1,
        updatedAt: _clock.nowMs(),
        syncState: SyncState.pending,
      );
      await txn.update('activities', n.toRow(), where: 'id = ? AND owner_id = ?', whereArgs: [a.id, a.ownerId]);
      await _enqueue(txn, n.ownerId, 'activity', n.id, SyncOpType.upsert, n.toJson(), revision: n.revision);
      return n;
    });
    _changes.add(a.ownerId);
    return next;
  }

  /// Delete: tombstone local + outbox delete; ẩn khỏi mọi truy vấn (I03, F15).
  Future<void> deleteActivity(String ownerId, String activityId) async {
    await _db.db.transaction((txn) async {
      final now = _clock.nowMs();
      final n = await txn.update(
        'activities',
        {'deleted_at': now, 'updated_at': now, 'sync_state': SyncState.pending.name},
        where: 'id = ? AND owner_id = ?',
        whereArgs: [activityId, ownerId],
      );
      if (n == 0) return;
      await _enqueue(txn, ownerId, 'activity', activityId, SyncOpType.delete, {'id': activityId, 'deletedAt': now}, revision: now);
    });
    _changes.add(ownerId);
  }

  Future<void> _enqueue(
    DatabaseExecutor ex,
    String ownerId,
    String entity,
    String entityId,
    SyncOpType op,
    Map<String, Object?> payload, {
    required int revision,
  }) async {
    // Gộp: bỏ thao tác pending cũ cùng entity (thao tác mới mang trạng thái đầy đủ).
    await ex.delete(
      'sync_outbox',
      where: "owner_id = ? AND entity = ? AND entity_id = ? AND state IN ('pending','error')",
      whereArgs: [ownerId, entity, entityId],
    );
    final opId = _uuid.v4();
    final opRow = SyncOperation(
      id: opId,
      ownerId: ownerId,
      entity: entity,
      entityId: entityId,
      op: op,
      payload: payload,
      idempotencyKey: '$entity:$entityId:${op.name}:$revision:$opId',
      createdAt: _clock.nowMs(),
    );
    await ex.insert('sync_outbox', opRow.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Cho các module khác (settings, goals, attachments) đẩy thao tác vào outbox.
  Future<void> enqueue(String ownerId, String entity, String entityId, SyncOpType op, Map<String, Object?> payload, {required int revision}) =>
      _enqueue(_db.db, ownerId, entity, entityId, op, payload, revision: revision);

  // ---------------- Đọc ----------------

  Future<Activity?> byId(String ownerId, String id) async {
    final r = await _db.db.query('activities', where: 'id = ? AND owner_id = ? AND deleted_at IS NULL', whereArgs: [id, ownerId]);
    return r.isEmpty ? null : Activity.fromRow(r.first);
  }

  /// Chỉ dùng nội bộ (engine/sync) — không dùng cho UI.
  Future<Activity?> byIdAnyOwner(String id) async {
    final r = await _db.db.query('activities', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Activity.fromRow(r.first);
  }

  (String, List<Object?>) _where(ActivityQuery q) {
    final where = StringBuffer("owner_id = ? AND status = 'saved' AND deleted_at IS NULL");
    final args = <Object?>[q.ownerId];
    if (q.types != null && q.types!.isNotEmpty) {
      where.write(' AND type IN (${List.filled(q.types!.length, '?').join(',')})');
      args.addAll(q.types!.map((t) => t.name));
    }
    if (q.fromMs != null) {
      where.write(' AND started_at >= ?');
      args.add(q.fromMs);
    }
    if (q.toMs != null) {
      where.write(' AND started_at < ?');
      args.add(q.toMs);
    }
    return (where.toString(), args);
  }

  /// Danh sách đã lưu (không gồm bản nháp), keyset pagination ổn định theo (started_at DESC, id DESC).
  Future<List<Activity>> list(ActivityQuery q) async {
    var (where, args) = _where(q);
    if (q.beforeStartedAt != null && q.beforeId != null) {
      where = '$where AND (started_at < ? OR (started_at = ? AND id < ?))';
      args = [...args, q.beforeStartedAt, q.beforeStartedAt, q.beforeId];
    }
    final r = await _db.db.query('activities', where: where, whereArgs: args, orderBy: 'started_at DESC, id DESC', limit: q.limit);
    return r.map(Activity.fromRow).toList();
  }

  /// Tổng theo đúng bộ lọc (không phân trang).
  Future<ActivityTotals> totals(ActivityQuery q) async {
    final (where, args) = _where(q);
    final r = await _db.db.rawQuery('''
SELECT COUNT(*) AS c, COALESCE(SUM(distance_m),0) AS d, COALESCE(SUM(moving_ms),0) AS m,
  COALESCE(SUM(CASE WHEN has_gps = 1 AND distance_source = 'gps' THEN distance_m END),0) AS gd,
  COALESCE(SUM(CASE WHEN has_gps = 1 AND distance_source = 'gps' THEN moving_ms END),0) AS gm
FROM activities WHERE $where''', args);
    final row = r.first;
    return ActivityTotals(
      count: row['c'] as int,
      distanceM: (row['d'] as num).toDouble(),
      movingMs: (row['m'] as num).toInt(),
      gpsDistanceM: (row['gd'] as num).toDouble(),
      gpsMovingMs: (row['gm'] as num).toInt(),
    );
  }

  /// Ngày (UTC ms bắt đầu) có hoạt động trong khoảng — cho chấm lịch.
  Future<List<Activity>> allInRange(String ownerId, int fromMs, int toMs) => list(ActivityQuery(ownerId: ownerId, fromMs: fromMs, toMs: toMs, limit: 10000));

  Future<Activity?> latest(String ownerId) async {
    final l = await list(ActivityQuery(ownerId: ownerId, limit: 1));
    return l.isEmpty ? null : l.first;
  }

  Future<List<TrackPoint>> points(String activityId, {bool acceptedOnly = false}) async {
    final r = await _db.db.query(
      'track_points',
      where: acceptedOnly ? 'activity_id = ? AND accepted = 1' : 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq',
    );
    return r.map(TrackPoint.fromRow).toList();
  }

  Future<List<TrackSegment>> segments(String activityId) async {
    final r = await _db.db.query('track_segments', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'seq');
    return r.map(TrackSegment.fromRow).toList();
  }

  Future<List<SessionEvent>> events(String activityId) async {
    final r = await _db.db.query('session_events', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'seq');
    return r.map(SessionEvent.fromRow).toList();
  }

  // ---------------- Ảnh ----------------

  Future<void> addAttachment({required String activityId, required String ownerId, required String localPath, required String mime, required int bytes}) async {
    await _db.db.insert('attachments', {
      'id': _uuid.v4(),
      'activity_id': activityId,
      'owner_id': ownerId,
      'local_path': localPath,
      'mime': mime,
      'bytes': bytes,
      'upload_state': 'pending',
      'created_at': _clock.nowMs(),
    });
    _changes.add(ownerId);
  }

  Future<List<Map<String, Object?>>> attachments(String activityId) =>
      _db.db.query('attachments', where: 'activity_id = ? AND deleted_at IS NULL', whereArgs: [activityId], orderBy: 'created_at');

  Future<void> removeAttachment(String ownerId, String attachmentId) async {
    await _db.db.update('attachments', {'deleted_at': _clock.nowMs()}, where: 'id = ? AND owner_id = ?', whereArgs: [attachmentId, ownerId]);
    _changes.add(ownerId);
  }

  // ---------------- Chuyển owner (E03) ----------------

  /// Số hoạt động đã lưu của owner (để hỏi chuyển dữ liệu khách).
  Future<int> countSaved(String ownerId) async {
    final r = await _db.db.rawQuery("SELECT COUNT(*) AS c FROM activities WHERE owner_id = ? AND status = 'saved' AND deleted_at IS NULL", [ownerId]);
    return r.first['c'] as int;
  }

  /// Chuyển toàn bộ dữ liệu khách sang user trong một transaction; idempotent (chạy lại không nhân đôi).
  Future<int> transferOwnership({required String fromOwner, required String toOwner}) async {
    final moved = await _db.db.transaction((txn) async {
      final n = await txn.update(
        'activities',
        {'owner_id': toOwner, 'sync_state': SyncState.pending.name},
        where: "owner_id = ? AND status = 'saved'",
        whereArgs: [fromOwner],
      );
      await txn.update('attachments', {'owner_id': toOwner}, where: 'owner_id = ?', whereArgs: [fromOwner]);
      await txn.update('step_samples', {'owner_id': toOwner}, where: 'owner_id = ?', whereArgs: [fromOwner], conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update('goal_versions', {'owner_id': toOwner}, where: 'owner_id = ?', whereArgs: [fromOwner]);
      await txn.update('workout_plans', {'owner_id': toOwner}, where: 'owner_id = ?', whereArgs: [fromOwner]);
      // Chuyển luôn thao tác outbox của khách sang user (không để kẹt dưới owner khách).
      await txn.update('sync_outbox', {'owner_id': toOwner}, where: 'owner_id = ?', whereArgs: [fromOwner]);
      final acts = await txn.query('activities', where: "owner_id = ? AND status = 'saved' AND deleted_at IS NULL", whereArgs: [toOwner]);
      for (final row in acts) {
        final a = Activity.fromRow(row);
        final hasOp = await txn.query(
          'sync_outbox',
          columns: ['id'],
          where: "owner_id = ? AND entity = 'activity' AND entity_id = ? AND state IN ('pending','error','sending')",
          whereArgs: [toOwner, a.id],
          limit: 1,
        );
        if (a.syncState == SyncState.pending && hasOp.isEmpty) {
          await _enqueue(txn, toOwner, 'activity', a.id, SyncOpType.upsert, a.toJson(), revision: a.revision);
        }
      }
      return n;
    });
    _changes.add(toOwner);
    return moved;
  }
}
