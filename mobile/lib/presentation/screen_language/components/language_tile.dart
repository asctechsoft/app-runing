import 'package:asc_common/asc_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../configs/locale_config.dart';
import '../../../utils/haptics.dart';
import '../../../utils/l10n.dart';
import '../../../values/tokens.dart';

/// Danh sách ngôn ngữ dùng chung cho màn lần đầu (L19) và màn trong Hồ sơ (L05). [selected] null = "Theo hệ thống".
class LanguageList extends StatelessWidget {
  const LanguageList({super.key, required this.selected, required this.onSelectLocale, required this.onSelectSystem});

  final Locale? selected;
  final ValueChanged<Locale> onSelectLocale;
  final VoidCallback onSelectSystem;

  @override
  Widget build(BuildContext context) {
    final system = AscLocale.bestSupportedMatchFor(AscLocale.getSystemLocale());
    return Column(
      children: [
        LanguageTile(
          title: 'lang_system_default'.tr,
          subtitle: 'lang_system_default_value'.trArgs([LanguageNames.nativeName(system)]),
          icon: Icons.phone_android,
          selected: selected == null,
          onTap: onSelectSystem,
        ),
        for (final l in AppLocaleConfig.supportedLocales)
          LanguageTile(
            title: LanguageNames.nativeName(l),
            subtitle: LanguageNames.englishName(l),
            // TalkBack đọc tên ngôn ngữ bằng đúng ngôn ngữ đó.
            titleLocale: l,
            selected: selected == l,
            onTap: () => onSelectLocale(l),
          ),
      ],
    );
  }
}

/// Một dòng ngôn ngữ: cao ≥ 56, chạm cả dòng, trạng thái chọn có viền primary + dấu chọn (không chỉ dựa vào màu).
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key, required this.title, required this.subtitle, required this.selected, required this.onTap, this.icon, this.titleLocale});

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Locale? titleLocale;

  @override
  Widget build(BuildContext context) {
    final duration = StrideMotion.of(context, StrideMotion.state);
    Widget titleText = Text(title, style: StrideText.subheading, maxLines: 2, overflow: TextOverflow.ellipsis);
    final tl = titleLocale;
    if (tl != null) {
      titleText = Semantics(
        attributedLabel: AttributedString(
          title,
          attributes: [
            LocaleStringAttribute(
              range: TextRange(start: 0, end: title.length),
              locale: tl,
            ),
          ],
        ),
        excludeSemantics: true,
        child: titleText,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: StrideSpace.s8),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(StrideRadius.control),
            onTap: () {
              StrideHaptics.selection();
              onTap();
            },
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s16, vertical: StrideSpace.s12),
              decoration: BoxDecoration(
                color: selected ? StrideColors.subtle : StrideColors.surface,
                borderRadius: BorderRadius.circular(StrideRadius.control),
                border: Border.all(color: selected ? StrideColors.primary : StrideColors.borderSubtle, width: selected ? 2 : 1),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[Icon(icon, color: StrideColors.primary), const SizedBox(width: StrideSpace.s12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleText,
                        Text(subtitle, style: StrideText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: StrideSpace.s12),
                  AnimatedScale(
                    duration: duration,
                    scale: selected ? 1 : 0.9,
                    child: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? StrideColors.primary : StrideColors.borderControl,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
