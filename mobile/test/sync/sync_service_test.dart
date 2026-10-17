import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stride/data/owner_repository.dart';
import 'package:stride/domain/models/activity.dart';
import 'package:stride/domain/models/sync.dart';
import 'package:stride/features/sync/sha256.dart';
import 'package:stride/features/sync/sync_service.dart';

import 'sync_test_utils.dart';

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
      expect(
        sha256Hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });
  });

  group('Outbox push (H03)', () {
    test('pending → acked, Idempotency-Key = op.idempotencyKey, chỉ synced sau ack', () async {
      final a = await h.recordAndSave(userId);
      final key = (await h.outbox()).single['idempotency_key'];
      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r, revision: 1) : emptyPull();

      final s = await h.sync.syncNow();

      expect(s.phase, SyncPhase.idle);
      expect(s.pending, 0);
      final push = h.calls('/sync/push').single;
      expect(push.headers['Idempotency-Key'], key);
      expect(firstOp(push)['idempotencyKey'], key);
      expect(firstOp(push).containsKey('expectedRevision'), isFalse, reason: 'tạo mới: chưa biết revision server');
      expect((firstOp(push)['payload'] as Map)['title'], 'Morning run');
      expect((await h.outbox()).single['state'], SyncOpState.acked.name);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('mất mạng → error + backoff, retry gửi lại cùng key, không nhân đôi', () async {
      final a = await h.recordAndSave(userId);
      h.handler = (r) async => throw http.ClientException('no network');

      final s1 = await h.sync.syncNow();
      expect(s1.phase, SyncPhase.offline);
      var op = (await h.outbox()).single;
      expect(op['state'], SyncOpState.error.name);
      expect(op['attempts'], 1);
      expect(op['next_attempt_at'], h.clock.nowMs() + SyncOperation.backoffMs(1));
      expect((await h.activityRow(a.id))['sync_state'], SyncState.pending.name, reason: 'không báo synced khi chưa có ack');

      // Chưa tới hạn backoff: không gửi lại.
      h.requests.clear();
      await h.sync.syncNow();
      expect(h.calls('/sync/push'), isEmpty);

      // Lần trước server đã nhận nhưng phản hồi bị mất: server trả lại kết quả đã lưu cho cùng key.
      final seenKeys = <String?>[];
      h.handler = (r) async {
        if (r.url.path.endsWith('/sync/push')) {
          seenKeys.add(r.headers['Idempotency-Key']);
          return ackPush(r, revision: 1);
        }
        return emptyPull();
      };
      h.clock.advance(const Duration(seconds: 5));
      final s2 = await h.sync.syncNow();
      expect(s2.phase, SyncPhase.idle);
      expect(seenKeys, [op['idempotency_key']]);
      op = (await h.outbox()).single;
      expect(op['state'], SyncOpState.acked.name);
      expect(await h.activities.countSaved(userId), 1);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('retry sau khi đã ack không gửi lại', () async {
      await h.recordAndSave(userId);
      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r) : emptyPull();
      await h.sync.syncNow();
      await h.sync.syncNow(manual: true);
      expect(h.calls('/sync/push').length, 1);
    });

    test('op kẹt ở sending (app bị kill) được gửi lại', () async {
      await h.recordAndSave(userId);
      await h.db.db.update('sync_outbox', {'state': 'sending'});
      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r) : emptyPull();
      await h.sync.syncNow();
      expect((await h.outbox()).single['state'], 'acked');
    });

    test('lỗi 5xx là tạm thời: giữ op, đánh dấu error với backoff', () async {
      await h.recordAndSave(userId);
      h.handler = (r) async => jsonRes({
        'error': {'code': 'internal_error', 'message': 'x'},
      }, 500);
      final s = await h.sync.syncNow();
      expect(s.phase, SyncPhase.error);
      expect(s.pending, 1);
      expect((await h.outbox()).single['last_error'], 'internal_error');
    });

    test('khách hoặc không có credential: không gọi mạng', () async {
      await h.recordAndSave('guest:22222222-2222-4222-8222-222222222222');
      h.owner = const OwnerState(ownerId: 'guest:22222222-2222-4222-8222-222222222222', isGuest: true);
      final s = await h.sync.syncNow();
      expect(s.phase, SyncPhase.signedOut);
      expect(h.requests, isEmpty);

      h.owner = const OwnerState(ownerId: userId, isGuest: false);
      await h.tokens.clear();
      expect((await h.sync.syncNow()).phase, SyncPhase.signedOut);
      expect(h.requests, isEmpty);
    });

    test('update lần sau gửi expectedRevision = revision server đã ack', () async {
      final a = await h.recordAndSave(userId);
      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r, revision: 4) : emptyPull();
      await h.sync.syncNow();
      final saved = (await h.activities.byId(userId, a.id))!;
      await h.activities.updateMetadata(saved, title: 'Evening run');
      await h.sync.syncNow();
      final second = h.calls('/sync/push').last;
      expect(firstOp(second)['expectedRevision'], 4);
    });

    test('delete chưa từng lên server (not_found) coi như xong', () async {
      final a = await h.recordAndSave(userId);
      await h.activities.deleteActivity(userId, a.id);
      h.handler = (r) async {
        if (!r.url.path.endsWith('/sync/push')) return emptyPull();
        final op = firstOp(r);
        return jsonRes({
          'results': [
            {
              'idempotencyKey': op['idempotencyKey'],
              'entity': 'activity',
              'entityId': op['entityId'],
              'status': 'rejected',
              'error': {'code': 'not_found', 'message': 'Activity not found'},
            },
          ],
        });
      };
      final s = await h.sync.syncNow();
      expect(s.pending, 0);
      expect((await h.activityRow(a.id))['deleted_at'], isNotNull);
    });
  });

  group('Track chunk (H02)', () {
    test('upload chunk có checksum, finalize rồi mới synced', () async {
      final a = await h.recordAndSave(userId, gps: true, points: 5);
      final sync = h.sync;
      final chunkBodies = <String, String>{};
      h.handler = (r) async {
        final p = r.url.path;
        if (p.endsWith('/sync/push')) return ackPush(r);
        if (p.contains('/track/chunks/')) {
          chunkBodies[p] = r.body;
          expect(r.headers['X-Checksum-Sha256'], sha256Hex(r.bodyBytes));
          return jsonRes({'seq': 0, 'sha256': sha256Hex(r.bodyBytes), 'duplicate': false}, 201);
        }
        if (p.endsWith('/track/finalize')) {
          expect(jsonDecode(r.body), {'totalChunks': 3});
          return jsonRes({'activityId': a.id, 'status': 'finalized', 'totalChunks': 3});
        }
        return emptyPull();
      };
      // 5 điểm, 2 điểm/chunk → 3 chunk.
      final small = SyncService(db: h.db, activities: h.activities, settings: h.settings, auth: h.auth, clock: h.clock, owner: () => h.owner, chunkPoints: 2);
      addTearDown(small.dispose);
      await small.syncNow();
      expect(chunkBodies.length, 3);
      final first = jsonDecode(chunkBodies.values.first) as Map;
      expect((first['segments'] as List).length, 1, reason: 'chunk đầu khai báo segment');
      expect((first['points'] as List).length, 2);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
      expect(sync, isNotNull);
    });

    test('finalize lỗi mạng → chưa synced, retry upload lại cùng bytes', () async {
      final a = await h.recordAndSave(userId, gps: true, points: 3);
      final bodies = <String>[];
      var finalizeOk = false;
      h.handler = (r) async {
        final p = r.url.path;
        if (p.endsWith('/sync/push')) return ackPush(r);
        if (p.contains('/track/chunks/')) {
          bodies.add(r.body);
          return jsonRes({'seq': 0, 'duplicate': bodies.length > 1}, bodies.length > 1 ? 200 : 201);
        }
        if (p.endsWith('/track/finalize')) {
          if (!finalizeOk) throw http.ClientException('drop');
          return jsonRes({'status': 'finalized'});
        }
        return emptyPull();
      };
      await h.sync.syncNow();
      expect((await h.activityRow(a.id))['sync_state'], SyncState.pending.name);
      finalizeOk = true;
      h.clock.advance(const Duration(minutes: 1));
      await h.sync.syncNow();
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1], reason: 'chunk tất định → cùng sha256, server nhận là duplicate');
      expect((await h.outbox()).single['state'], 'acked');
    });
  });

  group('Pull & tombstone (H03)', () {
    test('bản đã xóa local không sống lại khi pull trả upsert cũ', () async {
      final a = await h.recordAndSave(userId);
      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r, revision: 1) : emptyPull();
      await h.sync.syncNow();
      await h.activities.deleteActivity(userId, a.id);

      h.handler = (r) async {
        if (r.url.path.endsWith('/sync/push')) throw http.ClientException('offline for push');
        return emptyPull();
      };
      await h.sync.syncNow(); // push delete lỗi mạng, op còn treo

      // Lần sau: pull trả bản upsert cũ (máy khác sửa trước khi delete tới server).
      final data = {...a.toJson(), 'ownerId': userId, 'title': 'Edited elsewhere', 'revision': 2};
      // Push delete vẫn bị server từ chối tạm thời; pull vẫn chạy và trả bản upsert cũ.
      h.handler = (r) async {
        if (r.url.path.endsWith('/sync/push')) {
          // server vẫn tạm lỗi
          return jsonRes({
            'results': [
              {
                'idempotencyKey': firstOp(r)['idempotencyKey'],
                'entity': 'activity',
                'entityId': a.id,
                'status': 'rejected',
                'error': {'code': 'retry_later', 'message': 'Temporary failure, retry'},
              },
            ],
          });
        }
        return jsonRes({
          'items': [
            {'seq': 5, 'entity': 'activity', 'entityId': a.id, 'op': 'upsert', 'revision': 2, 'data': data},
          ],
          'nextCursor': '5',
          'hasMore': false,
        });
      };
      h.clock.advance(const Duration(minutes: 5));
      await h.sync.syncNow();

      final row = await h.activityRow(a.id);
      expect(row['deleted_at'], isNotNull);
      expect(row['title'], 'Morning run');
      expect(await h.activities.byId(userId, a.id), isNull);
      final cursor = await h.db.db.query('sync_cursor');
      expect(cursor.single['cursor'], '5');
    });

    test('pull delete áp tombstone và bỏ thao tác local đang treo', () async {
      final a = await h.recordAndSave(userId);
      h.handler = (r) async {
        if (r.url.path.endsWith('/sync/push')) {
          return jsonRes({
            'results': [
              {
                'idempotencyKey': firstOp(r)['idempotencyKey'],
                'entity': 'activity',
                'entityId': a.id,
                'status': 'rejected',
                'error': {'code': 'retry_later', 'message': 'x'},
              },
            ],
          });
        }
        return jsonRes({
          'items': [
            {
              'seq': 9,
              'entity': 'activity',
              'entityId': a.id,
              'op': 'delete',
              'revision': 3,
              'data': {'id': a.id, 'deletedAt': h.clock.nowMs()},
            },
          ],
          'nextCursor': '9',
          'hasMore': false,
        });
      };
      final s = await h.sync.syncNow();
      expect((await h.activityRow(a.id))['deleted_at'], isNotNull);
      expect(s.pending, 0);
      expect(await h.activities.countSaved(userId), 0);
    });

    test('pull chèn hoạt động mới từ máy khác và không ghi đè owner khác', () async {
      final other = await h.recordAndSave('guest:33333333-3333-4333-8333-333333333333');
      const newId = '44444444-4444-4444-8444-444444444444';
      h.handler = (r) async => jsonRes({
        'items': [
          {
            'seq': 1,
            'entity': 'activity',
            'entityId': newId,
            'op': 'upsert',
            'revision': 1,
            'data': {
              'id': newId,
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
            },
          },
          {
            'seq': 2,
            'entity': 'activity',
            'entityId': other.id,
            'op': 'delete',
            'revision': 2,
            'data': {'id': other.id, 'deletedAt': 5},
          },
        ],
        'nextCursor': '2',
        'hasMore': false,
      });
      await h.sync.syncNow();
      expect((await h.activities.byId(userId, newId))?.title, 'Walk');
      expect((await h.activityRow(other.id))['deleted_at'], isNull, reason: 'không chạm dữ liệu owner khác');
    });
  });

  group('Xung đột (H04)', () {
    test('409 giữ cả hai bản; Keep this device đẩy lại với revision server và key mới', () async {
      final a = await h.recordAndSave(userId);
      final server = {...a.toJson(), 'title': 'Server title', 'revision': 7};
      h.handler = (r) async {
        if (!r.url.path.endsWith('/sync/push')) return emptyPull();
        final op = firstOp(r);
        return jsonRes({
          'results': [
            {
              'idempotencyKey': op['idempotencyKey'],
              'entity': 'activity',
              'entityId': a.id,
              'status': 'conflict',
              'error': {'code': 'revision_required', 'message': 'x'},
              'server': server,
            },
          ],
        });
      };
      final s = await h.sync.syncNow();
      expect(s.conflicts, 1);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.error.name);
      final conflicts = await h.sync.conflicts();
      expect(conflicts.single.server?['title'], 'Server title');
      expect(conflicts.single.local['title'], 'Morning run');
      final oldKey = (await h.outbox()).single['idempotency_key'] as String;

      // Xung đột không tự retry.
      h.requests.clear();
      h.clock.advance(const Duration(hours: 2));
      await h.sync.syncNow(manual: true);
      expect(h.calls('/sync/push'), isEmpty);

      h.handler = (r) async => r.url.path.endsWith('/sync/push') ? ackPush(r, revision: 8) : emptyPull();
      await h.sync.resolveKeepLocal(conflicts.single);
      await h.sync.syncNow();
      final push = h.calls('/sync/push').last;
      expect(firstOp(push)['expectedRevision'], 7);
      expect(firstOp(push)['idempotencyKey'], isNot(oldKey));
      expect(await h.sync.conflicts(), isEmpty);
      expect((await h.activityRow(a.id))['sync_state'], SyncState.synced.name);
    });

    test('Use other device áp bản server vào local', () async {
      final a = await h.recordAndSave(userId);
      final server = {...a.toJson(), 'title': 'Server title', 'revision': 7};
      h.handler = (r) async {
        if (!r.url.path.endsWith('/sync/push')) return emptyPull();
        return jsonRes({
          'results': [
            {
              'idempotencyKey': firstOp(r)['idempotencyKey'],
              'entity': 'activity',
              'entityId': a.id,
              'status': 'conflict',
              'error': {'code': 'revision_conflict', 'message': 'x'},
              'server': server,
            },
          ],
        });
      };
      await h.sync.syncNow();
      final c = (await h.sync.conflicts()).single;
      await h.sync.resolveKeepServer(c);
      expect((await h.activities.byId(userId, a.id))?.title, 'Server title');
      expect(await h.sync.pendingCount(userId), 0);
    });

    test('server đã xóa (activity_deleted) → tombstone thắng, không hồi sinh', () async {
      final a = await h.recordAndSave(userId);
      h.handler = (r) async {
        if (!r.url.path.endsWith('/sync/push')) return emptyPull();
        return jsonRes({
          'results': [
            {
              'idempotencyKey': firstOp(r)['idempotencyKey'],
              'entity': 'activity',
              'entityId': a.id,
              'status': 'conflict',
              'error': {'code': 'activity_deleted', 'message': 'Activity was deleted'},
              'server': {'id': a.id, 'revision': 3, 'deletedAt': 123},
            },
          ],
        });
      };
      await h.sync.syncNow();
      expect((await h.activityRow(a.id))['deleted_at'], 123);
      expect(await h.sync.conflicts(), isEmpty);
    });
  });

  group('Ánh xạ payload', () {
    test('title rỗng → nhãn theo loại; goal free value null', () {
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
  });
}
