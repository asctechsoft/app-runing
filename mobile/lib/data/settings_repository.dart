import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/db/app_database.dart';
import '../core/time/clock.dart';
import '../domain/models/profile.dart';

/// Cài đặt + mục tiêu theo owner (E04, F06, J01).
class SettingsRepository {
  SettingsRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final _changes = StreamController<String>.broadcast();

  /// Phát ownerId mỗi khi settings/goals đổi để UI làm mới.
  Stream<String> get changes => _changes.stream;

  Future<UserSettings> load(String ownerId) async {
    final rows = await _db.db.query('settings', where: 'owner_id = ?', whereArgs: [ownerId]);
    if (rows.isEmpty) return UserSettings(ownerId: ownerId);
    return UserSettings.fromRow(rows.first);
  }

  Future<UserSettings> save(UserSettings s, {bool markDirty = true}) async {
    final next = s.copyWith(revision: s.revision + 1, updatedAt: _clock.nowMs());
    await _db.db.insert('settings', {...next.toRow(), 'dirty': markDirty ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(s.ownerId);
    return next;
  }

  Future<List<GoalVersion>> goals(String ownerId) async {
    final rows = await _db.db.query('goal_versions', where: 'owner_id = ?', whereArgs: [ownerId], orderBy: 'effective_from, created_at');
    return rows.map(GoalVersion.fromRow).toList();
  }

  /// Mục tiêu mới có hiệu lực từ hôm nay; không viết lại version của ngày đã qua (F06).
  Future<GoalVersion> setGoal(String ownerId, GoalType type, double value, {String? effectiveFrom}) async {
    final g = GoalVersion(
      id: const Uuid().v4(),
      ownerId: ownerId,
      type: type,
      value: value,
      effectiveFrom: effectiveFrom ?? localDateKey(_clock.nowLocal()),
      createdAt: _clock.nowMs(),
    );
    await _db.db.insert('goal_versions', g.toRow());
    _changes.add(ownerId);
    return g;
  }

  Future<GoalVersion?> goalFor(String ownerId, GoalType type, String localDate) async => goalForDate(await goals(ownerId), type, localDate);

  Future<String?> kvGet(String ownerId, String key) async {
    final r = await _db.db.query('kv', where: 'owner_id = ? AND key = ?', whereArgs: [ownerId, key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> kvSet(String ownerId, String key, String? value) async {
    await _db.db.insert('kv', {'owner_id': ownerId, 'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(ownerId);
  }
}
