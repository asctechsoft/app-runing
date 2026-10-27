import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/repository/activity_repository.dart';
import 'package:stride/repository/device_repository.dart';
import 'package:stride/services/application/heart_rate_parser.dart';
import 'package:stride/services/application/heart_rate_plugin.dart';
import 'package:stride/services/application/heart_rate_transport.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/utils/clock.dart';

import 'fake_transport.dart';

/// sqflite ffi chạy ở isolate riêng → cần chờ thời gian thật ngắn thay vì một microtask.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late FakeClock clock;
  late DeviceRepository devices;
  late ActivityRepository activities;
  late FakeTransport transport;
  late List<HeartRateStatus> statuses;
  late HeartRatePlugin plugin;

  setUp(() async {
    db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi);
    clock = FakeClock(DateTime(2026, 10, 17, 7).millisecondsSinceEpoch);
    devices = DeviceRepository(db, clock);
    activities = ActivityRepository(db, clock);
    transport = FakeTransport();
    statuses = [];
    plugin = HeartRatePlugin(repository: devices, transport: transport, clock: clock, onStatus: statuses.add, reconnectDelay: const Duration(hours: 1));
  });

  tearDown(() => db.close());

  Future<Activity> session(String owner) async {
    final (a, _) = await activities.createSession(ownerId: owner, type: ActivityType.run, goal: const RunGoal.free(), monoMs: 0, tzId: 'UTC', tzOffsetMin: 0);
    return a;
  }

  test('không có thiết bị → unavailable, không kết nối', () async {
    final a = await session('o');
    await plugin.onSessionStart(a);
    expect(transport.connectCalls, isEmpty);
    expect(plugin.status.phase, HeartRatePhase.unavailable);
  });

  test('ghi mẫu có timestamp thật, giữ khoảng trống khi mất cảm biến, dừng khi kết thúc', () async {
    final d = await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    final a = await session('o');
    plugin = HeartRatePlugin(
      repository: devices,
      transport: transport,
      clock: clock,
      onStatus: statuses.add,
      reconnectDelay: const Duration(milliseconds: 400),
    );
    await plugin.onSessionStart(a);
    expect(transport.connectCalls, ['R1']);
    expect(plugin.status.phase, HeartRatePhase.connected);
    final c = transport.connections.single;

    final t0 = clock.nowMs();
    c.emit(120);
    await pump();
    clock.advance(const Duration(seconds: 1));
    c.emit(0, contact: SensorContact.notDetected); // không tiếp xúc → bỏ
    await pump();
    clock.advance(const Duration(seconds: 1));
    c.emit(125);
    await pump();

    // Mất cảm biến 30 s: phiên vẫn chạy, trạng thái lost giữ bpm cuối.
    c.loseSignal();
    await pump();
    await pump();
    expect(plugin.status.phase, HeartRatePhase.lost);
    expect(plugin.status.lastBpm, 125);
    clock.advance(const Duration(seconds: 30));

    // Plugin tự kết nối lại → mẫu tiếp theo cách 32 s, khoảng giữa không được nội suy.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(transport.connectCalls, ['R1', 'R1']);
    expect(plugin.status.phase, HeartRatePhase.connected);
    final c2 = transport.connections.last;
    c2.emit(128);
    await pump();

    final s1 = await devices.samples(a.id);
    expect(s1.map((s) => s.bpm), [120, 125, 128]);
    expect(s1.map((s) => s.t), [t0, t0 + 2000, t0 + 32000]);
    expect(s1.every((s) => s.deviceId == d.id), isTrue);

    await plugin.onSessionEnd(a, discarded: false);
    expect(plugin.status.phase, HeartRatePhase.unavailable);
    expect(c2.disconnected, isTrue);
    // Sau khi kết thúc không ghi thêm.
    expect((await devices.samples(a.id)).length, 3);
  });

  test('onSessionEnd ngắt kết nối cảm biến và bỏ mẫu đến sau', () async {
    await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    final a = await session('o');
    await plugin.onSessionStart(a);
    final c = transport.connections.single;
    c.emit(130);
    await pump();
    await plugin.onSessionEnd(a, discarded: true);
    expect(c.disconnected, isTrue);
    expect((await devices.samples(a.id)).map((s) => s.bpm), [130]);
  });

  test('thiết bị đã revoke không được dùng; chọn thiết bị gần nhất chưa revoke', () async {
    final old = await devices.savePaired(ownerId: 'o', name: 'Old', remoteId: 'R-old');
    clock.advance(const Duration(minutes: 1));
    final recent = await devices.savePaired(ownerId: 'o', name: 'Recent', remoteId: 'R-new');
    await devices.revoke(recent.id);
    final a = await session('o');
    await plugin.onSessionStart(a);
    expect(transport.connectCalls, ['R-old']);
    expect(plugin.status.deviceName, old.name);

    await plugin.onSessionEnd(a, discarded: false);
    await devices.revoke(old.id);
    transport.connectCalls.clear();
    final b = await session('o2');
    await plugin.onSessionStart(b);
    expect(transport.connectCalls, isEmpty);
  });

  test('Forget giữa phiên → ngừng nhập ngay', () async {
    final d = await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    final a = await session('o');
    await plugin.onSessionStart(a);
    final c = transport.connections.single;
    c.emit(110);
    await pump();
    await devices.revoke(d.id);
    await pump();
    await pump();
    expect(c.disconnected, isTrue);
    expect(plugin.status.phase, HeartRatePhase.unavailable);
    expect((await devices.samples(a.id)).map((s) => s.bpm), [110]);
    await plugin.onSessionEnd(a, discarded: false);
  });

  test('kết nối lỗi lúc bắt đầu → lost, phiên vẫn tiếp tục', () async {
    await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    transport.failWith = HeartRateConnectException('timeout');
    final a = await session('o');
    await plugin.onSessionStart(a);
    expect(plugin.status.phase, HeartRatePhase.lost);
    expect(plugin.status.lastBpm, isNull);
    await plugin.onSessionEnd(a, discarded: false);
  });

  test('X40: kết thúc phiên không treo khi cancel() stream đo của cảm biến không bao giờ trả lời', () async {
    await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    transport.hangOnCancel = true;
    final a = await session('o');
    await plugin.onSessionStart(a);
    expect(plugin.status.phase, HeartRatePhase.connected);
    await plugin.onSessionEnd(a, discarded: false).timeout(const Duration(seconds: 10));
    expect(plugin.status.phase, HeartRatePhase.unavailable);
    expect(transport.connections.single.disconnected, isTrue);
  });

  test('ghép lại cùng remoteId dùng lại bản ghi và bỏ revoke', () async {
    final d = await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    await devices.revoke(d.id);
    expect(await devices.list('o'), isEmpty);
    final again = await devices.savePaired(ownerId: 'o', name: 'Strap', remoteId: 'R1');
    expect(again.id, d.id);
    expect(again.revoked, isFalse);
    expect((await devices.list('o', includeRevoked: true)).length, 1);
  });
}
