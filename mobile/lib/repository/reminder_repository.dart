import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../controller/providers.dart';
import '../controller/reminders/reminder_logic.dart';
import '../services/storage/app_database.dart';
import 'settings_repository.dart';

const quietHoursKey = 'quietHours';

/// Lưu lịch nhắc trong bảng `reminders` và quiet hours trong kv.
class ReminderRepository {
  ReminderRepository(this._db, this._settings);
  final AppDatabase _db;
  final SettingsRepository _settings;

  Future<Map<ReminderKind, Reminder>> load(String ownerId) async {
    final rows = await _db.db.query('reminders', where: 'owner_id = ?', whereArgs: [ownerId]);
    final out = {for (final k in ReminderKind.values) k: Reminder.defaults(k)};
    for (final r in rows) {
      final rem = Reminder.fromRow(r);
      if (rem != null) out[rem.kind] = rem;
    }
    return out;
  }

  Future<void> save(String ownerId, Reminder r) async {
    await _db.db.insert('reminders', r.toRow(ownerId), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<QuietHours> loadQuietHours(String ownerId) async => QuietHours.decode(await _settings.kvGet(ownerId, quietHoursKey));

  Future<void> saveQuietHours(String ownerId, QuietHours q) => _settings.kvSet(ownerId, quietHoursKey, q.encode());
}

final remindersRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(ref.watch(databaseProvider), ref.watch(settingsRepositoryProvider)),
);
