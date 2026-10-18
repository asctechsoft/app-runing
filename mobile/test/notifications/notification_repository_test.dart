import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/core/db/app_database.dart';
import 'package:stride/core/time/clock.dart';
import 'package:stride/features/notifications/notification_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late FakeClock clock;
  late NotificationRepository repo;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock();
    repo = NotificationRepository(db, clock);
  });
  tearDown(() => db.close());

  test('chỉ lưu thông báo có deep link nội bộ', () async {
    expect(await repo.add(ownerId: 'o', kind: 'x', title: 'T', body: 'B', deepLink: 'https://evil.example'), isNull);
    expect(await repo.add(ownerId: 'o', kind: 'x', title: ' ', body: 'B', deepLink: '/home'), isNull);
    expect(await repo.add(ownerId: 'o', kind: 'goal', title: 'Goal reached', body: 'Nice', deepLink: '/home/steps'), isNotNull);
    expect((await repo.list('o')).length, 1);
  });

  test('mới nhất trước, unread count, mark read, tách owner', () async {
    final a = await repo.add(ownerId: 'o', kind: 'k', title: 'A', body: '', deepLink: '/home');
    clock.advance(const Duration(minutes: 1));
    await repo.add(ownerId: 'o', kind: 'k', title: 'B', body: '', deepLink: '/run');
    await repo.add(ownerId: 'other', kind: 'k', title: 'C', body: '', deepLink: '/run');
    final list = await repo.list('o');
    expect(list.map((n) => n.title), ['B', 'A']);
    expect(await repo.unreadCount('o'), 2);
    await repo.markRead('o', a!.id);
    expect(await repo.unreadCount('o'), 1);
    await repo.markRead('other', a.id); // owner khác không đụng được
    await repo.markAllRead('o');
    expect(await repo.unreadCount('o'), 0);
    expect(await repo.unreadCount('other'), 1);
  });
}
