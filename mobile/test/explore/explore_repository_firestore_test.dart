import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/repository/explore_repository.dart';

/// Repository Explore trên Firestore giả lập trong bộ nhớ (X46): kiểm dữ liệu ghi ra đúng hợp đồng
/// (docs/firestore-schema.md) và các transaction TM01/TM02/TM03/TM30. Quyền truy cập kiểm riêng ở firestore-tests/.
void main() {
  late FakeFirebaseFirestore db;
  var now = DateTime.now().millisecondsSinceEpoch;

  ExploreRepository as(String uid, {String name = ''}) =>
      ExploreRepository(ready: () => true, firestore: () => db, uid: () => uid, displayName: () => name, nowMs: () => now);

  Future<Map<String, dynamic>?> doc(String path) async => (await db.doc(path).get()).data();

  setUp(() {
    db = FakeFirebaseFirestore();
    now = DateTime.now().millisecondsSinceEpoch;
  });

  group('TM01: createClub', () {
    test('ghi club + owner + hạn mức; club hiện trong "của tôi"', () async {
      final id = await as('olly', name: 'Olly').createClub(name: ' Morning Crew ', description: 'Easy', region: 'Hanoi', isPrivate: true);
      expect(await doc('clubs/$id'), {
        'name': 'Morning Crew',
        'nameLower': 'morning crew',
        'description': 'Easy',
        'region': 'Hanoi',
        'visibility': 'private',
        'memberCount': 1,
        'ownerId': 'olly',
        'createdAt': now,
      });
      final m = await doc('clubs/$id/members/olly');
      expect((m!['role'], m['status'], m['displayName']), ('owner', 'active', 'Olly'));
      final q = await doc('clubQuota/olly');
      expect(q!['count'], 1);
      expect(q['lastCreatedAt'], isA<Timestamp>());
      final mine = await as('olly').myClubs();
      expect(mine.single.id, id);
      expect(mine.single.isPrivate, isTrue);
      expect(mine.single.membership!.isOwner, isTrue);
    });

    test('tạo lần hai trong 1 giờ → club_too_soon; đủ 5 club → club_limit', () async {
      await as('olly').createClub(name: 'One', description: '', region: '', isPrivate: false);
      await expectLater(
        as('olly').createClub(name: 'Two', description: '', region: '', isPrivate: false),
        throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'club_too_soon')),
      );
      await db.doc('clubQuota/olly').set({'count': maxOwnedClubs, 'lastCreatedAt': Timestamp.fromMillisecondsSinceEpoch(0)});
      await expectLater(
        as('olly').createClub(name: 'Six', description: '', region: '', isPrivate: false),
        throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', 'club_limit')),
      );
    });
  });

  group('TM04: updateClub', () {
    test('ghi patch, giữ owner/bộ đếm; club() đọc lại nội quy', () async {
      final id = await as('olly').createClub(name: 'Morning Crew', description: '', region: '', isPrivate: false);
      await as('olly').updateClub(id, name: 'Evening Crew', description: 'Hi', region: 'HCM', isPrivate: true, rulesText: 'Be kind');
      final d = (await doc('clubs/$id'))!;
      expect(
        (d['name'], d['nameLower'], d['visibility'], d['rulesText'], d['ownerId'], d['memberCount']),
        ('Evening Crew', 'evening crew', 'private', 'Be kind', 'olly', 1),
      );
      final c = await as('olly').club(id);
      expect((c.rulesText, c.isPrivate, c.regionText), ('Be kind', true, 'HCM'));
    });
  });

  group('TM04: giải tán', () {
    test('lưu trữ → ẩn khỏi tìm kiếm, vẫn trong "của tôi" với cờ archived', () async {
      final id = await as('olly').createClub(name: 'Morning Crew', description: '', region: '', isPrivate: false);
      expect((await as('bob').searchClubs()).items.map((c) => c.id), [id]);
      await as('olly').archiveClub(id);
      expect((await as('bob').searchClubs()).items, isEmpty);
      expect((await as('olly').myClubs()).single.archived, isTrue);
    });

    test('ghim bài: lưu pinnedPostId; post() bỏ bài đã xóa', () async {
      await db.doc('clubs/c1').set({'name': 'Club', 'visibility': 'public', 'memberCount': 1, 'ownerId': 'olly'});
      await db.doc('posts/p1').set({
        'clubId': 'c1',
        'authorId': 'olly',
        'text': 'Rules',
        'createdAt': 1,
        'cheerCount': 0,
        'commentCount': 0,
        'deletedAt': null,
      });
      await db.doc('posts/gone').set({'clubId': 'c1', 'authorId': 'olly', 'text': 'x', 'createdAt': 1, 'deletedAt': 5});
      await as('olly').setPinnedPost('c1', 'p1');
      expect((await as('olly').club('c1')).pinnedPostId, 'p1');
      expect((await as('bob').post('p1'))!.text, 'Rules');
      expect(await as('bob').post('gone'), isNull);
      await as('olly').setPinnedPost('c1', null);
      expect((await as('olly').club('c1')).pinnedPostId, isNull);
    });
  });

  group('TM02: thành viên', () {
    setUp(() async {
      await db.doc('clubs/c1').set({'name': 'Club', 'visibility': 'private', 'memberCount': 2, 'ownerId': 'olly'});
      await db.doc('clubs/c1/members/olly').set({'userId': 'olly', 'role': 'owner', 'status': 'active', 'joinedAt': 1});
      await db.doc('clubs/c1/members/mia').set({'userId': 'mia', 'role': 'member', 'status': 'active', 'joinedAt': 2});
      await db.doc('clubs/c1/members/pete').set({'userId': 'pete', 'role': 'member', 'status': 'pending', 'joinedAt': 3});
    });

    test('liệt kê active và pending riêng', () async {
      final active = await as('olly').clubMembers('c1');
      expect(active.items.map((m) => m.userId), ['olly', 'mia']);
      final pending = await as('olly').clubMembers('c1', pending: true);
      expect(pending.items.single.userId, 'pete');
    });

    test('duyệt → active + memberCount +1; duyệt lại không cộng thêm', () async {
      await as('olly').approveMember('c1', 'pete');
      await as('olly').approveMember('c1', 'pete');
      expect((await doc('clubs/c1/members/pete'))!['status'], 'active');
      expect((await doc('clubs/c1'))!['memberCount'], 3);
    });

    test('xóa member active → memberCount −1; từ chối pending không trừ; cấm ghi bans', () async {
      await as('olly').removeMember('c1', 'pete');
      expect((await doc('clubs/c1'))!['memberCount'], 2);
      await as('olly').removeMember('c1', 'mia', ban: true);
      expect(await doc('clubs/c1/members/mia'), isNull);
      expect((await doc('clubs/c1'))!['memberCount'], 1);
      expect((await doc('clubs/c1/bans/mia'))!['bannedBy'], 'olly');
    });

    test('đổi vai trò; chuyển quyền chủ đổi cả ba document', () async {
      await as('olly').setMemberRole('c1', 'mia', 'admin');
      expect((await doc('clubs/c1/members/mia'))!['role'], 'admin');
      await as('olly').transferOwnership('c1', 'mia');
      expect((await doc('clubs/c1/members/mia'))!['role'], 'owner');
      expect((await doc('clubs/c1/members/olly'))!['role'], 'admin');
      expect((await doc('clubs/c1'))!['ownerId'], 'mia');
      await expectLater(as('mia').transferOwnership('c1', 'nobody'), throwsA(isA<ExploreFailure>()));
    });
  });

  group('TM03: mã mời', () {
    setUp(() async {
      await db.doc('clubs/p1').set({'name': 'Private', 'visibility': 'private', 'memberCount': 1, 'ownerId': 'olly'});
      await db.doc('clubs/p1/members/olly').set({'userId': 'olly', 'role': 'owner', 'status': 'active', 'joinedAt': 1});
    });

    test('tạo mã → người khác vào club riêng ngay (active), lượt dùng và memberCount +1', () async {
      final inv = await as('olly').createInvite('p1');
      expect(normalizeInviteCode(inv.code), inv.code);
      final stored = await doc('clubInvites/${inv.code}');
      expect(
        (stored!['clubId'], stored['uses'], stored['maxUses'], stored['expiresAt']),
        ('p1', 0, inviteDefaultMaxUses, now + inviteDefaultTtl.inMilliseconds),
      );

      final clubId = await as('bob', name: 'Bob').joinWithCode(inv.code.toLowerCase());
      expect(clubId, 'p1');
      final m = await doc('clubs/p1/members/bob');
      expect((m!['status'], m['role'], m['inviteCode']), ('active', 'member', inv.code));
      expect((await doc('clubInvites/${inv.code}'))!['uses'], 1);
      expect((await doc('clubs/p1'))!['memberCount'], 2);

      // Dùng lại khi đã là thành viên: không tốn lượt.
      await as('bob').joinWithCode(inv.code);
      expect((await doc('clubInvites/${inv.code}'))!['uses'], 1);
    });

    test('đang chờ duyệt + mã → active (cập nhật, không tạo bản mới)', () async {
      final inv = await as('olly').createInvite('p1');
      await db.doc('clubs/p1/members/pete').set({'userId': 'pete', 'role': 'member', 'status': 'pending', 'joinedAt': 5});
      await as('pete').joinWithCode(inv.code);
      final m = await doc('clubs/p1/members/pete');
      expect((m!['status'], m['joinedAt'], m['inviteCode']), ('active', 5, inv.code));
    });

    test('mã sai định dạng / không tồn tại / hết hạn / hết lượt → lỗi có mã riêng', () async {
      Matcher code(String c) => throwsA(isA<ExploreFailure>().having((e) => e.code, 'code', c));
      await expectLater(as('bob').joinWithCode('nope'), code('invite_invalid'));
      await expectLater(as('bob').joinWithCode('ABCDEFGH'), code('invite_not_found'));
      await db.doc('clubInvites/EXPDATE2').set({'clubId': 'p1', 'expiresAt': now - 1, 'uses': 0, 'maxUses': 5});
      await expectLater(as('bob').joinWithCode('EXPDATE2'), code('invite_expired'));
      await db.doc('clubInvites/USEDUP22').set({'clubId': 'p1', 'expiresAt': now + 1000, 'uses': 5, 'maxUses': 5});
      await expectLater(as('bob').joinWithCode('USEDUP22'), code('invite_used_up'));
      expect(await doc('clubs/p1/members/bob'), isNull);
    });
  });

  group('TM30: bảng xếp hạng', () {
    setUp(() async {
      await db.doc('challenges/ch1').set({'title': 'x', 'metric': 'distance', 'target': 100000, 'startsAt': 0, 'endsAt': now + 1000, 'participantCount': 4});
      Future<void> p(String id, double v, int t, {bool optIn = true}) => db.doc('challenges/ch1/participants/$id').set({
        'userId': id,
        'displayName': id,
        'leaderboardOptIn': optIn,
        'progressValue': v,
        'progressUpdatedAt': t,
      });
      await p('ann', 9000, 10);
      await p('bo', 5000, 20);
      await p('cy', 5000, 15);
      await p('hidden', 99999, 1, optIn: false);
      await p('me', 1000, 5, optIn: false);
    });

    test('chỉ người bật hiển thị; đồng điểm ai đạt trước xếp trên; tôi đang ẩn thì không có hạng', () async {
      final b = await as('me').challengeLeaderboard('ch1');
      expect(b.entries.map((e) => (e.userId, e.rank)), [('ann', 1), ('cy', 2), ('bo', 3)]);
      expect((b.joined, b.optedIn, b.me!.rank), (true, false, 0));
    });

    test('bật hiện tên → có hạng; người bị chặn bị ẩn khỏi danh sách', () async {
      await as('me').setLeaderboardOptIn('ch1', true);
      expect((await doc('users/me/challengeJoins/ch1'))!['leaderboardOptIn'], isTrue);
      await db.doc('users/me/blocks/ann').set({'createdAt': 1});
      final b = await as('me').challengeLeaderboard('ch1');
      expect(b.entries.map((e) => (e.userId, e.rank)), [('cy', 2), ('bo', 3), ('me', 4)]);
      expect((b.optedIn, b.me!.rank), (true, 4));
    });

    test('chưa tham gia', () async {
      final b = await as('stranger').challengeLeaderboard('ch1');
      expect((b.joined, b.me), (false, null));
    });
  });
}
