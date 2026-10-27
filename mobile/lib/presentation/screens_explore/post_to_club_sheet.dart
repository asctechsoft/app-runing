import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/explore/explore_logic.dart';
import '../../models/data_models/activity.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/activity_format.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/explore_widgets.dart';

/// TM06: người dùng chủ động đăng một buổi đã lưu vào club mình đang là thành viên. Bài chỉ có số liệu tóm tắt
/// ([postActivityDoc]) — không bản đồ/tọa độ, không ghi chú — nên không lộ điểm đầu/cuối dù hoạt động đang riêng tư.
/// Trả `true` khi đã đăng.
Future<bool> showPostToClubSheet(BuildContext context, Activity activity) async {
  final r = await showStrideSheet<bool>(
    context,
    title: 'explore_post_to_club_title'.tr,
    builder: (_) => _PostToClub(activity: activity),
  );
  return r ?? false;
}

class _PostToClub extends ConsumerStatefulWidget {
  const _PostToClub({required this.activity});
  final Activity activity;

  @override
  ConsumerState<_PostToClub> createState() => _PostToClubState();
}

class _PostToClubState extends ConsumerState<_PostToClub> {
  final _text = TextEditingController();
  List<Club>? _clubs;
  ExploreFailure? _error;
  String? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final all = await ref.read(exploreRepositoryProvider).myClubs();
      final mine = all.where((c) => c.membership?.isMember ?? false).toList();
      if (mounted) {
        setState(() {
          _clubs = mine;
          _selected = mine.length == 1 ? mine.single.id : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _post() async {
    final id = _selected;
    if (_busy || id == null) return; // T04: chạm đúp
    setState(() => _busy = true);
    try {
      final a = widget.activity;
      await ref
          .read(exploreRepositoryProvider)
          .createPost(
            id,
            text: _text.text,
            activity: postActivityDoc(a, title: activityDisplayTitle(a)),
          );
      if (!mounted) return;
      showStrideSnack(context, 'explore_post_to_club_done'.tr);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final clubs = _clubs;
    if (clubs == null) return const LoadingCard(height: 120);
    if (clubs.isEmpty) {
      return EmptyState(icon: Icons.groups_outlined, title: 'explore_post_to_club_empty_title'.tr, message: 'explore_post_to_club_empty_message'.tr);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<String>(
          groupValue: _selected,
          onChanged: (v) => setState(() => _selected = v),
          child: Column(
            children: [
              for (final c in clubs)
                RadioListTile<String>(
                  key: Key('post-club-${c.id}'),
                  value: c.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name, style: StrideText.body),
                ),
            ],
          ),
        ),
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('post-club-text'),
          controller: _text,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: 'explore_post_to_club_caption'.tr),
        ),
        Text('explore_post_to_club_privacy'.tr, style: StrideText.caption),
        const Gap(StrideSpace.s16),
        PrimaryButton(
          key: const Key('post-club-submit'),
          label: 'explore_post_to_club_submit'.tr,
          loading: _busy,
          onPressed: _busy || _selected == null ? null : _post,
        ),
      ],
    );
  }
}
