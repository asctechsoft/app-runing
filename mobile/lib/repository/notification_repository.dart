import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../controller/providers.dart';
import '../services/storage/app_database.dart';
import '../utils/clock.dart';

/// Một mục trong inbox (NotificationItem — docs/domain-model.md).
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String ownerId;
  final String kind;
  final String title;
  final String body;
  final String? deepLink;
  final int createdAt;
  final int? readAt;

  bool get isRead => readAt != null;

  factory NotificationItem.fromRow(Map<String, Object?> r) => NotificationItem(
    id: r['id'] as String,
    ownerId: r['owner_id'] as String,
    kind: r['kind'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    deepLink: r['deep_link'] as String?,
    createdAt: r['created_at'] as int,
    readAt: r['read_at'] as int?,
  );
}

/// Inbox cục bộ (J02). Chỉ lưu thông báo có ích và có deep link tới màn đích.
class NotificationRepository {
  NotificationRepository(this._db, this._clock);
  final AppDatabase _db;
  final Clock _clock;
  final _changes = StreamController<String>.broadcast();

  Stream<String> get changes => _changes.stream;

  /// Thêm thông báo. [deepLink] bắt buộc là route nội bộ (bắt đầu bằng "/") — thông báo không dẫn đâu thì không lưu.
  Future<NotificationItem?> add({required String ownerId, required String kind, required String title, required String body, required String deepLink}) async {
    if (!deepLink.startsWith('/') || title.trim().isEmpty) return null;
    final item = NotificationItem(id: const Uuid().v4(), ownerId: ownerId, kind: kind, title: title, body: body, deepLink: deepLink, createdAt: _clock.nowMs());
    await _db.db.insert('notifications', {
      'id': item.id,
      'owner_id': ownerId,
      'kind': kind,
      'title': title,
      'body': body,
      'deep_link': deepLink,
      'created_at': item.createdAt,
      'read_at': null,
    });
    _changes.add(ownerId);
    return item;
  }

  Future<List<NotificationItem>> list(String ownerId, {int limit = 100}) async {
    final r = await _db.db.query('notifications', where: 'owner_id = ?', whereArgs: [ownerId], orderBy: 'created_at DESC', limit: limit);
    return r.map(NotificationItem.fromRow).toList();
  }

  Future<int> unreadCount(String ownerId) async {
    final r = await _db.db.rawQuery('SELECT COUNT(*) AS c FROM notifications WHERE owner_id = ? AND read_at IS NULL', [ownerId]);
    return (r.first['c'] as num).toInt();
  }

  Future<void> markRead(String ownerId, String id) async {
    await _db.db.update('notifications', {'read_at': _clock.nowMs()}, where: 'owner_id = ? AND id = ? AND read_at IS NULL', whereArgs: [ownerId, id]);
    _changes.add(ownerId);
  }

  Future<void> markAllRead(String ownerId) async {
    await _db.db.update('notifications', {'read_at': _clock.nowMs()}, where: 'owner_id = ? AND read_at IS NULL', whereArgs: [ownerId]);
    _changes.add(ownerId);
  }
}

final notificationsRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

final notificationsRevisionProvider = StreamProvider<int>((ref) async* {
  final owner = ref.watch(ownerProvider).ownerId;
  var n = 0;
  yield n;
  await for (final changed in ref.watch(notificationsRepositoryProvider).changes) {
    if (changed == owner) yield ++n;
  }
});

final notificationsListProvider = FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  ref.watch(notificationsRevisionProvider);
  return ref.read(notificationsRepositoryProvider).list(ref.watch(ownerProvider).ownerId);
});

final notificationsUnreadProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(notificationsRevisionProvider);
  return ref.read(notificationsRepositoryProvider).unreadCount(ref.watch(ownerProvider).ownerId);
});
