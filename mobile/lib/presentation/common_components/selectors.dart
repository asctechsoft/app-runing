import 'package:flutter/material.dart';

import '../../values/tokens.dart';

/// Segmented control: container subtle, selected primary + chữ trắng, cao ≥ 48.
class StrideSegmented<T> extends StatelessWidget {
  const StrideSegmented({super.key, required this.values, required this.selected, required this.labelOf, required this.onChanged, this.dense = false});

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(StrideRadius.control)),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Semantics(
                selected: v == selected,
                button: true,
                label: labelOf(v),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: StrideMotion.state,
                    constraints: BoxConstraints(minHeight: dense ? 40 : 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: v == selected ? StrideColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(StrideRadius.small + 2),
                    ),
                    child: Text(
                      labelOf(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StrideText.label.copyWith(color: v == selected ? Colors.white : StrideColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip cao vẽ 36, hit area 48, text 14.
class StrideChip extends StatelessWidget {
  const StrideChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StrideRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: StrideMotion.state,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? StrideColors.lime : StrideColors.surface,
              borderRadius: BorderRadius.circular(StrideRadius.pill),
              border: Border.all(color: selected ? StrideColors.lime : StrideColors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: StrideColors.textPrimary), const SizedBox(width: 6)],
                Text(label, style: StrideText.label.copyWith(color: onTap == null ? StrideColors.disabledText : StrideColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hàng preset chip (vd. 4,000 / 6,000 / 8,000 / 10,000).
class PresetChips<T> extends StatelessWidget {
  const PresetChips({super.key, required this.values, required this.selected, required this.labelOf, required this.onSelected});
  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [for (final v in values) StrideChip(label: labelOf(v), selected: v == selected, onTap: () => onSelected(v))],
  );
}
