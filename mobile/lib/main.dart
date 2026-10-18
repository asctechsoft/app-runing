import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/db/app_database.dart';
import 'core/logging/logger.dart';
import 'core/providers.dart';
import 'core/run_plugins.dart';
import 'features/devices/devices_providers.dart';
import 'features/live/live_share_providers.dart';
import 'core/theme/stride_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-first: chỉ mở tài nguyên cục bộ trước khi vào app; không chờ mạng (F01).
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();
  FlutterError.onError = (d) => StrideLog.e('flutter', d.exception, d.stack);
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        // Ghép plugin mở rộng vào engine phiên chạy (L03 nhịp tim, M07 live sharing); provider trả null khi flag tắt.
        runPluginsProvider.overrideWith((ref) => [?ref.watch(heartRateRunPluginProvider), ?ref.watch(liveShareRunPluginProvider)]),
      ],
      child: const StrideApp(),
    ),
  );
}

class StrideApp extends ConsumerStatefulWidget {
  const StrideApp({super.key});

  @override
  ConsumerState<StrideApp> createState() => _StrideAppState();
}

class _StrideAppState extends ConsumerState<StrideApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kiểm tra lại quyền khi quay về app, không dựa giá trị đã lưu (E05).
    if (state == AppLifecycleState.resumed) ref.read(permissionsProvider).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(envProvider);
    return MaterialApp.router(
      title: 'STRIDE',
      debugShowCheckedModeBanner: false,
      theme: buildStrideTheme(),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: const [Locale('en', 'US'), Locale('vi', 'VN')],
      // Chỉ báo môi trường không phải production (B03).
      builder: (context, child) => env.isProduction ? child! : Banner(message: env.env.name.toUpperCase(), location: BannerLocation.topEnd, child: child!),
    );
  }
}
