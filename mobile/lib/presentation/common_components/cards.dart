import 'package:flutter/material.dart';

import '../../values/tokens.dart';

/// Thẻ trắng radius 20, padding 16.
class StrideCard extends StatelessWidget {
  const StrideCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(StrideSpace.cardPadding),
    this.onTap,
    this.color = StrideColors.surface,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(StrideRadius.card),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Thẻ sage (bg.subtle).
class SageCard extends StrideCard {
  const SageCard({super.key, required super.child, super.padding, super.onTap, super.semanticLabel}) : super(color: StrideColors.subtle);
}

/// Chỉ số: icon tròn lime + giá trị + đơn vị sát nhau + nhãn.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.estimated = false,
    this.large = false,
    this.center = false,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final bool estimated;
  final bool large;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final valueStyle = large ? StrideText.metricMedium : StrideText.metricSmall;
    final semantics = '$label, $value${unit == null ? '' : ' $unit'}${estimated ? ', estimated' : ''}';
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[IconBadge(icon: icon!, size: 32), const SizedBox(height: 6)],
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: valueStyle),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: StrideText.label.copyWith(color: StrideColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
          ),
          Text(estimated ? '$label · estimated' : label, style: StrideText.caption, textAlign: center ? TextAlign.center : TextAlign.start, maxLines: 2),
        ],
      ),
    );
  }
}

/// Icon trong vòng tròn lime (điểm nhấn).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.size = 40, this.background = StrideColors.lime, this.foreground = StrideColors.primary});
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, size: size * 0.55, color: foreground),
  );
}

/// Hàng settings: min 56, icon 24, chevron 20, toàn hàng bấm được (DS mục 05).
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, this.subtitle, this.icon, this.trailing, this.onTap, this.showChevron = true, this.destructive = false});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? StrideColors.error : StrideColors.textPrimary;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 24, color: destructive ? StrideColors.error : StrideColors.primary), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: StrideText.body.copyWith(fontWeight: FontWeight.w600, color: color),
                      ),
                      if (subtitle != null) Text(subtitle!, style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
                    ],
                  ),
                ),
                ?trailing,
                if (showChevron && onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_right, size: 20, color: StrideColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhóm SettingsRow trong một thẻ, có divider.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => StrideCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), children[i]],
      ],
    ),
  );
}

/// Tiêu đề khối + action phụ (vd. "View all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.subtitle});
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: StrideText.subheading),
              if (subtitle != null) Text(subtitle!, style: StrideText.caption),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(actionLabel!), const Icon(Icons.chevron_right, size: 18)]),
          ),
      ],
    ),
  );
}

/// Bộ tăng giảm "− 8,000 +" (Goals).
class ValueStepper extends StatelessWidget {
  const ValueStepper({super.key, required this.valueText, required this.unitLabel, required this.onDecrement, required this.onIncrement, this.semanticLabel});
  final String valueText;
  final String unitLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget circle(IconData i, VoidCallback? f, String label) => Semantics(
      button: true,
      label: label,
      child: Material(
        color: StrideColors.surface,
        shape: const CircleBorder(side: BorderSide(color: StrideColors.borderSubtle)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: f,
          child: SizedBox(width: 48, height: 48, child: Icon(i, color: f == null ? StrideColors.textMuted : StrideColors.textPrimary)),
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        circle(Icons.remove, onDecrement, 'Decrease ${semanticLabel ?? ''}'),
        Expanded(
          child: Semantics(
            label: '${semanticLabel ?? ''} $valueText $unitLabel',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(valueText, style: StrideText.metric.copyWith(fontSize: 40), textAlign: TextAlign.center),
                Text(unitLabel, style: StrideText.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        circle(Icons.add, onIncrement, 'Increase ${semanticLabel ?? ''}'),
      ],
    );
  }
}
