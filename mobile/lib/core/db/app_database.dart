import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local database offline-first (C03). Mọi bảng người dùng có owner_id và index owner/time.
/// Thêm migration: tăng [schemaVersion] và thêm bước vào [_migrations]; không sửa bước cũ.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const schemaVersion = 1;

  static Future<AppDatabase> open({String name = 'stride.db', DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = name == inMemoryDatabasePath ? name : p.join(await f.getDatabasesPath(), name);
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (var v = 1; v <= version; v++) {
            await _migrations[v]!(db);
          }
        },
        onUpgrade: (db, from, to) async {
          for (var v = from + 1; v <= to; v++) {
            await _migrations[v]!(db);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();

  static final Map<int, Future<void> Function(Database)> _migrations = {
    1: (db) async {
      final b = db.batch();
      b.execute('''
CREATE TABLE settings (
  owner_id TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 0
)''');
      b.execute('''
CREATE TABLE goal_versions (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  type TEXT NOT NULL,
  value REAL NOT NULL,
  effective_from TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''');
      b.execute('CREATE INDEX idx_goal_owner ON goal_versions(owner_id, type, effective_from)');
      b.execute('''
CREATE TABLE step_samples (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  source TEXT NOT NULL,
  source_id TEXT,
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL,
  steps INTEGER NOT NULL,
  tz_id TEXT NOT NULL
)''');
      b.execute('CREATE INDEX idx_steps_owner_time ON step_samples(owner_id, start_at)');
      b.execute('CREATE UNIQUE INDEX idx_steps_dedup ON step_samples(owner_id, source, start_at, end_at)');
      b.execute('''
CREATE TABLE step_counter_state (
  owner_id TEXT PRIMARY KEY,
  last_counter INTEGER,
  last_counter_at INTEGER,
  boot_marker INTEGER
)''');
      b.execute('''
CREATE TABLE activities (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  tz_id TEXT NOT NULL,
  tz_offset_min INTEGER NOT NULL,
  distance_m REAL,
  moving_ms INTEGER NOT NULL DEFAULT 0,
  elapsed_ms INTEGER NOT NULL DEFAULT 0,
  avg_pace_sec_per_km REAL,
  steps INTEGER,
  calories_kcal REAL,
  calorie_model TEXT,
  weight_kg_used REAL,
  title TEXT NOT NULL DEFAULT '',
  feeling TEXT,
  notes TEXT,
  privacy TEXT NOT NULL DEFAULT 'onlyMe',
  goal_json TEXT,
  has_gps INTEGER NOT NULL DEFAULT 0,
  distance_source TEXT NOT NULL DEFAULT 'gps',
  workout_execution_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local',
  revision INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)''');
      b.execute('CREATE INDEX idx_act_owner_time ON activities(owner_id, started_at DESC)');
      b.execute('CREATE INDEX idx_act_owner_status ON activities(owner_id, status)');
      b.execute('''
CREATE TABLE track_segments (
  id TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  reason TEXT NOT NULL
)''');
      b.execute('CREATE INDEX idx_seg_act ON track_segments(activity_id, seq)');
      b.execute('''
CREATE TABLE track_points (
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  segment_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  t INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,
  altitude_m REAL,
  speed_mps REAL,
  accepted INTEGER NOT NULL DEFAULT 1,
  reject_reason TEXT,
  PRIMARY KEY (activity_id, seq)
)''');
      b.execute('''
CREATE TABLE session_events (
  id TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  type TEXT NOT NULL,
  t INTEGER NOT NULL,
  mono_ms INTEGER NOT NULL,
  data_json TEXT
)''');
      b.execute('CREATE UNIQUE INDEX idx_evt_act_seq ON session_events(activity_id, seq)');
      b.execute('''
CREATE TABLE session_checkpoints (
  activity_id TEXT PRIMARY KEY REFERENCES activities(id) ON DELETE CASCADE,
  saved_at INTEGER NOT NULL,
  moving_ms INTEGER NOT NULL,
  distance_m REAL NOT NULL,
  last_point_seq INTEGER,
  last_event_seq INTEGER,
  phase TEXT NOT NULL,
  extra_json TEXT
)''');
      b.execute('''
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  owner_id TEXT NOT NULL,
  local_path TEXT,
  remote_key TEXT,
  mime TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  upload_state TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
)''');
      b.execute('CREATE INDEX idx_att_act ON attachments(activity_id)');
      b.execute('''
CREATE TABLE sync_outbox (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL
)''');
      b.execute('CREATE INDEX idx_outbox_owner_state ON sync_outbox(owner_id, state, next_attempt_at)');
      b.execute('''
CREATE TABLE sync_cursor (
  owner_id TEXT PRIMARY KEY,
  cursor TEXT,
  last_pulled_at INTEGER
)''');
      b.execute('''
CREATE TABLE workout_plans (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  name TEXT NOT NULL,
  steps_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)''');
      b.execute('CREATE INDEX idx_plan_owner ON workout_plans(owner_id)');
      b.execute('''
CREATE TABLE workout_executions (
  id TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  plan_snapshot_json TEXT NOT NULL,
  phases_json TEXT NOT NULL,
  current_phase INTEGER NOT NULL DEFAULT 0,
  incomplete INTEGER NOT NULL DEFAULT 0
)''');
      b.execute('''
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  remote_id TEXT NOT NULL,
  connected_at INTEGER,
  revoked_at INTEGER
)''');
      b.execute('''
CREATE TABLE heart_rate_samples (
  activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  t INTEGER NOT NULL,
  bpm INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  PRIMARY KEY (activity_id, t, device_id)
)''');
      b.execute('''
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  deep_link TEXT,
  created_at INTEGER NOT NULL,
  read_at INTEGER
)''');
      b.execute('CREATE INDEX idx_notif_owner ON notifications(owner_id, created_at DESC)');
      b.execute('''
CREATE TABLE reminders (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  enabled INTEGER NOT NULL,
  minute_of_day INTEGER NOT NULL,
  weekdays TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)''');
      b.execute('''
CREATE TABLE kv (
  owner_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT,
  PRIMARY KEY (owner_id, key)
)''');
      await b.commit(noResult: true);
    },
  };
}
