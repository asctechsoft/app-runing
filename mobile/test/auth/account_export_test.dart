import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/repository/account_repository.dart';
import 'package:stride/services/application/api_client.dart';

void main() {
  group('exportJsonSafe', () {
    test('Timestamp → ms, GeoPoint → lat/lon, đệ quy qua Map/List', () {
      final out = exportJsonSafe({
        'at': Timestamp.fromMillisecondsSinceEpoch(1234),
        'p': const GeoPoint(1.5, 2.5),
        'list': [Timestamp.fromMillisecondsSinceEpoch(9), 3],
      });
      expect(out, {
        'at': 1234,
        'p': {'lat': 1.5, 'lon': 2.5},
        'list': [9, 3],
      });
      expect(() => jsonEncode(out), returnsNormally);
    });
  });

  group('buildExportMap', () {
    test('gom user/goals/activities, giải mã chunk thành points, không còn Timestamp', () {
      final map = buildExportMap(
        uid: 'u1',
        exportedAt: 100,
        user: {'email': 'a@b.co', 'createdAt': 5},
        goals: [
          {'id': 'g1', 'type': 'steps', 'value': 8000},
        ],
        activities: [
          {
            'id': 'a1',
            'type': 'run',
            'serverUpdatedAt': Timestamp.fromMillisecondsSinceEpoch(77),
            'trackChunks': [
              {'seq': 0, 'count': 2, 'sha256': 'x', 'json': '[{"t":1},{"t":2}]'},
              {'seq': 1, 'count': 1, 'sha256': 'y', 'json': 'not json'},
            ],
          },
        ],
      );
      expect(map['uid'], 'u1');
      expect(map['exportedAt'], 100);
      expect((map['goals'] as List).single, containsPair('value', 8000));
      final act = (map['activities'] as List).single as Map;
      expect(act['serverUpdatedAt'], 77);
      final chunks = act['trackChunks'] as List;
      expect((chunks[0] as Map)['points'], [
        {'t': 1},
        {'t': 2},
      ]);
      expect((chunks[1] as Map)['raw'], 'not json', reason: 'chunk hỏng giữ nguyên chuỗi gốc, không bịa dữ liệu');
      expect(() => jsonEncode(map), returnsNormally);
    });

    test('tài khoản trống vẫn ra export hợp lệ', () {
      final map = buildExportMap(uid: 'u', exportedAt: 1, user: null, goals: const [], activities: const []);
      expect(map['user'], isNull);
      expect(map['activities'], isEmpty);
    });
  });

  group('AccountJob', () {
    test('trạng thái', () {
      const ok = AccountJob(id: '1', kind: 'export', status: 'succeeded');
      expect(ok.succeeded, isTrue);
      expect(ok.isOpen, isFalse);
      expect(ok.isExpired(10), isFalse);
      expect(AccountJob.fromJson({'id': '2', 'status': 'running'}).isOpen, isTrue);
    });
  });

  group('accountErrorMessage', () {
    test('map code Firebase', () {
      expect(accountErrorMessage(ApiException(401, 'invalid_credentials', 'x')), 'That password is incorrect.');
      expect(accountErrorMessage(ApiException(401, 'reauth_required', 'x')), contains('Confirm your password'));
      expect(accountErrorMessage(ApiException(429, 'rate_limited', 'x')), contains('Too many attempts'));
      expect(accountErrorMessage(ApiException(403, 'account_disabled', 'x')), contains('deleted'));
      expect(accountErrorMessage(ApiException(0, 'network', 'x')), contains("You're offline"));
      expect(accountErrorMessage(FirebaseAuthException(code: 'wrong-password')), 'That password is incorrect.');
      expect(accountErrorMessage(ApiException(500, 'x', 'stack')), 'Something went wrong on our side. Please try again.');
    });
  });
}
