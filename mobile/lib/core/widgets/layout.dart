import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Màn con: back + tiêu đề + tối đa hai action; nội dung giới hạn 560 và gutter 20 (16 khi máy nhỏ).
class StrideScreen extends StatelessWidget {
  const StrideScreen({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.bottom,
    this.showBack = true,
    this.scroll = true,
    this.padding,
    this.onBack,
    this.largeTitle = false,
  });

  final String? title;
  final Widget body;
  final List<Widget>? actions;

  /// CTA đáy nằm trên safe area, không che nội dung cuộn.
  final Widget? bottom;
  final bool showBack;
  final bool scroll;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onBack;
  final bool largeTitle;

  static double gutterOf(BuildContext context) => MediaQuery.sizeOf(context).width < 360 ? StrideSpace.gutterSmall : StrideSpace.gutter;

  @override
  Widget build(BuildContext context) {
    final g = gutterOf(context);
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: g),
          child: body,
        ),
      ),
    );
    return Scaffold(
      appBar: (title == null && !showBack && actions == null)
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: showBack
                  ? IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: onBack ?? () => Navigator.of(context).maybePop())
                  : null,
              titleSpacing: showBack ? 0 : g,
              title: title == null ? null : Text(title!, style: largeTitle ? StrideText.title : StrideText.heading),
              actions: actions,
            ),
      body: SafeArea(
        top: title == null && !showBack && actions == null,
        bottom: bottom == null,
        child: scroll ? SingleChildScrollView(padding: const EdgeInsets.only(bottom: 24), child: content) : content,
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
                  child: Padding(padding: EdgeInsets.fromLTRB(g, 8, g, 12), child: bottom),
                ),
              ),
            ),
    );
  }
}

/// Khoảng cách dọc chuẩn.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}
