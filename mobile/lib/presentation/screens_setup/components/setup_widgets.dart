import 'package:flutter/material.dart';

import '../../../values/tokens.dart';
import '../../../utils/l10n.dart';

/// Thanh tiến trình 3 bước của thiết lập: Profile → Goal → Ready.
class SetupSteps extends StatelessWidget {
  const SetupSteps({super.key, required this.current});

  /// 0 = Profile, 1 = Goal, 2 = Ready.
  final int current;

  /// Khóa chuỗi (không phải chữ hiển thị) — gọi `.tr` ở nơi hiển thị.
  static const labels = ['setup_step_profile', 'setup_step_goal', 'setup_step_ready'];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'setup_step_semantic'.trArgs([current + 1, labels.length, labels[current].tr]),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < current ? StrideColors.primary : (i == current ? StrideColors.surface : StrideColors.surface),
                    border: Border.all(color: i <= current ? StrideColors.primary : StrideColors.borderControl, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: i < current
                      ? const Icon(Icons.check, size: 14, color: StrideColors.surface)
                      : Text(
                          '${i + 1}',
                          style: StrideText.caption.copyWith(color: i == current ? StrideColors.primary : StrideColors.textMuted, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 4),
                Text(labels[i].tr, style: StrideText.caption.copyWith(color: i == current ? StrideColors.primary : StrideColors.textMuted)),
              ],
            ),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18, left: 4, right: 4),
                  color: i < current ? StrideColors.primary : StrideColors.borderSubtle,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Tiêu đề + mô tả của một bước thiết lập.
class SetupHeader extends StatelessWidget {
  const SetupHeader({super.key, required this.step, required this.title, required this.subtitle});
  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: StrideSpace.s8),
      SetupSteps(current: step),
      const SizedBox(height: StrideSpace.s24),
      Semantics(header: true, child: Text(title, style: StrideText.title)),
      const SizedBox(height: StrideSpace.s8),
      Text(subtitle, style: StrideText.bodySecondary),
      const SizedBox(height: StrideSpace.s24),
    ],
  );
}
