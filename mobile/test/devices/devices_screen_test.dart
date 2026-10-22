import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stride/services/storage/app_database.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/utils/clock.dart';
import 'package:stride/controller/devices/devices_providers.dart';
import 'package:stride/presentation/screen_devices/devices_screen.dart';
import 'package:stride/services/application/heart_rate_transport.dart';

import 'fake_transport.dart';

void main() {
  sqfliteFfiInit();

  Future<(AppDatabase, FakeTransport, FakePermissionCoordinator)> pumpScreen(
    WidgetTester tester, {
    PermStatus bluetooth = PermStatus.granted,
    BleAdapter adapter = BleAdapter.on,
  }) async {
    SharedPreferences.setMockInitialValues({'user_id': 'user-1', 'user_email': 'me@example.com'});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(() => AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    addTearDown(() => tester.runAsync(db.close));
    final transport = FakeTransport()..adapter = adapter;
    final perms = FakePermissionCoordinator({PermKind.bluetooth: bluetooth});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(perms),
          clockProvider.overrideWithValue(FakeClock()),
          heartRateTransportProvider.overrideWithValue(transport),
        ],
        child: const MaterialApp(home: DevicesScreen()),
      ),
    );
    await settle(tester);
    return (db, transport, perms);
  }

  testWidgets('giải thích ma trận hỗ trợ, không tên hãng; quyền bị từ chối → Allow Bluetooth', (tester) async {
    final (_, _, perms) = await pumpScreen(tester, bluetooth: PermStatus.denied);
    expect(find.text('Bluetooth heart rate sensors'), findsOneWidget);
    expect(find.text('Allow Bluetooth'), findsWidgets);
    expect(find.text('Scan for sensors'), findsNothing);
    perms.statuses[PermKind.bluetooth] = PermStatus.unknown;
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Allow Bluetooth'));
    await tester.tap(find.widgetWithText(FilledButton, 'Allow Bluetooth'));
    await settle(tester);
    expect(find.text('Scan for sensors'), findsOneWidget);
  });

  testWidgets('quyền bị chặn → mở cài đặt', (tester) async {
    await pumpScreen(tester, bluetooth: PermStatus.blocked);
    expect(find.text('Bluetooth access is off'), findsOneWidget);
    expect(find.text('Open phone settings'), findsOneWidget);
  });

  testWidgets('Bluetooth tắt → banner', (tester) async {
    await pumpScreen(tester, adapter: BleAdapter.off);
    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Scan for sensors'), findsNothing);
  });

  testWidgets('quét → kết nối → lưu thiết bị và hiện bpm', (tester) async {
    final (db, transport, _) = await pumpScreen(tester);
    transport.scanResult = const [FoundSensor(remoteId: 'AA:BB:CC:DD:EE:F1', advertisedName: '')];
    await tester.ensureVisible(find.text('Scan for sensors'));
    await tester.tap(find.text('Scan for sensors'));
    await settle(tester);
    expect(find.text('Heart rate sensor EEF1'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Connect'));
    await tester.tap(find.widgetWithText(TextButton, 'Connect'));
    await settle(tester);
    expect(transport.connectCalls, ['AA:BB:CC:DD:EE:F1']);
    final rows = (await tester.runAsync(() => db.db.query('devices')))!;
    expect(rows.single['owner_id'], 'user-1');
    expect(rows.single['kind'], 'bleHeartRate');
    expect(rows.single['remote_id'], 'AA:BB:CC:DD:EE:F1');
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('— bpm', findRichText: true), findsOneWidget);

    transport.connections.single.emit(142);
    await settle(tester);
    expect(find.text('142 bpm', findRichText: true), findsOneWidget);

    // Mất kết nối → trạng thái Disconnected + Reconnect.
    transport.connections.single.loseSignal();
    await settle(tester);
    expect(find.text('Reconnect'), findsOneWidget);
  });

  testWidgets('kết nối timeout → lỗi có Retry', (tester) async {
    final (_, transport, _) = await pumpScreen(tester);
    transport.scanResult = const [FoundSensor(remoteId: 'R1', advertisedName: 'Strap')];
    transport.failWith = HeartRateConnectException('timeout');
    await tester.ensureVisible(find.text('Scan for sensors'));
    await tester.tap(find.text('Scan for sensors'));
    await settle(tester);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Connect'));
    await tester.tap(find.widgetWithText(TextButton, 'Connect'));
    await settle(tester);
    expect(find.textContaining('Couldn\'t connect to Strap'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

/// sqflite ffi hoàn tất ở isolate khác → chờ thời gian thật rồi pump.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}
