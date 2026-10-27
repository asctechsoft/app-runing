import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/services/application/app_lifecycle.dart';
import 'package:stride/utils/analytics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Analytics', () {
    late List<(String, Map<String, Object>?)> sent;

    setUp(() {
      sent = [];
      Analytics.sink = (name, params) => sent.add((name, params));
    });
    tearDown(Analytics.resetSink);

    test('X11: tắt đồng ý chia sẻ dữ liệu → không gửi event nào; bật lại thì gửi', () {
      addTearDown(() => Analytics.collectionEnabled = true);
      Analytics.collectionEnabled = false;
      Analytics.appOpen(firstOpen: false);
      Analytics.screenView('/home');
      expect(sent, isEmpty);
      Analytics.collectionEnabled = true;
      Analytics.appForeground();
      expect(sent.map((e) => e.$1), ['stride_foreground']);
    });

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

    test('TM76: event nhóm hợp lệ, tham số chuỗi, không id; mốc chuỗi chỉ khi vượt qua', () {
      Analytics.clubCreate(visibility: 'private');
      Analytics.clubInviteShare();
      Analytics.clubJoin(via: 'invite_code');
      Analytics.challengeJoin(metric: 'distance');
      Analytics.leaderboardView();
      Analytics.streakMilestone(days: 7);
      expect(sent.map((e) => e.$1), ['club_create', 'club_invite_share', 'club_join', 'challenge_join', 'leaderboard_view', 'streak_milestone']);
      expect(sent.map((e) => e.$1).every(Analytics.isValidEventName), isTrue);
      expect(sent.last.$2, {'days': '7'});
      expect(Analytics.crossedStreakMilestone(6, 7), 7);
      expect(Analytics.crossedStreakMilestone(7, 8), isNull);
      expect(Analytics.crossedStreakMilestone(2, 15), 14);
      expect(Analytics.crossedStreakMilestone(5, 0), isNull);
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

    test('nguồn tile mặc định luôn có nguồn dự phòng khác nguồn chính (X41: mạng chặn openstreetmap.org)', () {
      final env = EnvConfig.fromEnvironment();
      expect(env.tileUrlTemplate, contains('{z}/{x}/{y}'));
      expect(env.tileFallbackUrlTemplate, contains('{z}/{x}/{y}'));
      expect(env.tileFallbackUrlTemplate, isNot(env.tileUrlTemplate));
    });
  });
}
