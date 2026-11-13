import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/application/ongoing_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('stride/ongoing');
  late List<MethodCall> calls;
  late OngoingNotificationService svc;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return null;
    });
    svc = OngoingNotificationService();
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('bước: lần đầu start, đổi nội dung thì update, giống hệt thì không gửi lại, hide thì stop', () async {
    await svc.showSteps(channel: 'c', title: '29 steps', text: 'goal', progress: 1);
    await svc.showSteps(channel: 'c', title: '29 steps', text: 'goal', progress: 1);
    await svc.showSteps(channel: 'c', title: '30 steps', text: 'goal', progress: 1);
    await svc.hideSteps();
    await svc.hideSteps();
    expect(calls.map((c) => c.method), ['startSteps', 'updateSteps', 'stopSteps']);
  });

  test('thẻ chạy: chỉ gửi lại khi chữ/trạng thái đổi, không gửi vì thời gian tăng; hide chỉ khi đang hiện', () async {
    Future<void> run({required int ms, required bool running, String distance = '0.00 km'}) => svc.showRun(
      channel: 'c',
      title: 'Recording',
      subtitle: 'Run',
      timeLabel: 'Time',
      distanceLabel: 'Distance',
      distance: distance,
      movingMs: ms,
      running: running,
    );
    await svc.hideRun(); // chưa hiện: không gọi native
    await run(ms: 1000, running: true);
    await run(ms: 5000, running: true);
    await run(ms: 6000, running: true, distance: '0.01 km');
    await run(ms: 7000, running: false, distance: '0.01 km');
    await svc.hideRun();
    expect(calls.map((c) => c.method), ['showRun', 'showRun', 'showRun', 'hideRun']);
    expect(calls[1].arguments['distance'], '0.01 km');
    expect(calls[2].arguments['running'], false);
  });
}
