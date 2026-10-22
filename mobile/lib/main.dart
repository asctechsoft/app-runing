import 'package:asc_common/asc_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/base/locale_config.dart';
import 'core/base/stride_base.dart';
import 'core/db/app_database.dart';
import 'core/firebase/firebase_providers.dart';
import 'core/lifecycle/app_lifecycle.dart';
import 'core/logging/logger.dart';
import 'core/providers.dart';
import 'core/run_plugins.dart';
import 'features/auth/google_sign_in_service.dart';
import 'features/devices/devices_providers.dart';
import 'features/live/live_share_providers.dart';
import 'core/theme/stride_theme.dart';

/// Luồng khởi động (offline-first: chỉ chạm tài nguyên cục bộ trước khi vào app, không chờ mạng — F01):
/// 1. binding + cấu hình locale  2. SharedPreferences + SQLite  3. base dùng chung (Firebase/App Check/Crashlytics, RC chạy nền)
/// 4. nối bộ bắt lỗi  5. nạp bản dịch XML  6. `runApp` → StartupScreen quyết định màn đầu.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLocaleConfig.configure();

  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();

  // Trước base để lỗi trong lúc khởi động vẫn được ghi; Crashlytics (nếu lên) sẽ ghi đè rồi ta bọc lại ở dưới.
  FlutterError.onError = (d) => StrideLog.e('flutter', d.exception, d.stack);
  PlatformDispatcher.instance.onError = (error, stack) {
    StrideLog.e('platform', error, stack);
    return true;
  };
  final googleReady = await StrideBase.start();
  _chainErrorLogging();

  await AppLocaleConfig.ensureConfigured();
  await AscLocale.loadTranslations();

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        googleSignInAvailableProvider.overrideWithValue(googleReady),
        firebaseReadyProvider.overrideWithValue(googleReady),
        flagsProvider.overrideWith((ref) => ref.watch(envProvider).flags.copyWith(authGoogle: googleReady)),
        // Ghép plugin mở rộng vào engine phiên chạy (L03 nhịp tim, M07 live sharing); provider trả null khi flag tắt.
        runPluginsProvider.overrideWith((ref) => [?ref.watch(heartRateRunPluginProvider), ?ref.watch(liveShareRunPluginProvider)]),
      ],
      child: const StrideApp(),
    ),
  );
}

/// `DspCrashlytics.install` thay `FlutterError.onError`/`PlatformDispatcher.onError` bằng bản chỉ gửi Crashlytics.
/// Bọc lại để vẫn ghi `StrideLog` (có che dữ liệu nhạy cảm) song song — không mất log cục bộ khi Firebase lên.
void _chainErrorLogging() {
  final flutterHandler = FlutterError.onError;
  FlutterError.onError = (d) {
    StrideLog.e('flutter', d.exception, d.stack);
    flutterHandler?.call(d);
  };
  final platformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    StrideLog.e('platform', error, stack);
    return platformHandler?.call(error, stack) ?? true;
  };
}

class StrideApp extends ConsumerStatefulWidget {
  const StrideApp({super.key});

  @override
  ConsumerState<StrideApp> createState() => _StrideAppState();
}

class _StrideAppState extends ConsumerState<StrideApp> {
  late final AppLifecycle _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycle(
      // Kiểm tra lại quyền khi quay về app, không dựa giá trị đã lưu (E05).
      onResumed: [() => ref.read(permissionsProvider).refresh()],
    )..attach();
  }

  @override
  void dispose() {
    _lifecycle.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(envProvider);
    return MaterialApp.router(
      title: 'STRIDE',
      debugShowCheckedModeBanner: false,
      theme: buildStrideTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: AscLocale.getAppLocale(),
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocaleConfig.supportedLocales,
      // Chỉ báo môi trường không phải production (B03).
      builder: (context, child) => env.isProduction ? child! : Banner(message: env.env.name.toUpperCase(), location: BannerLocation.topEnd, child: child!),
    );
  }
}
