import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/repository/activity_repository.dart';
import 'package:stride/repository/owner_repository.dart';
import 'package:stride/repository/settings_repository.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/controller/auth/auth_flow.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late FakeClock clock;
  late ActivityRepository repo;
  late SettingsRepository settings;
  late OwnerRepository owners;
  late GuestTransferService service;
  late String guest;
  const userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
    repo = ActivityRepository(db, clock);
    settings = SettingsRepository(db, clock);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    owners = OwnerRepository(prefs);
    guest = owners.guestId();
    service = GuestTransferService(db: db, activities: repo, settings: settings, owners: owners, prefs: prefs);
  });

  tearDown(() => db.close());

  Future<Activity> save(String owner) async {
    final (a, _) = await repo.createSession(ownerId: owner, type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
    clock.advance(const Duration(minutes: 20));
    final s = a.copyWith(distanceM: 3000, movingMs: 1200000, elapsedMs: 1200000, endedAt: clock.nowMs(), title: 'Run');
    await repo.finalizeSummary(s);
    return repo.saveActivity(s);
  }

  Future<List<Map<String, Object?>>> ops(String owner) => db.db.query('sync_outbox', where: "owner_id = ? AND state != 'acked'", whereArgs: [owner]);

  test('chuyển dữ liệu khách: activity + outbox sang tài khoản, không trùng', () async {
    await save(guest);
    await save(guest);
    await owners.signIn(userId: userA, email: 'a@example.com');

    final moved = await service.transfer(guestId: guest, userId: userA);

    expect(moved, 2);
    expect(await repo.countSaved(userA), 2);
    expect(await repo.countSaved(guest), 0);
    expect((await ops(userA)).length, 2, reason: 'mỗi activity đúng một op upsert cho user');
    expect(await ops(guest), isEmpty, reason: 'không còn op treo dưới owner khách');
  });

  test('thử lại (retry) không nhân đôi activity hay op', () async {
    await save(guest);
    await owners.signIn(userId: userA, email: 'a@example.com');
    await service.transfer(guestId: guest, userId: userA);
    final again = await service.transfer(guestId: guest, userId: userA);

    expect(again, 0);
    expect(await repo.countSaved(userA), 1);
    expect((await ops(userA)).length, 1);
    final keys = (await ops(userA)).map((o) => o['idempotency_key']).toSet();
    expect(keys.length, 1);
  });

  test('tài khoản khác không nhận dữ liệu đã chuyển cho tài khoản trước', () async {
    await save(guest);
    await owners.signIn(userId: userA, email: 'a@example.com');
    await service.transfer(guestId: guest, userId: userA);
    await save(userA);

    await owners.signOut();
    await owners.signIn(userId: userB, email: 'b@example.com');
    final moved = await service.transfer(guestId: guest, userId: userB);

    expect(moved, 0);
    expect(await repo.countSaved(userB), 0);
    expect(await repo.countSaved(userA), 2);
    expect(await ops(userB), isEmpty);
  });

  test('Keep separate: không gọi transfer → dữ liệu vẫn của khách', () async {
    await save(guest);
    await owners.signIn(userId: userA, email: 'a@example.com');
    expect(await repo.countSaved(userA), 0);
    expect(await repo.countSaved(guest), 1);
  });

  test('chỉ cho phép khách → tài khoản', () async {
    expect(() => service.transfer(guestId: userA, userId: userB), throwsArgumentError);
    expect(() => service.transfer(guestId: guest, userId: guest), throwsArgumentError);
  });

  test('hồ sơ khách được chép sang tài khoản chưa có hồ sơ', () async {
    final s = await settings.load(guest);
    await settings.save(s.copyWith(displayName: 'Lan'));
    await owners.markProfileSetupDone(guest);
    await owners.signIn(userId: userA, email: 'a@example.com');
    await service.transfer(guestId: guest, userId: userA);
    expect((await settings.load(userA)).displayName, 'Lan');
    expect(owners.current().profileSetupDone, isTrue);
  });
}
