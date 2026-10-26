import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../utils/l10n.dart';

/// [title], [body], [semantic] là khóa chuỗi — gọi `.tr` ở nơi hiển thị.
class _IntroPage {
  const _IntroPage(this.image, this.title, this.body, this.semantic);
  final String image;
  final String title;
  final String body;
  final String semantic;
}

const _pages = [
  _IntroPage('assets/images/onboarding_steps.jpg', 'onboarding_p1_title', 'onboarding_p1_body', 'onboarding_p1_semantic'),
  _IntroPage('assets/images/onboarding_map.jpg', 'onboarding_p2_title', 'onboarding_p2_body', 'onboarding_p2_semantic'),
  _IntroPage('assets/images/onboarding_progress.jpg', 'onboarding_p3_title', 'onboarding_p3_body', 'onboarding_p3_semantic'),
];

/// Ba trang giới thiệu (E01). intro_seen chỉ lưu khi bấm Skip hoặc Get started.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  final _guard = OnceGuard();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() => _guard.run(() async {
    await ref.read(ownerRepositoryProvider).markIntroSeen();
    ref.read(ownerProvider.notifier).reload();
    if (mounted) context.go(Routes.welcome);
  });

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _controller.jumpToPage(_index + 1);
    } else {
      _controller.nextPage(duration: StrideMotion.screen, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: StrideColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: Column(
              children: [
                SizedBox(
                  height: StrideSpace.touchTarget,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: last ? null : TextButton(onPressed: _finish, child: Text('onboarding_skip'.tr)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _PageBody(page: _pages[i], showFeatures: i == _pages.length - 1),
                  ),
                ),
                _Dots(count: _pages.length, index: _index),
                Padding(
                  padding: const EdgeInsets.fromLTRB(StrideSpace.gutter, StrideSpace.s16, StrideSpace.gutter, StrideSpace.s8),
                  child: PrimaryButton(label: last ? 'onboarding_get_started'.tr : 'onboarding_next'.tr, trailingIcon: Icons.arrow_forward, onPressed: _next),
                ),
                SizedBox(
                  height: 56,
                  child: _index == 0
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: Text('auth_have_account'.tr, style: StrideText.bodySecondary)),
                            TextButton(
                              onPressed: () => context.push(Routes.login),
                              child: Text(
                                'auth_log_in'.tr,
                                style: StrideText.body.copyWith(color: StrideColors.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.showFeatures});
  final _IntroPage page;
  final bool showFeatures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: StrideSpace.gutter),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(StrideRadius.card),
                child: Semantics(
                  label: page.semantic.tr,
                  image: true,
                  child: Image.asset(
                    page.image,
                    height: (c.maxHeight * (showFeatures ? 0.42 : 0.58)).clamp(160.0, 460.0),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(height: 200, color: StrideColors.subtle),
                  ),
                ),
              ),
              const SizedBox(height: StrideSpace.s24),
              Semantics(
                header: true,
                child: Text(page.title.tr, style: StrideText.title, textAlign: TextAlign.center),
              ),
              const SizedBox(height: StrideSpace.s8),
              Text(page.body.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
              if (showFeatures) ...[
                const SizedBox(height: StrideSpace.s16),
                _Feature(icon: Icons.flag_outlined, title: 'onboarding_feature_goals_title'.tr, body: 'onboarding_feature_goals_body'.tr),
                _Feature(icon: Icons.bar_chart, title: 'onboarding_feature_progress_title'.tr, body: 'onboarding_feature_progress_body'.tr),
                _Feature(icon: Icons.emoji_events_outlined, title: 'onboarding_feature_milestones_title'.tr, body: 'onboarding_feature_milestones_body'.tr),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: StrideSpace.s8),
    child: SageCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconBadge(icon: icon, size: 36),
          const SizedBox(width: StrideSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: StrideText.label),
                Text(body, style: StrideText.caption.copyWith(color: StrideColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'onboarding_page_semantic'.trArgs([index + 1, count]),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: StrideMotion.state,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? StrideColors.primary : StrideColors.borderSubtle,
              borderRadius: BorderRadius.circular(StrideRadius.pill),
            ),
          ),
      ],
    ),
  );
}
