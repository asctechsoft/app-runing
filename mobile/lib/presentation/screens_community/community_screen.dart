import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/auth/auth_flow.dart';
import '../../controller/community/community_providers.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/community_models.dart';
import '../../repository/community_repository.dart';
import '../../services/application/firebase_providers.dart';
import '../../utils/activity_format.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../screens_auth/components/auth_widgets.dart';
import '../screens_explore/components/explore_widgets.dart' show askReportReason;

/// Cộng đồng: bảng tin các buổi chạy được chia sẻ. **Chỉ người đã đăng nhập xem được**; khách thấy lời mời đăng nhập Google.
/// Người xem chỉ có thể thả tim (không bình luận).
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(communitySignedInProvider);
    return StrideScreen(
      title: 'community_title'.tr,
      actions: [
        if (signedIn)
          IconButton(tooltip: 'community_refresh'.tr, icon: const Icon(Icons.refresh), onPressed: () => ref.read(communityFeedProvider.notifier).refresh()),
      ],
      body: signedIn ? const _Feed() : const CommunityLoginGate(),
    );
  }
}

/// Lời mời đăng nhập (chỉ Google) thay cho bảng tin khi chưa có tài khoản.
class CommunityLoginGate extends ConsumerStatefulWidget {
  const CommunityLoginGate({super.key});

  @override
  ConsumerState<CommunityLoginGate> createState() => _CommunityLoginGateState();
}

class _CommunityLoginGateState extends ConsumerState<CommunityLoginGate> {
  final _guard = OnceGuard();
  bool _busy = false;

  Future<void> _login() => _guard.run(() async {
    setState(() => _busy = true);
    try {
      final next = await signInWithGoogleWidget(ref);
      if (!mounted || next == null) return;
      // Có dữ liệu khách cần gộp → sang màn gộp (chủ sở hữu dữ liệu đã đổi sang tài khoản). Ngược lại ở lại, bảng tin tự nạp.
      if (next == Routes.mergeGuest) context.go(next);
    } catch (e) {
      if (mounted) showStrideSnack(context, googleSignInErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(firebaseReadyProvider) && ref.watch(flagsProvider).authGoogle;
    return Column(
      children: [
        const SizedBox(height: StrideSpace.s32),
        const IconBadge(icon: Icons.groups_outlined, size: 88),
        const SizedBox(height: StrideSpace.s20),
        Text('community_gate_title'.tr, style: StrideText.title, textAlign: TextAlign.center),
        const SizedBox(height: StrideSpace.s8),
        Text('community_gate_message'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
        const SizedBox(height: StrideSpace.s24),
        if (available)
          PrimaryButton(label: 'auth_continue_google'.tr, icon: Icons.g_mobiledata, loading: _busy, onPressed: _login)
        else
          const AccountsUnavailable(),
      ],
    );
  }
}

class _Feed extends ConsumerWidget {
  const _Feed();

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final err = await ref.read(communityFeedProvider.notifier).loadMore();
    if (err != null && context.mounted) showStrideSnack(context, err, isError: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(communityFeedProvider);
    return feed.when(
      loading: () => const Column(children: [Gap(16), LoadingCard(height: 140), Gap(12), LoadingCard(height: 140), Gap(12), LoadingCard(height: 140)]),
      error: (e, _) =>
          ErrorState(title: 'community_error_title'.tr, message: communityErrorMessage(e), onRetry: () => ref.read(communityFeedProvider.notifier).refresh()),
      data: (state) {
        final posts = state.posts;
        if (posts.isEmpty && !state.hasMore) {
          return EmptyState(icon: Icons.groups_outlined, title: 'community_empty_title'.tr, message: 'community_empty_message'.tr);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(8),
            for (final p in posts) ...[PostCard(post: p), const Gap(12)],
            if (state.hasMore) OutlineButton(label: 'community_load_more'.tr, onPressed: state.loadingMore ? null : () => _loadMore(context, ref)),
          ],
        );
      },
    );
  }
}

enum _PostAction { delete, reportPost, reportUser, block }

/// Một bài: tác giả, số liệu buổi chạy, nút thả tim. Tác giả có thêm menu xóa.
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});
  final CommunityPost post;

  Future<void> _like(BuildContext context, WidgetRef ref) async {
    final err = await ref.read(communityFeedProvider.notifier).toggleLike(post.id);
    if (err != null && context.mounted) showStrideSnack(context, err, isError: true);
  }

