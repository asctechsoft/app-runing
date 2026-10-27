import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';

/// Q03 / N03: nâng schema SQLite từ MỌI phiên bản cũ lên bản mới nhất phải (1) ra đúng schema như cài mới, (2) giữ dữ liệu.
/// Khi thêm migration v(n+1): test này tự chạy thêm ca "từ v1..vn" — không cần viết test riêng cho từng bản.
Future<Map<String, String>> _schema(Database db) async {
  final rows = await db.rawQuery("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND sql IS NOT NULL ORDER BY name");
  return {for (final r in rows) '${r['type']}:${r['name']}': (r['sql'] as String).replaceAll(RegExp(r'\s+'), ' ').trim()};
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfiNoIsolate;

  test('mọi bước migration 1..schemaVersion đều tồn tại', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.applyMigrations(db, from: 0, to: AppDatabase.schemaVersion);
    expect(await _schema(db), isNotEmpty);
    await db.close();
  });

  for (var v = 1; v <= AppDatabase.schemaVersion; v++) {
    test('nâng từ v$v → v${AppDatabase.schemaVersion}: schema giống cài mới, dữ liệu settings còn nguyên', () async {
      final fresh = await AppDatabase.open(name: inMemoryDatabasePath, factory: factory);
      final expected = await _schema(fresh.db);
      await fresh.close();

      final old = await factory.openDatabase(inMemoryDatabasePath);
      await AppDatabase.applyMigrations(old, from: 0, to: v);
      await old.insert('settings', {'owner_id': 'guest:x', 'json': '{"weekStart":1}', 'revision': 3});
      await AppDatabase.applyMigrations(old, from: v, to: AppDatabase.schemaVersion);

      expect(await _schema(old), expected);
      final rows = await old.query('settings', where: 'owner_id = ?', whereArgs: ['guest:x']);
      expect(rows.single['json'], '{"weekStart":1}');
      expect(rows.single['revision'], 3);
      await old.close();
    });
  }

  test('thiếu bước migration → báo lỗi rõ, không âm thầm bỏ qua', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    await expectLater(AppDatabase.applyMigrations(db, from: 0, to: AppDatabase.schemaVersion + 1), throwsStateError);
    await db.close();
  });
}
