import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/language/language_controller.dart';
import '../../controller/providers.dart';
import '../../utils/analytics.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../screen_startup/startup_screen.dart';
import 'components/language_tile.dart';

/// Chọn ngôn ngữ (L19 lần đầu sau splash, L05 trong Hồ sơ). Chạm một dòng → giao diện đổi ngay (xem trước, L06).
/// Lần đầu: chỉ sang onboarding khi bấm "Tiếp tục" (chốt 2026-10-23); thoát app trước đó → lần mở sau quay lại đây.
/// Offline-first: chỉ nạp bản dịch từ asset, không gọi mạng.
class LanguageSelectionScreen extends ConsumerStatefulWidget {
  const LanguageSelectionScreen({super.key, this.firstRun = true});

  final bool firstRun;

  @override
  ConsumerState<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends ConsumerState<LanguageSelectionScreen> {
  final _guard = OnceGuard();

  String get _source => widget.firstRun ? 'first_run' : 'settings';

  @override
  void initState() {
    super.initState();
    Analytics.languageScreenView(source: _source);
  }

  Future<void> _selectLocale(Locale l) async {
    await ref.read(languageProvider.notifier).select(l);
    Analytics.languageSelect(code: l.toString(), source: _source);
  }

  Future<void> _selectSystem() async {
    await ref.read(languageProvider.notifier).useSystemDefault();
    Analytics.languageSelect(code: 'system', source: 'system_default');
  }

  Future<void> _continue() => _guard.run(() async {
    await ref.read(languageProvider.notifier).confirmFirstRun();
    if (!mounted) return;
    final owner = ref.read(ownerProvider);
    context.go(decideStartRoute(owner: owner, languageChosen: true));
  });

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final list = LanguageList(selected: lang.followSystem ? null : lang.locale, onSelectLocale: _selectLocale, onSelectSystem: _selectSystem);

    if (!widget.firstRun) {
      return StrideScreen(
        title: 'lang_settings_title'.tr,
        body: Padding(
          padding: const EdgeInsets.only(top: StrideSpace.s16),
          child: list,
        ),
      );
    }

    final showHint = lang.locale.languageCode != 'en';
    return Scaffold(
      backgroundColor: StrideColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(StrideScreen.gutterOf(context), StrideSpace.s32, StrideScreen.gutterOf(context), StrideSpace.s16),
                    children: [
                      const Icon(Icons.language, size: 40, color: StrideColors.primary),
                      const SizedBox(height: StrideSpace.s16),
                      Semantics(header: true, child: Text('lang_title'.tr, style: StrideText.title)),
                      // Dòng phụ cố định tiếng Anh cho người không đọc được ngôn ngữ đang hiển thị.
                      if (showHint) Text('lang_title_hint'.tr, style: StrideText.bodySecondary),
                      const SizedBox(height: StrideSpace.s8),
                      Text('lang_subtitle'.tr, style: StrideText.bodySecondary),
                      const SizedBox(height: StrideSpace.s24),
                      list,
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(StrideScreen.gutterOf(context), StrideSpace.s8, StrideScreen.gutterOf(context), StrideSpace.s16),
                  // Luôn bật: ngôn ngữ của máy đã được chọn sẵn.
                  child: PrimaryButton(label: 'lang_continue'.tr, trailingIcon: Icons.arrow_forward, onPressed: _continue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
