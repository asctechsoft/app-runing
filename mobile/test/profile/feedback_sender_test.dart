import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/application/api_client.dart';
import 'package:stride/presentation/screens_profile/help_screen.dart';

FeedbackSender _sender(FeedbackWriter w, {bool ready = true, String? uid = 'u1', Duration timeout = const Duration(seconds: 1)}) =>
    FeedbackSender(write: w, ready: () => ready, uid: () => uid, nowMs: () => 1760000000000, newId: () => 'f1', timeout: timeout);

void main() {
  test('gửi thành công → sent, document đúng hợp đồng', () async {
    String? id;
    Map<String, Object?>? data;
    final s = _sender((i, d) async {
      id = i;
      data = d;
    });
    expect(await s.send(message: 'Map froze', diagnostics: 'env=dev', appVersion: '1.0.0'), FeedbackResult.sent);
    expect(id, 'f1');
    expect(data, {'uid': 'u1', 'message': 'Map froze', 'diagnostics': 'env=dev', 'appVersion': '1.0.0', 'createdAt': 1760000000000});
  });

  test('Firebase chưa sẵn sàng hoặc chưa đăng nhập → unavailable, không ghi', () async {
    Future<void> boom(String i, Map<String, Object?> d) async => fail('không được ghi');
    expect(await _sender(boom, ready: false).send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
    expect(await _sender(boom, uid: null).send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
  });

  test('mất mạng (unavailable / quá thời gian) → unavailable để chuyển share sheet', () async {
    final offline = _sender((i, d) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    expect(await offline.send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
    final hang = _sender((i, d) => Completer<void>().future, timeout: const Duration(milliseconds: 20));
    expect(await hang.send(message: 'x', appVersion: '1'), FeedbackResult.unavailable);
  });

  test('permission-denied / quá tải → ném ApiException, không báo đã gửi', () async {
    final denied = _sender((i, d) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await expectLater(denied.send(message: 'x', appVersion: '1'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    final limited = _sender((i, d) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted'));
    await expectLater(limited.send(message: 'x', appVersion: '1'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)));
  });
}
