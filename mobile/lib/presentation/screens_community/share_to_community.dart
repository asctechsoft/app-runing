import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/auth/auth_flow.dart';
import '../../controller/community/community_providers.dart';
import '../../models/data_models/activity.dart';
import '../../repository/community_repository.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';

/// Số ký tự tối đa của chú thích (rules cho phép tới 500).
const communityCaptionMaxLength = 280;

/// Chia sẻ buổi chạy [a] (đã lưu) lên Cộng đồng — chỉ khi người dùng bấm. Luôn hỏi xác nhận (kèm chú thích tùy chọn) trước khi đăng.
/// Chưa đăng nhập: xác nhận kèm đăng nhập Google rồi mới đăng. Báo thành công chỉ khi Firestore đã xác nhận ghi.
Future<void> shareRunToCommunity(BuildContext context, WidgetRef ref, Activity a) async {
  final signedIn = ref.read(communitySignedInProvider);
  final caption = await _askCaption(context, signedIn: signedIn);
  if (caption == null || !context.mounted) return;

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
    await ref.read(communityRepositoryProvider).publish(a, text: caption);
    ref.invalidate(communityFeedProvider);
    if (context.mounted) showStrideSnack(context, 'community_shared'.tr);
  } catch (e) {
    if (context.mounted) showStrideSnack(context, communityErrorMessage(e), isError: true);
  }
  // Vừa đăng nhập: chủ sở hữu dữ liệu đã đổi → đi tiếp theo luồng đăng nhập (gộp dữ liệu khách hoặc Home).
  if (next != null && context.mounted) context.go(next);
}

/// Hộp xác nhận chia sẻ. Trả chú thích (có thể rỗng) khi đồng ý, null khi hủy.
Future<String?> _askCaption(BuildContext context, {required bool signedIn}) {
  final c = TextEditingController();
  return showStrideSheet<String>(
    context,
    title: 'community_share_title'.tr,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(signedIn ? 'community_share_message'.tr : 'community_share_login_message'.tr, style: StrideText.bodySecondary),
        const SizedBox(height: StrideSpace.s12),
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
          onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
        ),
        const SizedBox(height: StrideSpace.s8),
        OutlineButton(label: 'action_cancel'.tr, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}
