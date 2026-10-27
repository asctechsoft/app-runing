import 'package:asc_common/asc_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stride/configs/pref_const.dart';
import 'package:stride/controller/language/language_controller.dart';
import 'package:stride/controller/providers.dart';
import 'package:stride/main.dart';
import 'package:stride/presentation/screen_language/components/language_tile.dart';
import 'package:stride/presentation/screen_language/language_selection_screen.dart';
import 'package:stride/services/application/reminder_scheduler.dart';
import 'package:stride/utils/l10n.dart';
import 'package:stride/values/router.dart';
import 'package:stride/values/routes.dart';

const _en = Locale('en', 'US');
const _vi = Locale('vi', 'VN');

/// L20: màn chọn ngôn ngữ lần đầu + L06 đổi ngôn ngữ cập nhật giao diện ngay.
void main() {
  setUpAll(() async {
    // Nạp sẵn bản vi để thao tác chọn trong test không phải chờ đọc asset.
    await AscLocale.setAppLocale(_vi);
    await AscLocale.setAppLocale(_en);
  });

  tearDown(() async {
    await AscLocale.setAppLocale(_en);
    Intl.defaultLocale = 'en_US';
  });

  Future<SharedPreferences> prefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  bool selectedTitle(WidgetTester tester, String title) => tester.widget<LanguageTile>(find.widgetWithText(LanguageTile, title)).selected;

  Future<void> pumpFirstRun(WidgetTester tester, SharedPreferences p, {double textScale = 1}) async {
    final router = GoRouter(
      initialLocation: Routes.language,
      routes: [
        GoRoute(path: Routes.language, builder: (_, _) => const LanguageSelectionScreen()),
        for (final r in [Routes.onboarding, Routes.welcome, Routes.home])
          GoRoute(
            path: r,
            builder: (_, _) => Scaffold(body: Text('at:$r')),
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(p), remindersSyncProvider.overrideWithValue(() async {})],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mặc định tô sẵn ngôn ngữ của máy; có dòng "Theo hệ thống"; nút Tiếp tục luôn bật', (tester) async {
    await pumpFirstRun(tester, await prefs());
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(selectedTitle(tester, 'English'), isTrue);
    expect(selectedTitle(tester, 'Tiếng Việt'), isFalse);
    expect(find.text('Continue'), findsOneWidget);
    // T01: vùng chạm ≥ 48 (Android) / 44 (iOS); T08: mọi vùng chạm có nhãn.
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('T10: cỡ chữ 200% trên máy nhỏ (360 × 640) không tràn, nút Tiếp tục vẫn thấy', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFirstRun(tester, await prefs(), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Continue').hitTestable(), findsOneWidget);
  });

  testWidgets('chọn Tiếng Việt → chữ đổi ngay, chưa rời màn; dòng phụ tiếng Anh hiện', (tester) async {
    final p = await prefs();
    await pumpFirstRun(tester, p);
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn ngôn ngữ'), findsOneWidget);
    expect(find.text('Choose your language'), findsOneWidget, reason: 'dòng phụ cố định tiếng Anh');
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(selectedTitle(tester, 'Tiếng Việt'), isTrue);
    expect(find.textContaining('at:'), findsNothing, reason: 'không tự chuyển màn khi chạm một dòng');
    expect(p.getBool(PrefConst.languageChosen), isNull, reason: 'thoát app lúc này → lần sau vẫn hỏi');
    expect(Intl.defaultLocale, 'vi_VN');
  });

  testWidgets('Tiếp tục → ghi cờ languageChosen và sang onboarding', (tester) async {
    final p = await prefs();
    await pumpFirstRun(tester, p);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(p.getBool(PrefConst.languageChosen), isTrue);
    expect(find.text('at:${Routes.onboarding}'), findsOneWidget);
  });

  testWidgets('"Theo hệ thống" bật cờ followSystem; chọn ngôn ngữ cụ thể thì tắt', (tester) async {
    final p = await prefs();
    await pumpFirstRun(tester, p);
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(p.getBool(PrefConst.followSystemLanguage), isTrue);
    expect(selectedTitle(tester, 'System default'), isTrue);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(p.getBool(PrefConst.followSystemLanguage), isFalse);
    expect(selectedTitle(tester, 'English'), isTrue);
  });

  test('L14: đổi ngôn ngữ → lên lịch nhắc nhở lại (một lần); chọn lại đúng ngôn ngữ hiện tại thì không', () async {
    final p = await prefs();
    var resyncs = 0;
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p), remindersSyncProvider.overrideWithValue(() async => resyncs++)]);
    addTearDown(c.dispose);
    await c.read(languageProvider.notifier).select(_en);
    expect(resyncs, 0);
    await c.read(languageProvider.notifier).select(_vi);
    await pumpEventQueue();
    expect(resyncs, 1);
  });

  testWidgets('L06: StrideApp dựng lại cả màn không theo dõi provider khi đổi ngôn ngữ, giữ nguyên route', (tester) async {
    final p = await prefs();
    final router = GoRouter(
      initialLocation: '/plain',
      routes: [GoRoute(path: '/plain', builder: (_, _) => const _PlainScreen())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(p), routerProvider.overrideWithValue(router), remindersSyncProvider.overrideWithValue(() async {})],
        child: const StrideApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(_PlainScreen)));
    await tester.runAsync(() => container.read(languageProvider.notifier).select(_vi));
    await tester.pumpAndSettle();
    expect(find.text('Ngôn ngữ'), findsOneWidget);
    expect(find.byType(_PlainScreen), findsOneWidget);
    expect(Localizations.localeOf(tester.element(find.byType(_PlainScreen))), _vi);
  });
}

/// Màn "thường": chỉ gọi `.tr`, không watch provider nào.
class _PlainScreen extends StatelessWidget {
  const _PlainScreen();

  @override
  Widget build(BuildContext context) => Scaffold(body: Text('lang_settings_title'.tr));
}
