import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/analytics.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenges_screen.dart';
import 'components/explore_widgets.dart';

/// TM30: bảng xếp hạng thử thách — top N người bật hiển thị, vị trí của tôi, đồng hạng theo ai đạt trước,
/// ẩn người bị chặn, công tắc hiện tên (mặc định ẩn, `leaderboardOptIn = false`).
class ChallengeLeaderboardScreen extends StatelessWidget {
  const ChallengeLeaderboardScreen({super.key, required this.challengeId});
  final String challengeId;

  @override
  Widget build(BuildContext context) => StrideScreen(
    title: 'explore_leaderboard'.tr,
    scroll: false,
    body: ExploreGuestGate(
      title: 'explore_challenges_guest_title'.tr,
      message: 'explore_challenges_guest_message'.tr,
      child: _Body(challengeId: challengeId),
    ),
  );
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.challengeId});
  final String challengeId;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  Challenge? _challenge;
  ChallengeLeaderboard? _board;
  ExploreFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Analytics.leaderboardView();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repo = ref.read(exploreRepositoryProvider);
    try {
      final c = await repo.challenge(widget.challengeId);
      final b = await repo.challengeLeaderboard(widget.challengeId);
      if (mounted) {
        setState(() {
          _challenge = c;
          _board = b;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return; // T04
    setState(() => _busy = true);
    try {
      await ref.read(exploreRepositoryProvider).setLeaderboardOptIn(widget.challengeId, on);
      await _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SingleChildScrollView(
        child: ExploreFailureView(failure: _error!, onRetry: _load),
      );
    }
    final c = _challenge;
    final b = _board;
    if (c == null || b == null) return ListView(children: const [LoadingCard(height: 72), Gap(12), LoadingCard(height: 72)]);
    final fmt = ref.watch(formatProvider);
    String value(double v) => challengeValue(c.targetType, v, fmt);
    final myUid = ref.read(ownerProvider).ownerId;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: StrideSpace.s24),
        children: [
          Text(c.title, style: StrideText.subheading),
          const Gap(StrideSpace.s12),
          if (!b.joined)
            StatusBanner(tone: BannerTone.info, title: 'explore_leaderboard_not_joined'.tr, message: 'explore_leaderboard_empty_message'.tr)
          else ...[
            if (b.optedIn && b.me != null)
              Text('explore_leaderboard_your_rank'.trArgs([b.me!.rank]), style: StrideText.label)
            else
              StatusBanner(tone: BannerTone.info, title: 'explore_leaderboard_hidden'.tr, message: 'explore_leaderboard_hidden_message'.tr),
            SwitchListTile(
              key: const Key('leaderboard-optin'),
              contentPadding: EdgeInsets.zero,
              value: b.optedIn,
              onChanged: _busy ? null : _toggle,
              title: Text('explore_leaderboard_show_me'.tr, style: StrideText.body),
              subtitle: Text('explore_leaderboard_show_me_note'.tr, style: StrideText.caption),
            ),
          ],
          const Gap(StrideSpace.s12),
          if (b.entries.isEmpty)
            EmptyState(icon: Icons.leaderboard_outlined, title: 'explore_leaderboard_empty_title'.tr, message: 'explore_leaderboard_empty_message'.tr)
          else
            for (final e in b.entries) _Row(entry: e, isMe: e.userId == myUid, value: value(e.value)),
          const Gap(StrideSpace.s8),
          Text('explore_leaderboard_tie_note'.tr, style: StrideText.caption),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.isMe, required this.value});
  final LeaderboardEntry entry;
  final bool isMe;
  final String value;

  @override
  Widget build(BuildContext context) {
    final name = isMe ? 'explore_leaderboard_you'.tr : (entry.displayName.isEmpty ? 'explore_club_member_unnamed'.tr : entry.displayName);
    return Semantics(
      label: 'explore_leaderboard_rank_semantic'.trArgs([entry.rank, name, value]),
      excludeSemantics: true,
      child: Container(
        key: Key('rank-${entry.userId}'),
        color: isMe ? StrideColors.subtle : null,
        padding: const EdgeInsets.symmetric(vertical: StrideSpace.s8, horizontal: StrideSpace.s4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text('#${entry.rank}', style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Expanded(
              child: Text(name, style: StrideText.body, overflow: TextOverflow.ellipsis),
            ),
            Text(value, style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}
