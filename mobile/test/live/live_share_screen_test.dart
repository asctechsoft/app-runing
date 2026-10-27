import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/env.dart';
import 'package:stride/controller/live/live_share_providers.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/models/ui_models/live_share_models.dart';
import 'package:stride/presentation/screen_live/live_share_screen.dart';
import 'package:stride/repository/live_share_repository.dart';
import 'package:stride/utils/clock.dart';

void main() {
  Future<ProviderContainer> pumpScreen(WidgetTester tester, {required bool signedIn}) async {
    SharedPreferences.setMockInitialValues(signedIn ? {'user_id': 'user-1', 'user_email': 'me@example.com'} : {});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(FakeClock()),
        envProvider.overrideWithValue(const EnvConfig(env: StrideEnv.dev, tileUrlTemplate: '', tileAttribution: '', flags: FeatureFlags())),
        liveShareRepositoryProvider.overrideWithValue(LiveShareRepository(ready: () => true, firestore: () => throw UnimplementedError(), uid: () => 'user-1')),
        liveSharePreviewPositionProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/run/live-share',
      routes: [
        GoRoute(
          path: '/run',
          builder: (c, s) => const Scaffold(body: Text('run prepare')),
          routes: [GoRoute(path: 'live-share', builder: (c, s) => const LiveShareScreen())],
        ),
        GoRoute(
          path: '/auth/login',
          builder: (c, s) => const Scaffold(body: Text('login')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('khách → yêu cầu đăng nhập', (tester) async {
    await pumpScreen(tester, signedIn: false);
    expect(find.text('Sign in to share live location'), findsOneWidget);
    expect(find.text('Start sharing for this run'), findsNothing);
  });

  testWidgets('mặc định tắt; cần người xem + đồng ý mới sẵn sàng', (tester) async {
    final c = await pumpScreen(tester, signedIn: true);
    expect(find.text('Live sharing'), findsOneWidget);
    expect(c.read(liveShareConfigProvider).enabled, isFalse);
    expect(find.text('Choose who can follow this run'), findsNothing);

    await tester.ensureVisible(find.text('Live sharing'));
    await tester.tap(find.text('Live sharing'));
    await tester.pumpAndSettle();
    expect(find.text('Choose who can follow this run'), findsOneWidget);
    expect(find.text('When this run ends'), findsOneWidget);
    expect(find.text('Live location and activity status'), findsOneWidget);
    // Chưa có người xem → nút Start bị khóa.
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start sharing for this run'));
    expect(start.onPressed, isNull);

    c.read(liveShareConfigProvider.notifier).addViewer(const LiveShareViewer(userId: 'u2', label: 'Jamie'));
    await tester.pumpAndSettle();
    expect(find.text('Jamie'), findsOneWidget);

    await tester.ensureVisible(find.text('Jamie'));
    await tester.tap(find.text('Start sharing for this run'));
    await tester.pumpAndSettle();
    expect(find.text('Share your live location?'), findsOneWidget);
    await tester.tap(find.text('Share for this run'));
    await tester.pumpAndSettle();
    expect(c.read(liveShareConfigProvider).ready, isTrue);
    expect(find.text('run prepare'), findsOneWidget);
  });

  testWidgets('Cancel xóa cấu hình', (tester) async {
    final c = await pumpScreen(tester, signedIn: true);
    c.read(liveShareConfigProvider.notifier)
      ..setEnabled(true)
      ..addViewer(const LiveShareViewer(userId: 'u2', label: 'Jamie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(liveShareConfigProvider).enabled, isFalse);
    expect(c.read(liveShareConfigProvider).viewers, isEmpty);
  });
}
