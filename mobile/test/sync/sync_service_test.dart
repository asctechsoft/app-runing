import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/models/data_models/sync.dart';
import 'package:stride/repository/owner_repository.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/services/application/sha256.dart';
import 'package:stride/services/application/sync_remote.dart';
import 'package:stride/services/application/sync_service.dart';

import 'sync_test_utils.dart';

const _guest = 'guest:22222222-2222-4222-8222-222222222222';

void main() {
  late SyncHarness h;

  setUp(() async {
    h = SyncHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  group('sha256', () {
    test('khớp vector chuẩn', () {
      expect(sha256Hex(utf8.encode('')), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('Outbox push (H03)', () {
    test('pending → acked, ghi document revision 1, chỉ synced sau ack', () async {
      final a = await h.recordAndSave(userId);
      final s = await h.sync.syncNow();

      expect(s.phase, SyncPhase.idle);
      expect(s.pending, 0);
      final doc = h.remote.activities[userId]![a.id]!;
      expect(doc['revision'], 1);
      expect(doc['title'], 'Morning run');
      expect(doc['deletedAt'], isNull);
      expect((await h.outbox()).single['state'], SyncOpState.acked.name);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('mất mạng → error + backoff; retry không nhân đôi', () async {
      final a = await h.recordAndSave(userId);
      h.remote.hook = (m) async => throw offlineError();

      final s1 = await h.sync.syncNow();
      expect(s1.phase, SyncPhase.offline);
      var op = (await h.outbox()).single;
      expect(op['state'], SyncOpState.error.name);
      expect(op['attempts'], 1);
      expect(op['next_attempt_at'], h.clock.nowMs() + SyncOperation.backoffMs(1));
      expect((await h.activityRow(a.id))['sync_state'], SyncState.pending.name, reason: 'không báo synced khi chưa có ack');

      // Chưa tới hạn backoff: không gửi lại.
      h.remote.calls.clear();
      await h.sync.syncNow();
      expect(h.remote.count('pushActivity'), 0);

      h.remote.hook = null;
      h.clock.advance(const Duration(seconds: 5));
      final s2 = await h.sync.syncNow();
      expect(s2.phase, SyncPhase.idle);
      op = (await h.outbox()).single;
      expect(op['state'], SyncOpState.acked.name);
      expect(h.remote.activities[userId], hasLength(1));
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('lần ghi trước đã thành công nhưng mất phản hồi → retry nhận ra và ack (không conflict)', () async {
      final a = await h.recordAndSave(userId);
      // Ghi thành công lên server nhưng client không biết.
      final op = SyncOperation.fromRow((await h.outbox()).single);
      final body = activityBodyForServer(op.payload);
      await h.remote.pushActivity(userId, a.id, expectedRevision: null, body: body, nowMs: 1);
      final s = await h.sync.syncNow();
      expect(s.conflicts, 0);
      expect((await h.outbox()).single['state'], SyncOpState.acked.name);
      expect(h.remote.activities[userId]![a.id]!['revision'], 1);
    });

    test('retry sau khi đã ack không gửi lại', () async {
      await h.recordAndSave(userId);
      await h.sync.syncNow();
      await h.sync.syncNow(manual: true);
      expect(h.remote.count('pushActivity'), 1);
    });

    test('op kẹt ở sending (app bị kill) được gửi lại', () async {
      await h.recordAndSave(userId);
      await h.db.db.update('sync_outbox', {'state': 'sending'});
      await h.sync.syncNow();
      expect((await h.outbox()).single['state'], 'acked');
    });

    test('lỗi 5xx là tạm thời: giữ op, đánh dấu error với backoff', () async {
      await h.recordAndSave(userId);
      h.remote.hook = (m) async => throw ApiException(500, 'internal_error', 'x');
      final s = await h.sync.syncNow();
      expect(s.phase, SyncPhase.error);
      expect(s.pending, 1);
      expect((await h.outbox()).single['last_error'], 'internal_error');
    });

    test('mất đăng nhập (401) giữ op pending và báo signedOut', () async {
      await h.recordAndSave(userId);
      h.remote.hook = (m) async => throw ApiException(401, 'unauthorized', 'x');
      final s = await h.sync.syncNow();
      expect(s.phase, SyncPhase.signedOut);
      expect((await h.outbox()).single['state'], SyncOpState.pending.name);
    });

    test('lỗi vĩnh viễn (403) đánh dấu error với backoff dài', () async {
      final a = await h.recordAndSave(userId);
      h.remote.hook = (m) async => throw ApiException(403, 'forbidden', 'x');
      final s = await h.sync.syncNow();
      expect(s.phase, SyncPhase.error);
      expect((await h.outbox()).single['last_error'], 'forbidden');
      expect((await h.outbox()).single['next_attempt_at'], greaterThan(h.clock.nowMs() + SyncOperation.backoffMs(5)));
      expect(a.id, isNotEmpty);
    });

    test('khách, chưa có uid hoặc Firebase chưa sẵn sàng: không gọi Firestore', () async {
      await h.recordAndSave(_guest);
      h.owner = const OwnerState(ownerId: _guest, isGuest: true);
      expect((await h.sync.syncNow()).phase, SyncPhase.signedOut);
      expect(h.remote.calls, isEmpty);

      h.owner = const OwnerState(ownerId: userId, isGuest: false);
      h.uid = null;
      expect((await h.sync.syncNow()).phase, SyncPhase.signedOut);
      h.uid = userId;
      h.firebaseReady = false;
      expect((await h.sync.syncNow()).phase, SyncPhase.signedOut);
      h.uid = 'other-uid';
      h.firebaseReady = true;
      expect((await h.sync.syncNow()).phase, SyncPhase.signedOut, reason: 'uid khác owner: không ghi dữ liệu sang tài khoản khác');
      expect(h.remote.calls, isEmpty);
    });

    test('update lần sau dùng revision server đã ack và tăng revision', () async {
      final a = await h.recordAndSave(userId);
      await h.sync.syncNow();
      final saved = (await h.activities.byId(userId, a.id))!;
      await h.activities.updateMetadata(saved, title: 'Evening run');
      await h.sync.syncNow();
      final doc = h.remote.activities[userId]![a.id]!;
      expect(doc['revision'], 2);
      expect(doc['title'], 'Evening run');
    });

    test('delete ghi tombstone, không xóa document', () async {
      final a = await h.recordAndSave(userId);
      await h.sync.syncNow();
      await h.activities.deleteActivity(userId, a.id);
      await h.sync.syncNow();
      final doc = h.remote.activities[userId]![a.id]!;
      expect(doc['deletedAt'], isNotNull);
      expect(doc['revision'], 2);
      expect(doc['title'], 'Morning run', reason: 'giữ nguyên các trường, chỉ thêm deletedAt');
      expect((await h.sync.pendingCount(userId)), 0);
    });

    test('delete chưa từng lên server (not_found) coi như xong', () async {
      final a = await h.recordAndSave(userId);
      await h.activities.deleteActivity(userId, a.id);
      final s = await h.sync.syncNow();
      expect(s.pending, 0);
      expect((await h.activityRow(a.id))['deleted_at'], isNotNull);
    });
  });

  group('Goal và profile', () {
    test('goal ghi theo ID (idempotent) và pull về máy khác', () async {
      final g = GoalVersion(id: 'g-1', ownerId: userId, type: GoalType.dailySteps, value: 5000, effectiveFrom: '2026-10-17', createdAt: 5000);
      await h.activities.enqueue(userId, 'goal', g.id, SyncOpType.upsert, g.toJson(), revision: 1);
      await h.sync.syncNow();
      expect(h.remote.goals[userId]!['g-1']!['createdAt'], 5000);
      expect(h.remote.goals[userId]!['g-1']!['value'], 5000);

      final other = SyncHarness(h.remote);
      await other.setUp();
      addTearDown(other.tearDown);
      await other.sync.syncNow();
      final rows = await other.db.db.query('goal_versions', where: 'owner_id = ?', whereArgs: [userId]);
      expect(rows.map((r) => r['id']), contains('g-1'));
    });

    test('profile: lấy revision server làm expected, không đè displayName/email', () async {
      h.remote.users[userId] = {
        'displayName': 'Dũng',
        'email': 'a@example.com',
        'profileRevision': 3,
        'profile': <String, Object?>{'locale': 'vi'},
      };
      await h.sync.enqueueProfile(await h.settings.load(userId));
      await h.sync.syncNow();
      final u = h.remote.users[userId]!;
      expect(u['profileRevision'], 4);
      expect(u['displayName'], 'Dũng');
      expect(u['email'], 'a@example.com');
      expect((u['profile'] as Map).containsKey('distanceUnit'), isTrue);
    });

    test('profile: máy khác sửa trước → xung đột giữ cả hai bản', () async {
      h.remote.users[userId] = {
        'profileRevision': 3,
        'profile': <String, Object?>{'displayName': 'Server'},
      };
      await h.sync.enqueueProfile(await h.settings.load(userId));
      // Chốt expectedRevision = 3 rồi máy khác ghi thêm.
      h.remote.hook = (m) async {
        if (m == 'pushProfile') {
          h.remote.hook = null;
          h.remote.users[userId] = {
            'profileRevision': 5,
            'profile': <String, Object?>{'displayName': 'Other'},
          };
        }
      };
      await h.sync.syncNow();
      final c = (await h.sync.conflicts()).single;
      expect(c.entity, 'profile');
      expect(c.server?['revision'], 5);
    });

    test('pull áp profile từ server một lần theo profileRevision', () async {
      h.remote.users[userId] = {
        'profileRevision': 2,
        'profile': <String, Object?>{'displayName': 'Từ máy khác', 'distanceUnit': 'mi'},
      };
      await h.sync.syncNow();
      final s = await h.settings.load(userId);
      expect(s.displayName, 'Từ máy khác');
      expect(s.distanceUnit.name, 'mi');
    });
  });

  group('Track chunk (H02)', () {
    test('ghi chunk có checksum, đủ chunk rồi mới synced', () async {
      final a = await h.recordAndSave(userId, gps: true, points: 5);
      final small = h.makeSync(chunkPoints: 2);
      addTearDown(small.dispose);
      await small.syncNow();
      final chunks = h.remote.chunks[userId]![a.id]!;
      expect(chunks.keys.toList()..sort(), [0, 1, 2]);
      for (final d in chunks.values) {
        expect(d['sha256'], sha256Hex(utf8.encode(d['json'] as String)));
      }
      final first = jsonDecode(chunks[0]!['json'] as String) as Map;
      expect((first['segments'] as List).length, 1, reason: 'chunk đầu khai báo segment');
      expect(chunks[0]!['count'], 2);
      expect(chunks[2]!['count'], 1);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('lỗi mạng giữa chừng → chưa synced; retry ghi lại cùng document', () async {
      final a = await h.recordAndSave(userId, gps: true, points: 3);
      final small = h.makeSync(chunkPoints: 2);
      addTearDown(small.dispose);
      var puts = 0;
      h.remote.hook = (m) async {
        if (m == 'putTrackChunk' && ++puts == 2) throw offlineError();
      };
      await small.syncNow();
      expect((await h.activityRow(a.id))['sync_state'], SyncState.pending.name);
      final firstDoc = Map.of(h.remote.chunks[userId]![a.id]![0]!);

      h.remote.hook = null;
      h.clock.advance(const Duration(minutes: 1));
      await small.syncNow();
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
      expect(h.remote.chunks[userId]![a.id]![0], firstDoc, reason: 'chunk tất định → cùng bytes/sha256');
      expect(h.remote.chunks[userId]![a.id], hasLength(2));
    });

    test('máy khác pull activity có GPS và dựng lại track từ chunk', () async {
      final a = await h.recordAndSave(userId, gps: true, points: 5);
      final small = h.makeSync(chunkPoints: 2);
      addTearDown(small.dispose);
      await small.syncNow();

      final other = SyncHarness(h.remote);
      await other.setUp();
      addTearDown(other.tearDown);
      await other.sync.syncNow();
      final pts = await other.activities.points(a.id);
      expect(pts.length, 5);
      expect(pts.map((p) => p.seq), [0, 1, 2, 3, 4]);
      expect((await other.activities.segments(a.id)).length, 1);
    });
  });

  group('Pull & tombstone (H03)', () {
    test('bản đã xóa local không sống lại khi pull trả upsert cũ', () async {
      final a = await h.recordAndSave(userId);
      await h.sync.syncNow();
      await h.activities.deleteActivity(userId, a.id);

      h.remote.hook = (m) async {
        if (m == 'pushActivity') throw offlineError();
      };
      await h.sync.syncNow(); // push delete lỗi mạng, op còn treo

      // Máy khác sửa (revision 2) trước khi delete tới server; pull trả bản upsert.
      h.remote.hook = (m) async {
        if (m == 'pushActivity') throw ApiException(503, 'unavailable_svc', 'x');
      };
      final stored = Map.of(h.remote.activities[userId]![a.id]!)..remove('_us');
      h.remote.seedActivity(userId, a.id, {...stored, 'title': 'Edited elsewhere'}, revision: 2);
      h.clock.advance(const Duration(minutes: 5));
      await h.sync.syncNow();

      final row = await h.activityRow(a.id);
      expect(row['deleted_at'], isNotNull);
      expect(row['title'], 'Morning run');
      expect(await h.activities.byId(userId, a.id), isNull);
      final cursor = await h.db.db.query('sync_cursor');
      expect(int.parse(cursor.single['cursor'] as String), greaterThan(0));
    });

    test('pull tombstone áp xóa và bỏ thao tác local đang treo', () async {
      final a = await h.recordAndSave(userId);
      h.remote.hook = (m) async {
        if (m == 'pushActivity') throw ApiException(503, 'x', 'x');
      };
      h.remote.seedActivity(userId, a.id, {'type': 'run', 'title': 'x'}, revision: 3, deletedAt: h.clock.nowMs());
      final s = await h.sync.syncNow();
      expect((await h.activityRow(a.id))['deleted_at'], isNotNull);
      expect(s.pending, 0);
      expect(await h.activities.countSaved(userId), 0);
    });

    test('pull chèn hoạt động mới từ máy khác và không ghi đè owner khác', () async {
      final other = await h.recordAndSave('guest:33333333-3333-4333-8333-333333333333');
      const newId = '44444444-4444-4444-8444-444444444444';
      h.remote.seedActivity(userId, newId, {
        'type': 'walk',
        'status': 'saved',
        'startedAt': 1000,
        'endedAt': 2000,
        'tzId': 'UTC',
        'tzOffsetMin': 0,
        'movingMs': 1000,
        'elapsedMs': 1000,
        'title': 'Walk',
        'hasGps': false,
        'distanceSource': 'steps',
      });
      h.remote.seedActivity(userId, other.id, {}, revision: 2, deletedAt: 5);
      await h.sync.syncNow();
      expect((await h.activities.byId(userId, newId))?.title, 'Walk');
      expect((await h.activityRow(other.id))['deleted_at'], isNull, reason: 'không chạm dữ liệu owner khác');
    });

    test('cursor tăng dần: lần pull sau không đọc lại bản cũ', () async {
      h.remote.seedActivity(userId, '55555555-5555-4555-8555-555555555555', {
        'type': 'walk',
        'status': 'saved',
        'startedAt': 1000,
        'endedAt': 2000,
        'tzId': 'UTC',
        'tzOffsetMin': 0,
        'movingMs': 1000,
        'elapsedMs': 1000,
        'title': 'Walk',
        'hasGps': false,
        'distanceSource': 'steps',
      });
      await h.sync.syncNow();
      final c1 = (await h.db.db.query('sync_cursor')).single['cursor'];
      await h.sync.syncNow();
      expect((await h.db.db.query('sync_cursor')).single['cursor'], c1);
    });
  });

  group('Xung đột (H04)', () {
    Map<String, Object?> serverDoc(Activity a, String title) => {...a.toJson()..remove('id'), 'title': title};

    test('revision lệch giữ cả hai bản; Keep this device đẩy lại với revision server', () async {
      final a = await h.recordAndSave(userId);
      h.remote.seedActivity(userId, a.id, serverDoc(a, 'Server title'), revision: 7);
      final s = await h.sync.syncNow();
      expect(s.conflicts, 1);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.error.name);
      final conflicts = await h.sync.conflicts();
      expect(conflicts.single.server?['title'], 'Server title');
      expect(conflicts.single.server?['revision'], 7);
      expect(conflicts.single.local['title'], 'Morning run');

      // Xung đột không tự retry.
      h.remote.calls.clear();
      h.clock.advance(const Duration(hours: 2));
      await h.sync.syncNow(manual: true);
      expect(h.remote.count('pushActivity'), 0);

      await h.sync.resolveKeepLocal(conflicts.single);
      await h.sync.syncNow();
      final doc = h.remote.activities[userId]![a.id]!;
      expect(doc['revision'], 8);
      expect(doc['title'], 'Morning run');
      expect(await h.sync.conflicts(), isEmpty);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('Use other device áp bản server vào local', () async {
      final a = await h.recordAndSave(userId);
      h.remote.seedActivity(userId, a.id, serverDoc(a, 'Server title'), revision: 7);
      await h.sync.syncNow();
      final c = (await h.sync.conflicts()).single;
      await h.sync.resolveKeepServer(c);
      expect((await h.activities.byId(userId, a.id))?.title, 'Server title');
      expect(await h.sync.pendingCount(userId), 0);
    });

    test('server đã xóa (tombstone) → tombstone thắng, không hồi sinh', () async {
      final a = await h.recordAndSave(userId);
      h.remote.seedActivity(userId, a.id, serverDoc(a, 'x'), revision: 3, deletedAt: 123);
      await h.sync.syncNow();
      expect((await h.activityRow(a.id))['deleted_at'], 123);
      expect(await h.sync.conflicts(), isEmpty);
      expect(h.remote.activities[userId]![a.id]!['revision'], 3, reason: 'không ghi đè tombstone');
    });
  });

  group('Hàm thuần', () {
    test('title rỗng → nhãn theo loại; bỏ id/revision', () {
      final body = activityBodyForServer({
        'id': 'x',
        'type': 'indoorRun',
        'title': '',
        'revision': 3,
        'goal': {'type': 'free', 'value': null},
      });
      expect(body['title'], 'Indoor run');
      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('revision'), isFalse);
    });

    test('trackChunkDocId đệm 5 chữ số; mặc định 500 điểm/chunk', () {
      expect(trackChunkDocId(0), '00000');
      expect(trackChunkDocId(42), '00042');
      expect(kTrackChunkPoints, 500);
    });

    test('buildTrackChunks + trackChunkDocs + parseTrackChunks khứ hồi', () {
      const seg = TrackSegment(id: 's1', activityId: 'a', seq: 0, startedAt: 1, endedAt: null, reason: SegmentReason.start);
      final pts = [for (var i = 0; i < 1100; i++) TrackPoint(activityId: 'a', segmentId: 's1', seq: i, t: i, lat: 1, lon: 2)];
      final docs = trackChunkDocs(buildTrackChunks([seg], pts, kTrackChunkPoints));
      expect(docs.map((d) => d['count']), [500, 500, 100]);
      for (final d in docs) {
        expect(utf8.encode(d['json'] as String).length, lessThan(1024 * 1024));
      }
      final (segs, points) = parseTrackChunks('a', docs.reversed.toList());
      expect(segs.single.id, 's1');
      expect(points.length, 1100);
      expect(points.first.activityId, 'a');
    });

    test('parseTrackChunks từ chối chunk sai checksum', () {
      const seg = TrackSegment(id: 's1', activityId: 'a', seq: 0, startedAt: 1, endedAt: null, reason: SegmentReason.start);
      final docs = trackChunkDocs(buildTrackChunks([seg], [const TrackPoint(activityId: 'a', segmentId: 's1', seq: 0, t: 0, lat: 1, lon: 2)], 500));
      docs.first['sha256'] = '00';
      expect(() => parseTrackChunks('a', docs), throwsFormatException);
    });

    test('normalizeFirestoreValue: Timestamp → ms, đệ quy', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1234567);
      final out = normalizeFirestoreValue({
        'a': ts,
        'b': [
          ts,
          {'c': ts},
        ],
        'd': 5,
      }) as Map;
      expect(out['a'], 1234567);
      expect(out['b'], [
        1234567,
        {'c': 1234567},
      ]);
      expect(out['d'], 5);
      expect(serverUpdatedAtUs(ts), 1234567000);
    });

    test('nextCursorUs không bao giờ lùi', () {
      expect(nextCursorUs(null, const []), isNull);
      expect(nextCursorUs(null, [3, 9, 5]), 9);
      expect(nextCursorUs(10, [3, 9]), 10);
    });

    test('pullItemFromActivityDoc: tombstone → delete', () {
      expect(pullItemFromActivityDoc('x', {'revision': 2, 'deletedAt': 5})['op'], 'delete');
      final up = pullItemFromActivityDoc('x', {'revision': 2, 'deletedAt': null, 'serverUpdatedAt': 1});
      expect(up['op'], 'upsert');
      expect((up['data'] as Map).containsKey('serverUpdatedAt'), isFalse);
    });

    test('decideActivityPush theo revision', () {
      final body = <String, Object?>{'title': 't', 'distanceM': 5200};
      ActivityPushDecision d(Map<String, Object?>? existing, int? exp, {Map<String, Object?>? b = const {'title': 't'}}) =>
          decideActivityPush(existing: existing, expectedRevision: exp, body: b, id: 'x');
      expect(d(null, null, b: body).newRevision, 1);
      expect(d(null, null, b: null).result!.code, 'not_found');
      expect(d({'revision': 2}, 2).newRevision, 3);
      expect(d({'revision': 2}, 1).result!.code, 'revision_conflict');
      expect(d({'revision': 2}, null).result!.code, 'revision_required');
      expect(d({'revision': 2, 'deletedAt': 9}, 2).result!.code, 'activity_deleted');
      expect(d({'revision': 2, 'deletedAt': 9}, 2, b: null).result!.status, PushStatus.acked);
      expect(d({'revision': 2}, 0, b: null).newRevision, 3, reason: 'xóa không bị chặn bởi revision');
      // Ghi lặp (mất phản hồi): revision = expected + 1 và nội dung giống, kể cả int/double.
      expect(d({'revision': 2, 'title': 't', 'distanceM': 5200.0}, 1, b: body).result!.status, PushStatus.acked);
      expect(d({'revision': 2, 'title': 'khác'}, 1).result!.status, PushStatus.conflict);
    });

    test('decideProfilePush', () {
      final p = <String, Object?>{'locale': 'vi'};
      expect(decideProfilePush(existingDoc: null, expectedRevision: null, profile: p).newRevision, 1);
      expect(decideProfilePush(existingDoc: {'profileRevision': 3}, expectedRevision: 3, profile: p).newRevision, 4);
      expect(decideProfilePush(existingDoc: {'profileRevision': 3}, expectedRevision: 2, profile: p).result!.status, PushStatus.conflict);
      expect(decideProfilePush(existingDoc: {'profileRevision': 3, 'profile': p}, expectedRevision: 2, profile: p).result!.status, PushStatus.acked);
    });
  });
}
