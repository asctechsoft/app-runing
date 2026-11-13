import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/ui_models/community_models.dart';
import 'package:stride/repository/community_repository.dart';
import 'package:stride/repository/explore_repository.dart';

/// Repository Cộng đồng trên Firestore giả lập: dữ liệu ghi ra đúng hợp đồng (docs/firestore-schema.md), thả tim idempotent.
/// Quyền truy cập (khách không đọc được…) kiểm riêng ở firestore-tests/.
void main() {
  late FakeFirebaseFirestore db;
  const now = 1700000000000;

  CommunityRepository as(String? uid, {String name = '', int at = now}) =>
      CommunityRepository(ready: () => true, firestore: () => db, uid: () => uid, displayName: () => name, nowMs: () => at);

  Activity act({ActivityStatus status = ActivityStatus.saved, ActivityType type = ActivityType.run, int? deletedAt}) => Activity(
    id: 'secret-activity-id',
    ownerId: 'alice',
    type: type,
    status: status,
    startedAt: 1699990000000,
    tzId: 'Asia/Ho_Chi_Minh',
    tzOffsetMin: 420,
    distanceM: 5000,
    movingMs: 1800000,
    avgPaceSecPerKm: 360,
    notes: 'ghi chú riêng tư',
    title: 'Chạy sáng',
    deletedAt: deletedAt,
  );

  setUp(() => db = FakeFirebaseFirestore());

  test('publish chỉ ghi số liệu tóm tắt — không id hoạt động, ghi chú, tiêu đề, tọa độ', () async {
    final p = await as('alice', name: 'Alice').publish(act());
    final d = (await db.doc('communityPosts/${p.id}').get()).data()!;
    expect(d.keys.toSet(), {'authorId', 'authorName', 'text', 'createdAt', 'likeCount', 'deletedAt', 'activity'});
    expect((d['authorId'], d['authorName'], d['likeCount'], d['createdAt'], d['deletedAt']), ('alice', 'Alice', 0, now, null));
    expect(d['activity'], {
      'type': 'run',
      'startedAt': 1699990000000,
      'distanceM': 5000.0,
      'distanceEstimated': false,
      'movingMs': 1800000,
      'avgPaceSecPerKm': 360.0,
    });
  });

  test('publish kèm ảnh tuyến đường: lưu base64, đọc lại ra đúng byte; quá lớn thì từ chối', () async {
    final png = Uint8List.fromList(List.generate(64, (i) => i));
    final p = await as('alice').publish(act(), image: png);
    expect(p.image, png);
    final d = (await db.doc('communityPosts/${p.id}').get()).data()!;
    expect(d['image'], base64Encode(png));
    expect(CommunityPost.fromDoc(p.id, d).image, png);
    await expectLater(as('alice').publish(act(), image: Uint8List(maxCommunityImageBytes + 1)), throwsA(isA<ExploreFailure>()));
  });

  test('ảnh hỏng (không phải base64) coi như bài không có ảnh', () {
    expect(CommunityPost.decodeImage('***'), isNull);
    expect(CommunityPost.decodeImage(null), isNull);
    expect(CommunityPost.decodeImage(''), isNull);
  });

  test('ngừng chia sẻ (delete) đặt deletedAt và xóa ảnh khỏi document', () async {
    final p = await as('alice').publish(act(), image: Uint8List.fromList([1, 2, 3]));
    await as('alice').delete(p.id);
    final d = (await db.doc('communityPosts/${p.id}').get()).data()!;
    expect(d['deletedAt'], now);
    expect(d.containsKey('image'), isFalse);
  });

  test('buổi đạp xe được đăng với type bike', () async {
    final p = await as('alice').publish(act(type: ActivityType.bike));
    expect(p.type, ActivityType.bike);
  });

  test('không đăng hoạt động chưa lưu hoặc đã xóa', () async {
    for (final a in [act(status: ActivityStatus.awaitingSave), act(deletedAt: 5)]) {
      await expectLater(as('alice').publish(a), throwsA(isA<ExploreFailure>()));
    }
    expect((await db.collection('communityPosts').get()).docs, isEmpty);
  });

  test('chưa đăng nhập (uid null) → signedOut, không đọc/ghi Firestore', () async {
    await expectLater(as(null).feed(), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.signedOut)));
    await expectLater(as(null).publish(act()), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.signedOut)));
    expect((await db.collection('communityPosts').get()).docs, isEmpty);
  });

  test('feed: mới nhất trước, bỏ bài đã xóa, đánh dấu tim của tôi', () async {
    final old = await as('alice').publish(act());
    final newer = await as('alice', at: now + 1000).publish(act());
    final gone = await as('alice', at: now + 2000).publish(act());
    await as('alice').delete(gone.id);
    await as('bob').setLike(old.id, true);

    final page = await as('bob').feed();
    expect(page.posts.map((p) => p.id), [newer.id, old.id]);
    expect(page.posts.map((p) => p.likedByMe), [false, true]);
    expect(page.posts.last.likeCount, 1);
    expect(page.nextCursor, isNull, reason: 'ít hơn một trang → hết');
  });

  test('phân trang: trang đầy có cursor, trang sau nối tiếp không trùng, trang cuối hết cursor', () async {
    final ids = <String>[];
    for (var i = 0; i < 5; i++) {
      ids.add((await as('alice', at: now + i * 1000).publish(act())).id);
    }
    final newestFirst = ids.reversed.toList();
    final p1 = await as('bob').feed(limit: 2);
    expect(p1.posts.map((p) => p.id), newestFirst.sublist(0, 2));
    expect(p1.nextCursor, isNotNull);
    final p2 = await as('bob').feed(limit: 2, beforeCreatedAt: p1.nextCursor);
    expect(p2.posts.map((p) => p.id), newestFirst.sublist(2, 4));
    final p3 = await as('bob').feed(limit: 2, beforeCreatedAt: p2.nextCursor);
    expect(p3.posts.map((p) => p.id), newestFirst.sublist(4));
    expect(p3.nextCursor, isNull);
  });

  test('chặn người dùng: bài của họ biến mất khỏi bảng tin của tôi (dùng chung danh sách chặn Explore); không tự chặn mình', () async {
    await as('alice').publish(act());
    final mine = await as('bob', at: now + 1).publish(act());
    expect((await as('bob').feed()).posts, hasLength(2));
    await as('bob').blockUser('alice');
    expect((await db.doc('users/bob/blocks/alice').get()).exists, isTrue);
    expect((await as('bob').feed()).posts.map((p) => p.id), [mine.id]);
    await expectLater(as('bob').blockUser('bob'), throwsA(isA<ExploreFailure>()));
  });

  test('báo cáo bài và người dùng ghi vào reports với người báo cáo', () async {
    final p = await as('alice').publish(act());
    await as('bob').report(targetType: 'community_post', targetId: p.id, reason: 'spam');
    await as('bob').report(targetType: 'user', targetId: 'alice', reason: 'abuse');
    final docs = (await db.collection('reports').get()).docs.map((d) => d.data()).toList();
    expect(docs.map((d) => (d['reporterId'], d['targetType'], d['reason'])).toSet(), {('bob', 'community_post', 'spam'), ('bob', 'user', 'abuse')});
  });

  test('publish với chú thích: lưu text đã cắt khoảng trắng', () async {
    final p = await as('alice').publish(act(), text: '  Chạy sáng vui!  ');
    expect(p.text, 'Chạy sáng vui!');
    expect((await db.doc('communityPosts/${p.id}').get()).data()!['text'], 'Chạy sáng vui!');
  });

  test('setLike idempotent: thả hai lần chỉ +1, bỏ tim -1 và không âm', () async {
    final p = await as('alice').publish(act());
    final r = as('bob');
    expect((await r.setLike(p.id, true)).likeCount, 1);
    expect((await r.setLike(p.id, true)).likeCount, 1);
    expect((await as('carol').setLike(p.id, true)).likeCount, 2);
    final off = await r.setLike(p.id, false);
    expect((off.likeCount, off.likedByMe), (1, false));
    expect((await r.setLike(p.id, false)).likeCount, 1);
    expect((await db.doc('communityPosts/${p.id}/likes/bob').get()).exists, isFalse);
    expect((await db.doc('communityPosts/${p.id}/likes/carol').get()).exists, isTrue);
  });

  test('setLike bài không tồn tại → notFound', () async {
    await expectLater(as('bob').setLike('nope', true), throwsA(isA<ExploreFailure>().having((e) => e.kind, 'kind', ExploreErrorKind.notFound)));
  });
}