  Future<void> _action(BuildContext context, WidgetRef ref, _PostAction a) async {
    switch (a) {
      case _PostAction.delete:
        return _delete(context, ref);
      case _PostAction.reportPost || _PostAction.reportUser:
        final user = a == _PostAction.reportUser;
        final name = post.authorName.trim().isEmpty ? 'community_anonymous'.tr : post.authorName.trim();
        final reason = await askReportReason(context, user ? 'explore_report_user_title'.trArgs([name]) : 'explore_report_post'.tr);
        if (reason == null || !context.mounted) return;
        final err = await ref.read(communityFeedProvider.notifier).report(post, reason, user: user);
        if (context.mounted) showStrideSnack(context, err ?? 'community_report_sent'.tr, isError: err != null);
      case _PostAction.block:
        final name = post.authorName.trim().isEmpty ? 'community_anonymous'.tr : post.authorName.trim();
        final ok = await confirmDialog(
          context,
          title: 'explore_block_title'.trArgs([name]),
          message: 'community_block_message'.tr,
          confirmLabel: 'explore_block'.tr,
          cancelLabel: 'action_cancel'.tr,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final err = await ref.read(communityFeedProvider.notifier).block(post.authorId);
        if (context.mounted) showStrideSnack(context, err ?? 'explore_blocked'.trArgs([name]), isError: err != null);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'community_delete_title'.tr,
      message: 'community_delete_message'.tr,
      confirmLabel: 'community_delete_confirm'.tr,
      cancelLabel: 'action_cancel'.tr,
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !context.mounted) return;
    final err = await ref.read(communityFeedProvider.notifier).delete(post.id);
    if (context.mounted) showStrideSnack(context, err ?? 'community_deleted'.tr, isError: err != null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(formatProvider);
    final mine = ref.watch(currentUidProvider) == post.authorId;
    final name = post.authorName.trim();
    final when = AppDates.monthDayTime(DateTime.fromMillisecondsSinceEpoch(post.createdAt));
    final distance = post.distanceM == null ? missingValue : '${post.distanceEstimated ? '~' : ''}${fmt.distance(post.distanceM)}';
    final summary = [activityTypeLabel(post.type), distance, formatDuration(post.movingMs)].join(' · ');
    return StrideCard(
      semanticLabel: '${name.isEmpty ? 'community_anonymous'.tr : name}. $summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: StrideColors.subtle,
                foregroundColor: StrideColors.primary,
                child: name.isEmpty ? const Icon(Icons.person_outline) : Text(name.characters.first.toUpperCase(), style: StrideText.label),
              ),
              const SizedBox(width: StrideSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'community_anonymous'.tr : name, style: StrideText.subheading, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(when, style: StrideText.caption),
                  ],
                ),
              ),
              PopupMenuButton<_PostAction>(
                tooltip: 'community_more'.tr,
                icon: const Icon(Icons.more_horiz),
                onSelected: (a) => _action(context, ref, a),
                itemBuilder: (_) => mine
                    ? [PopupMenuItem(value: _PostAction.delete, child: Text('community_delete_confirm'.tr))]
                    : [
                        PopupMenuItem(value: _PostAction.reportPost, child: Text('explore_report_post'.tr)),
                        PopupMenuItem(value: _PostAction.reportUser, child: Text('explore_report_user'.tr)),
                        PopupMenuItem(value: _PostAction.block, child: Text('explore_block_user'.tr)),
                      ],
              ),
            ],
          ),
          if (post.text.isNotEmpty) ...[const SizedBox(height: StrideSpace.s12), Text(post.text, style: StrideText.body)],
          if (post.image != null) ...[const SizedBox(height: StrideSpace.s12), _RouteImage(bytes: post.image!)],
          const SizedBox(height: StrideSpace.s12),
          Row(
            children: [
              IconBadge(icon: activityTypeIcon(post.type)),
              const SizedBox(width: StrideSpace.s12),
              Expanded(child: Text(summary, style: StrideText.label)),
            ],
          ),
          const SizedBox(height: StrideSpace.s8),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              toggled: post.likedByMe,
              label: post.likedByMe ? 'community_unlike'.trArgs([post.likeCount]) : 'community_like'.trArgs([post.likeCount]),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(StrideRadius.control),
                onTap: () => _like(context, ref),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: StrideSpace.touchTarget, minWidth: StrideSpace.touchTarget),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border, color: post.likedByMe ? StrideColors.error : StrideColors.textMuted),
                        const SizedBox(width: StrideSpace.s8),
                        Text('${post.likeCount}', style: StrideText.label),
                      ],
                    ),
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

/// Ảnh tuyến đường kèm bài (tỉ lệ 4:5 như thẻ chia sẻ); chạm để xem lớn.
class _RouteImage extends StatelessWidget {
  const _RouteImage({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink());
    return Semantics(
      image: true,
      button: true,
      label: 'community_route_image_semantic'.tr,
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: InkWell(
            borderRadius: BorderRadius.circular(StrideRadius.card),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => Dialog(
                insetPadding: const EdgeInsets.all(StrideSpace.s16),
                child: InteractiveViewer(child: Image.memory(bytes)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(StrideRadius.card),
              child: AspectRatio(aspectRatio: 360 / 450, child: image),
            ),
          ),
        ),
      ),
    );
  }
}
