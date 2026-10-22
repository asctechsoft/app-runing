import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/repository/activity_repository.dart';
import 'package:stride/repository/settings_repository.dart';
import 'package:stride/utils/calc/records.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/services/application/records_service.dart';

import '../activity/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late ActivityRepository acts;
  late SettingsRepository settings;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final clock = FakeClock(DateTime(2026, 10, 18).millisecondsSinceEpoch);
    acts = ActivityRepository(db, clock);
    settings = SettingsRepository(db, clock);
  });
  tearDown(() => db.close());

  /// Run có GPS thật: [meters] với tốc độ [msPer10m] cho mỗi 10 m.
  Future<Activity> gpsRun(DateTime start, double meters, {int msPer10m = 3000}) async {
    final a = await saveFixtureActivity(acts, owner: 'o', start: start, distanceM: meters, movingMs: (meters / 10 * msPer10m).round());
    await addFixtureTrack(acts, a, [straightTrack(meters: meters, startT: start.millisecondsSinceEpoch, msPerStep: msPer10m)]);
    return a;
  }

  PersonalRecord? find(List<PersonalRecord> rs, RecordKind k) => rs.where((r) => r.kind == k).firstOrNull;

  test('4.9 km không bao giờ thành record 5 km', () async {
    final a = await gpsRun(DateTime(2026, 10, 1, 7), 4900, msPer10m: 2000);
    final rs = await loadPersonalRecords(acts, settings, 'o');
    expect(find(rs, RecordKind.fastest5k), isNull);
    expect(find(rs, RecordKind.fastest1k)!.activityId, a.id);
    expect(find(rs, RecordKind.longestRun)!.value, 4900);
  });

  test('effort chỉ tính trong segment liên tục (2 × 2.6 km có pause không thành 5 km)', () async {
    final start = DateTime(2026, 10, 2, 7);
    final a = await saveFixtureActivity(acts, owner: 'o', start: start, distanceM: 5200);
    final t0 = start.millisecondsSinceEpoch;
    final seg1 = straightTrack(meters: 2600, startT: t0);
    final seg2 = straightTrack(lat: seg1.last.$1, lon: seg1.last.$2, meters: 2600, startT: seg1.last.$3 + 600000);
    await addFixtureTrack(acts, a, [seg1, seg2]);
    final rs = await loadPersonalRecords(acts, settings, 'o');
    expect(find(rs, RecordKind.fastest5k), isNull);
    expect(find(rs, RecordKind.fastest1k), isNotNull);
  });

  test('xóa hoạt động giữ record → tính lại từ hoạt động còn lại', () async {
    final slow = await gpsRun(DateTime(2026, 10, 3, 7), 5100, msPer10m: 3600);
    final fast = await gpsRun(DateTime(2026, 10, 5, 7), 5050, msPer10m: 2400);
    var rs = await loadPersonalRecords(acts, settings, 'o');
    expect(find(rs, RecordKind.fastest5k)!.activityId, fast.id);
    expect(find(rs, RecordKind.fastest5k)!.value, closeTo(5000 / 10 * 2400, 50));
    await acts.deleteActivity('o', fast.id);
    rs = await loadPersonalRecords(acts, settings, 'o');
    expect(find(rs, RecordKind.fastest5k)!.activityId, slow.id);
    expect(find(rs, RecordKind.longestRun)!.activityId, slow.id);
  });

  test('walk / indoor / không GPS không đủ điều kiện', () async {
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 4, 7), distanceM: 20000, type: ActivityType.walk);
    await saveFixtureActivity(
      acts,
      owner: 'o',
      start: DateTime(2026, 10, 4, 9),
      distanceM: 20000,
      type: ActivityType.indoorRun,
      hasGps: false,
      source: DistanceSource.steps,
    );
    await saveFixtureActivity(acts, owner: 'o', start: DateTime(2026, 10, 4, 11), distanceM: 20000, hasGps: false, source: DistanceSource.steps);
    expect(await loadPersonalRecords(acts, settings, 'o'), isEmpty);
  });

  test('cache effort gắn revision; sửa hoạt động thì tính lại', () async {
    final a = await gpsRun(DateTime(2026, 10, 6, 7), 1500);
    await bestEffortsFor(acts, settings, a);
    final cached = await settings.kvGet('o', effortCacheKey(a.id));
    expect(cached, contains('"rev":${a.revision}'));
    final edited = await acts.updateMetadata(a, title: 'Renamed');
    await bestEffortsFor(acts, settings, edited);
    expect(await settings.kvGet('o', effortCacheKey(a.id)), contains('"rev":${edited.revision}'));
  });
}
