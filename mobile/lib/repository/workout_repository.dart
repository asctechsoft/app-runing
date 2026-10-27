import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../controller/providers.dart';
import '../models/ui_models/workout_models.dart';
import '../utils/clock.dart';

/// Kết quả thực hiện interval đã lưu (bảng workout_executions).
class WorkoutExecution {
  const WorkoutExecution({
    required this.id,
    required this.activityId,
    required this.plan,
    required this.phases,
    required this.currentPhase,
    required this.incomplete,
  });

  final String id;
  final String activityId;
  final WorkoutPlan plan;
  final List<PhaseResult> phases;
  final int currentPhase;
  final bool incomplete;
}

/// Lưu preset giáo án và kết quả thực hiện (K01, K03). Truy vấn plan luôn scope theo owner.
class WorkoutRepository {
  WorkoutRepository(this._db, this._clock);

  final Database _db;
  final Clock _clock;
  final _uuid = const Uuid();

  Future<List<WorkoutPlan>> listPlans(String ownerId) async {
    final rows = await _db.query('workout_plans', where: 'owner_id = ? AND deleted_at IS NULL', whereArgs: [ownerId], orderBy: 'updated_at DESC');
    return rows.map(_planFromRow).toList();
  }

  Future<WorkoutPlan?> plan(String ownerId, String id) async {
    final rows = await _db.query('workout_plans', where: 'id = ? AND owner_id = ? AND deleted_at IS NULL', whereArgs: [id, ownerId]);
    return rows.isEmpty ? null : _planFromRow(rows.first);
  }

  /// Tạo mới hoặc cập nhật preset; trả plan có id.
  Future<WorkoutPlan> savePlan(String ownerId, WorkoutPlan plan) async {
    final now = _clock.nowMs();
    final id = plan.id ?? _uuid.v4();
    final body = jsonEncode({'audioCues': plan.audioCues, 'steps': plan.steps.map((s) => s.toJson()).toList()});
    final updated = await _db.update(
      'workout_plans',
      {'name': plan.name, 'steps_json': body, 'updated_at': now},
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, ownerId],
    );
    if (updated == 0) {
      await _db.insert('workout_plans', {'id': id, 'owner_id': ownerId, 'name': plan.name, 'steps_json': body, 'created_at': now, 'updated_at': now});
    }
    return plan.copyWith(id: id);
  }

  Future<void> deletePlan(String ownerId, String id) =>
      _db.update('workout_plans', {'deleted_at': _clock.nowMs()}, where: 'id = ? AND owner_id = ?', whereArgs: [id, ownerId]);

  WorkoutPlan _planFromRow(Map<String, Object?> r) {
    final raw = jsonDecode(r['steps_json'] as String);
    // Hỗ trợ cả dạng list thuần (domain-model) lẫn object {audioCues, steps}.
    final map = raw is List ? {'steps': raw} : (raw as Map).cast<String, Object?>();
    return WorkoutPlan.fromJson({...map, 'id': r['id'], 'name': r['name']});
  }

  /// Lưu kết quả thực hiện; activity xóa (discard) thì cascade xóa theo.
  Future<String> saveExecution({
    required String activityId,
    required WorkoutPlan plan,
    required List<PhaseResult> phases,
    required int currentPhase,
    required bool incomplete,
  }) async {
    final existing = await executionForActivity(activityId);
    final id = existing?.id ?? _uuid.v4();
    await _db.insert('workout_executions', {
      'id': id,
      'activity_id': activityId,
      'plan_snapshot_json': plan.encode(),
      'phases_json': jsonEncode(phases.map((p) => p.toJson()).toList()),
      'current_phase': currentPhase,
      'incomplete': incomplete ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<WorkoutExecution?> executionForActivity(String activityId) async {
    final rows = await _db.query('workout_executions', where: 'activity_id = ?', whereArgs: [activityId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return WorkoutExecution(
      id: r['id'] as String,
      activityId: activityId,
      plan: WorkoutPlan.decode(r['plan_snapshot_json'] as String),
      phases: (jsonDecode(r['phases_json'] as String) as List).map((p) => PhaseResult.fromJson((p as Map).cast<String, Object?>())).toList(),
      currentPhase: r['current_phase'] as int? ?? 0,
      incomplete: (r['incomplete'] as int? ?? 0) == 1,
    );
  }
}

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) => WorkoutRepository(ref.watch(databaseProvider).db, ref.watch(clockProvider)));

/// Danh sách preset của owner hiện tại.
final workoutPlansProvider = FutureProvider.autoDispose<List<WorkoutPlan>>((ref) {
  final owner = ref.watch(ownerProvider).ownerId;
  return ref.watch(workoutRepositoryProvider).listPlans(owner);
});
