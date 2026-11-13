import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../controller/providers.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// [video] phát lặp, tắt tiếng, làm nền cả trang. Chưa tải xong / lỗi → nền navy (không chèn ảnh khác).
/// [title], [body], [semantic] là khóa chuỗi — gọi `.tr` ở nơi hiển thị.
class _IntroPage {
  const _IntroPage(this.video, this.title, this.body, this.semantic);
  final String video;
  final String title;
  final String body;
  final String semantic;
}

const _pages = [
  _IntroPage('assets/images/onboarding_1.mp4', 'onboarding_p1_title', 'onboarding_p1_body', 'onboarding_p1_semantic'),
  _IntroPage('assets/images/onboarding_2.mp4', 'onboarding_p2_title', 'onboarding_p2_body', 'onboarding_p2_semantic'),
  _IntroPage('assets/images/onboarding_3.mp4', 'onboarding_p3_title', 'onboarding_p3_body', 'onboarding_p3_semantic'),
];

/// Chiều cao vùng điều khiển cố định dưới cùng (dots + nút + dòng "đã có tài khoản") — nội dung trang chừa chỗ này.
const double _controlsFooter = 56;
const double _controlsReserve = 8 + StrideSpace.s16 + 56 + StrideSpace.s8 + _controlsFooter + StrideSpace.s16;

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

  // Cả 3 video được tạo và khởi tạo một lần ở đây (không theo vòng đời từng trang), nên vuốt qua lại không phải tải lại / chớp khung.
  late final List<VideoPlayerController> _videos = [
    for (final p in _pages) VideoPlayerController.asset(p.video, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)),
  ];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _videos.length; i++) {
      _prepare(i);
    }
  }

  Future<void> _prepare(int i) async {
    final c = _videos[i];
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (mounted) _syncPlayback();
    } catch (_) {
      // Thiếu plugin / codec lỗi: trang giữ nền navy, onboarding vẫn dùng được.
    }
  }

  /// Chỉ video của trang đang hiện được phát; các trang khác dừng và tua về đầu. Giảm chuyển động → không tự phát.
  void _syncPlayback() {
    final reduce = StrideMotion.reduced(context);
    for (var i = 0; i < _videos.length; i++) {
      final c = _videos[i];
      if (!c.value.isInitialized) continue;
      if (i == _index && !reduce) {
        c.play();
      } else {
        c.pause();
        if (i != _index) c.seekTo(Duration.zero);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _videos) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() => _guard.run(() async {
    await ref.read(ownerRepositoryProvider).markIntroSeen();
    ref.read(ownerProvider.notifier).reload();
    if (mounted) context.go(Routes.setupProfile);
  });

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    final reduce = StrideMotion.reduced(context);
    if (reduce) {
      _controller.jumpToPage(_index + 1);
    } else {
      _controller.nextPage(duration: StrideMotion.screen, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    // L19: Back lùi trang; ở trang đầu quay lại màn chọn ngôn ngữ để đổi lựa chọn (không thoát app ngay).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index > 0) {
          if (StrideMotion.reduced(context)) {
            _controller.jumpToPage(_index - 1);
          } else {
            _controller.previousPage(duration: StrideMotion.screen, curve: Curves.easeOut);
          }
        } else {
          context.go(Routes.language);
        }
      },
      // Mỗi trang là một nền video riêng phủ toàn màn hình (tràn cả vùng status bar); chữ + điều khiển nằm đè lên trên lớp phủ tối.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: StrideColors.iconNavy,
          body: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _syncPlayback();
                },
                itemBuilder: (context, i) => _PageBody(page: _pages[i], video: _videos[i], showFeatures: i == _pages.length - 1),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
                    child: Column(
                      children: [
                        SizedBox(
                          height: StrideSpace.touchTarget,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: last
                                ? null
                                : TextButton(
                                    onPressed: _finish,
                                    style: TextButton.styleFrom(foregroundColor: StrideColors.surface),
                                    child: Text('onboarding_skip'.tr),
                                  ),
                          ),
                        ),
                        const Spacer(),
                        _Dots(count: _pages.length, index: _index),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(StrideSpace.gutter, StrideSpace.s16, StrideSpace.gutter, StrideSpace.s8),
                          child: PrimaryButton(
                            label: last ? 'onboarding_get_started'.tr : 'onboarding_next'.tr,
                            trailingIcon: Icons.arrow_forward,
                            onPressed: _next,
                          ),
                        ),
                        SizedBox(
                          height: _controlsFooter,
                          child: _index == 0
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text('auth_have_account'.tr, style: StrideText.bodySecondary.copyWith(color: StrideColors.surface)),
                                    ),
                                    TextButton(
                                      onPressed: () => context.push(Routes.login),
                                      child: Text(
                                        'auth_log_in'.tr,
                                        style: StrideText.body.copyWith(color: StrideColors.lime, fontWeight: FontWeight.w600),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.video, required this.showFeatures});
  final _IntroPage page;
  final VideoPlayerController video;
  final bool showFeatures;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: page.semantic.tr,
          image: true,
          child: _IntroVideo(controller: video),
        ),
        // Lớp phủ tối dần xuống dưới để chữ trắng luôn đọc được trên mọi khung hình; đỉnh phủ nhẹ cho nút Skip.
        // Trang cuối nhiều nội dung hơn nên lớp phủ bắt đầu cao hơn và đặc hơn.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                StrideColors.iconNavy.withValues(alpha: 0.45),
                StrideColors.iconNavy.withValues(alpha: 0),
                StrideColors.iconNavy.withValues(alpha: showFeatures ? 0.55 : 0.35),
                StrideColors.iconNavy.withValues(alpha: 0.9),
                StrideColors.iconNavy.withValues(alpha: 0.97),
              ],
              stops: showFeatures ? const [0, 0.14, 0.34, 0.55, 1] : const [0, 0.16, 0.42, 0.68, 1],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: SingleChildScrollView(
              reverse: true,
              padding: EdgeInsets.fromLTRB(StrideSpace.gutter, safe.top + StrideSpace.touchTarget, StrideSpace.gutter, safe.bottom + _controlsReserve),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      page.title.tr,
                      style: StrideText.title.copyWith(color: StrideColors.surface),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  Text(
                    page.body.tr,
                    style: StrideText.bodySecondary.copyWith(color: StrideColors.surface),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Video nền toàn trang (cover). Controller do màn cha giữ; chưa khởi tạo xong thì để trống (nền navy của Scaffold).
class _IntroVideo extends StatelessWidget {
  const _IntroVideo({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, v, _) {
      if (!v.isInitialized) return const SizedBox.expand();
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(controller)),
      );
    },
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
