import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/utils/analytics.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/services/application/app_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Analytics', () {
    late List<(String, Map<String, Object>?)> sent;

    setUp(() {
      sent = [];
      Analytics.sink = (name, params) => sent.add((name, params));
    });
    tearDown(Analytics.resetSink);

    test('tên event hợp lệ theo luật Firebase, chặn tiền tố dành riêng', () {
      expect(Analytics.isValidEventName('app_open'), isTrue);
      expect(Analytics.isValidEventName('1bad'), isFalse);
      expect(Analytics.isValidEventName('has space'), isFalse);
      expect(Analytics.isValidEventName('firebase_x'), isFalse);
      expect(Analytics.isValidEventName('app_background'), isFalse); // tên dành riêng của Firebase
      expect(Analytics.isValidEventName('stride_background'), isTrue);
      expect(Analytics.isValidEventName('a' * 41), isFalse);
    });

    test('appOpen/screenView/foreground-background gửi đúng event với tham số chuỗi', () {
      Analytics.appOpen(firstOpen: true);
      Analytics.screenView('/home/activity/:id');
      Analytics.appForeground();
      Analytics.appBackground();
      expect(sent.map((e) => e.$1), ['app_open', 'screen_view', 'stride_foreground', 'stride_background']);
      expect(sent[0].$2, {'first_open': 'true'});
      expect(sent[1].$2, {'firebase_screen': '/home/activity/:id'});
      expect(sent.every((e) => e.$2 == null || e.$2!.values.every((v) => v is String)), isTrue);
    });

    test('không có Firebase vẫn không ném lỗi (offline-first)', () {
      Analytics.resetSink();
      expect(() => Analytics.appOpen(firstOpen: false), returnsNormally);
    });
  });

  group('AppLifecycle', () {
    test('resumed gọi hook mỗi lần; foreground/background chỉ ghi khi chuyển trạng thái thật', () {
      final sent = <String>[];
      Analytics.sink = (name, _) => sent.add(name);
      addTearDown(Analytics.resetSink);
      var resumed = 0;
      var paused = 0;
      final lifecycle = AppLifecycle(onResumed: [() => resumed++], onPaused: [() => paused++]);

      // Mở lạnh: đã ở foreground → resumed chỉ chạy hook (làm mới quyền), không log app_foreground.
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(resumed, 1);
      expect(sent, <String>[]);

      // Hộp thoại quyền: inactive → resumed, vẫn chạy hook nhưng không phải lần quay lại foreground.
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(resumed, 2);
      expect(sent, <String>[]);

      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(lifecycle.isForeground.value, isFalse);
      expect(paused, 1);
      expect(sent, ['stride_background']);

      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lifecycle.isForeground.value, isTrue);
      expect(lifecycle.lastResumedAt, isNotNull);
      expect(resumed, 3);
      expect(sent, ['stride_background', 'stride_foreground']);
      lifecycle.isForeground.dispose();
    });
  });

  group('EnvConfig', () {
    test('không truyền STRIDE_ENV và không flavor → dev; chỉ production khi flavor product', () {
      final env = EnvConfig.fromEnvironment();
      expect(env.env, StrideEnv.dev);
      expect(env.isProduction, isFalse);
    });
  });
}
