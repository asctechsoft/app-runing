import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/activity/activity_providers.dart';
import '../../controller/auth/auth_flow.dart';
import '../../controller/community/community_providers.dart';
import '../../controller/providers.dart';
import '../../models/data_models/activity.dart';
import '../../repository/community_repository.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'route_image.dart';

/// Số ký tự tối đa của chú thích (rules cho phép tới 500).
const communityCaptionMaxLength = 280;

/// Chia sẻ buổi chạy [a] (đã lưu) lên Cộng đồng — chỉ khi người dùng bấm. Luôn hỏi xác nhận (kèm chú thích tùy chọn và
/// công tắc ảnh tuyến đường) trước khi đăng. Chưa đăng nhập: xác nhận kèm đăng nhập Google rồi mới đăng.
/// Báo thành công chỉ khi Firestore đã xác nhận ghi.
Future<void> shareRunToCommunity(BuildContext context, WidgetRef ref, Activity a) async {
  final signedIn = ref.read(communitySignedInProvider);
  if (ref.read(communitySharesProvider).containsKey(a.id)) return; // đã chia sẻ: phải "Ngừng chia sẻ" trước, không đăng trùng
  // Chỉ đề nghị đính kèm ảnh tuyến đường khi buổi có GPS và phần tuyến còn lại (sau khi ẩn đầu/cuối) đủ dài.
  ActivityDetailData? detail;
  try {
    detail = await ref.read(activityDetailProvider(a.id).future);
  } catch (_) {
    detail = null;
  }
  if (!context.mounted) return;
  final canAttachRoute = detail != null && communityRouteFor(detail).isNotEmpty;
  final choice = await _askShare(context, signedIn: signedIn, canAttachRoute: canAttachRoute);
  if (choice == null || !context.mounted) return;

  String? next;
  if (!signedIn) {
    try {
      next = await signInWithGoogleWidget(ref);
    } catch (e) {
      if (context.mounted) showStrideSnack(context, googleSignInErrorMessage(e), isError: true);
      return;
    }
    if (next == null) return; // người dùng hủy chọn tài khoản
  }

  try {
    final image = choice.withRoute && detail != null && context.mounted ? await renderCommunityRouteImage(context, detail, ref.read(formatProvider)) : null;
    final post = await ref.read(communityRepositoryProvider).publish(a, text: choice.caption, image: image);
    await ref.read(communitySharesProvider.notifier).record(a.id, post.id);
    ref.invalidate(communityFeedProvider);
    if (context.mounted) showStrideSnack(context, 'community_shared'.tr);
  } catch (e) {
    if (context.mounted) showStrideSnack(context, communityErrorMessage(e), isError: true);
  }
  // Vừa đăng nhập: chủ sở hữu dữ liệu đã đổi → đi tiếp theo luồng đăng nhập (gộp dữ liệu khách hoặc Home).
  if (next != null && context.mounted) context.go(next);
}

/// Ngừng chia sẻ buổi [activityId]: xác nhận rồi xóa bài (kèm ảnh tuyến đường) khỏi Cộng đồng. Báo thành công chỉ khi Firestore đã xác nhận.
Future<void> stopSharingRun(BuildContext context, WidgetRef ref, String activityId) async {
  final postId = ref.read(communitySharesProvider)[activityId];
  if (postId == null) return;
  final ok = await confirmDialog(
    context,
    title: 'community_stop_title'.tr,
    message: 'community_stop_message'.tr,
    confirmLabel: 'community_stop_confirm'.tr,
    cancelLabel: 'action_cancel'.tr,
    destructive: true,
    icon: Icons.groups_outlined,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(communityRepositoryProvider).delete(postId);
    await ref.read(communitySharesProvider.notifier).forgetActivity(activityId);
    ref.invalidate(communityFeedProvider);
    if (context.mounted) showStrideSnack(context, 'community_stopped'.tr);
  } catch (e) {
    if (context.mounted) showStrideSnack(context, communityErrorMessage(e), isError: true);
  }
}

/// Nút "Chia sẻ lên cộng đồng" / "Ngừng chia sẻ" theo trạng thái của từng buổi chạy.
class CommunityShareButton extends ConsumerWidget {
  const CommunityShareButton({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(communitySharesProvider).containsKey(activity.id);
    return OutlineButton(
      label: shared ? 'community_stop_button'.tr : 'community_share_button'.tr,
      icon: shared ? Icons.group_off_outlined : Icons.groups_outlined,
      onPressed: () => shared ? stopSharingRun(context, ref, activity.id) : shareRunToCommunity(context, ref, activity),
    );
  }
}

/// Lựa chọn trong hộp xác nhận: chú thích (có thể rỗng) và có đính kèm ảnh tuyến đường không.
typedef _ShareChoice = ({String caption, bool withRoute});

/// Hộp xác nhận chia sẻ. Trả lựa chọn khi đồng ý, null khi hủy.
Future<_ShareChoice?> _askShare(BuildContext context, {required bool signedIn, required bool canAttachRoute}) {
  final c = TextEditingController();
  var withRoute = canAttachRoute;
  return showStrideSheet<_ShareChoice>(
    context,
    title: 'community_share_title'.tr,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(signedIn ? 'community_share_message'.tr : 'community_share_login_message'.tr, style: StrideText.bodySecondary),
          const SizedBox(height: StrideSpace.s12),
          if (canAttachRoute) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: withRoute,
              onChanged: (v) => setState(() => withRoute = v),
              title: Text('community_share_route'.tr, style: StrideText.label),
              subtitle: Text('community_share_route_hint'.tr, style: StrideText.caption),
            ),
            const SizedBox(height: StrideSpace.s8),
          ],
          TextField(
            controller: c,
            maxLength: communityCaptionMaxLength,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'community_caption_label'.tr, hintText: 'community_caption_hint'.tr),
          ),
          const SizedBox(height: StrideSpace.s8),
          PrimaryButton(
            label: signedIn ? 'community_share_confirm'.tr : 'community_share_login_confirm'.tr,
            icon: Icons.groups_outlined,
            onPressed: () => Navigator.of(ctx).pop((caption: c.text.trim(), withRoute: withRoute)),
          ),
          const SizedBox(height: StrideSpace.s8),
          OutlineButton(label: 'action_cancel'.tr, onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    ),
  );
}
