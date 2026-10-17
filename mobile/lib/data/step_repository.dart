import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/db/app_database.dart';
import '../core/time/clock.dart';
import '../domain/calc/step_aggregate.dart';
import '../domain/models/steps.dart';

/// Lưu mẫu bước và tổng hợp theo ngày (F01–F03).
class StepRepository {
  StepRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final _changes = StreamController<String>.broadcast();

  Stream<String> get changes => _changes.stream;

  /// Ghi mẫu; trùng (owner, source, start, end) bị bỏ qua.
  Future<void> addSample({
    required String ownerId,
    required StepSource source,
    String? sourceId,
    required int startAt,
    required int endAt,
    required int steps,
  }) async {
    if (steps < 0) return;
    await _db.db.insert(
      'step_samples',
      StepSample(
        id: const Uuid().v4(),
        ownerId: ownerId,
        source: source,
        sourceId: sourceId,
        startAt: startAt,
        endAt: endAt,
        steps: steps,
        tzId: currentTzId(),
      ).toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changes.add(ownerId);
  }

  /// Nhận giá trị counter tích lũy từ sensor; tự quản lý baseline/offset và reboot.
  Future<int?> ingestCounter({required String ownerId, required int counter, required int atMs}) async {
    final r = await _db.db.query('step_counter_state', where: 'owner_id = ?', whereArgs: [ownerId]);
    final last = r.isEmpty ? null : r.first['last_counter'] as int?;
    final lastAt = r.isEmpty ? null : r.first['last_counter_at'] as int?;
    final delta = counterDelta(lastCounter: last, current: counter);
    await _db.db.insert('step_counter_state', {
      'owner_id': ownerId,
      'last_counter': counter,
      'last_counter_at': atMs,
      'boot_marker': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (delta != null && delta > 0 && lastAt != null) {
      await addSample(ownerId: ownerId, source: StepSource.phoneSensor, startAt: lastAt, endAt: atMs, steps: delta);
    }
    return delta;
  }

  Future<List<StepSample>> samplesBetween(String ownerId, int fromMs, int toMs) async {
    final r = await _db.db.query(
      'step_samples',
      where: 'owner_id = ? AND end_at > ? AND start_at < ?',
      whereArgs: [ownerId, fromMs, toMs],
      orderBy: 'start_at',
    );
    return r.map(StepSample.fromRow).toList();
  }

  /// StepDay cho ngày địa phương [day]. [hasPermission] lấy từ PermissionCoordinator, không từ giá trị đã lưu.
  Future<StepDay> day(String ownerId, DateTime day, {required bool hasPermission, List<StepSource> priority = defaultSourcePriority}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final samples = await samplesBetween(ownerId, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
    final key = localDateKey(start);
    // Hôm nay: nếu có quyền và đã có baseline counter sau nửa đêm mà không có bước → 0 thật.
    var confirmedZero = false;
    if (hasPermission && samples.isEmpty) {
      final r = await _db.db.query('step_counter_state', where: 'owner_id = ?', whereArgs: [ownerId]);
      final lastAt = r.isEmpty ? null : r.first['last_counter_at'] as int?;
      confirmedZero = lastAt != null && lastAt >= start.millisecondsSinceEpoch && lastAt < end.millisecondsSinceEpoch;
    }
    return aggregateDay(
      dateKey: key,
      samples: samples,
      offsetMin: start.timeZoneOffset.inMinutes,
      hasPermission: hasPermission,
      priority: priority,
      sourceConfirmedZero: confirmedZero,
    );
  }

  Future<List<StepDay>> range(String ownerId, DateTime from, DateTime toExclusive, {required bool hasPermission}) async {
    final out = <StepDay>[];
    final today = _clock.nowLocal();
    for (var d = DateTime(from.year, from.month, from.day); d.isBefore(toExclusive); d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.isAfter(today)) break; // ngày tương lai không có bar
      out.add(await day(ownerId, d, hasPermission: hasPermission));
    }
    return out;
  }
}
