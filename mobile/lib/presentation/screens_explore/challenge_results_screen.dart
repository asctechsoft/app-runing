import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/date_locale.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenges_screen.dart';
import 'components/explore_widgets.dart';

/// Dữ liệu màn kết quả (TM41).
class ChallengeResults {
  const ChallengeResults({required this.challenge, required this.board, required this.teams});
  final Challenge challenge;
  final ChallengeLeaderboard board;
  final List<TeamStanding> teams;
}

/// TM41: kết quả thử thách — bục top 3 (người bật hiện tên), đội thắng, kết quả của tôi, chia sẻ, khiếu nại. Chỉ chính thức
/// sau thời gian chờ đồng bộ (TM33); trước đó hiện là "tạm thời". Không có giải thật (ADR 0003).
class ChallengeResultsScreen extends ConsumerStatefulWidget {
  const ChallengeResultsScreen({super.key, required this.challengeId});
  final String challengeId;

  @override
  ConsumerState<ChallengeResultsScreen> createState() => _ChallengeResultsScreenState();
}

class _ChallengeResultsScreenState extends ConsumerState<ChallengeResultsScreen> {
  ChallengeResults? _data;
  ExploreFailure? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(exploreRepositoryProvider);
      final c = await repo.challenge(widget.challengeId);
      final board = await repo.challengeLeaderboard(widget.challengeId);
      var teams = const <TeamStanding>[];
      if (c.clubId != null) {
        final t = await repo.teams(c.id);
        if (t.isNotEmpty) teams = computeTeamStandings(t, await repo.teamProgress(c.id, t));
      }
      if (mounted) setState(() => _data = ChallengeResults(challenge: c, board: board, teams: teams));
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _share(ChallengeResults r) async {
    final c = r.challenge;
    final p = c.participation;
    if (p == null) return;
    final fmt = ref.read(formatProvider);
    final value = challengeValue(c.targetType, p.progressValue, fmt);
    final rank = r.board.optedIn ? r.board.me?.rank : null;
    final text = rank != null && rank > 0 ? 'explore_results_share_rank'.trArgs([c.title, rank, value]) : 'explore_results_share'.trArgs([c.title, value]);
    await SharePlus.instance.share(ShareParams(text: text, subject: c.title));
  }

  Future<void> _appeal() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _AppealDialog());
    if (reason == null || !mounted) return;
    try {
      await ref.read(exploreRepositoryProvider).report(targetType: 'challenge_result', targetId: widget.challengeId, reason: reason);
      if (mounted) showStrideSnack(context, 'explore_results_appeal_sent'.tr);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => StrideScreen(title: 'explore_results_title'.tr, body: _body());

  Widget _body() {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final r = _data;
    if (r == null) return const Column(children: [Gap(8), LoadingCard(height: 200), Gap(12), LoadingCard()]);
    final c = r.challenge;
    final fmt = ref.watch(formatProvider);
    final now = ref.watch(clockProvider).nowMs();
    final phase = challengePhase(startsAt: c.startsAt, endsAt: c.endsAt, cancelled: c.cancelled, nowMs: now);
    final podium = r.board.entries.where((e) => e.rank <= 3).toList();
    final p = c.participation;
    final winner = r.teams.where((t) => t.members > 0 && t.rank == 1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(8),
        Text(c.title, style: StrideText.title),
        const Gap(8),
        if (phase == ChallengePhase.finished)
          StatusBanner(key: const Key('results-final'), tone: BannerTone.info, message: 'explore_phase_finished'.tr)
        else
          StatusBanner(
            key: const Key('results-provisional'),
            tone: BannerTone.warning,
            message: 'explore_results_provisional'.trArgs([
              AppDates.monthDayTime(DateTime.fromMillisecondsSinceEpoch(c.endsAt + challengeGrace.inMilliseconds)),
            ]),
          ),
        const Gap(16),
        Text('explore_results_podium'.tr, style: StrideText.subheading),
        const Gap(8),
        if (podium.isEmpty)
          Text('explore_results_podium_empty'.tr, style: StrideText.bodySecondary)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final place in [2, 1, 3])
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final e = podium.where((x) => x.rank == place).firstOrNull;
                      if (e == null) return const SizedBox.shrink();
                      return _PodiumStep(
                        entry: e,
                        value: challengeValue(c.targetType, e.value, fmt),
                        height: switch (place) {
                          1 => 120.0,
                          2 => 96.0,
                          _ => 80.0,
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        if (winner.isNotEmpty) ...[
          const Gap(16),
          StrideCard(
            key: const Key('results-team'),
            child: Row(
              children: [
                Icon(Icons.groups, color: StrideColors.teams[winner.first.team.color]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('explore_results_team_winner'.tr, style: StrideText.caption),
                      Text(winner.map((t) => t.team.name).join(', '), style: StrideText.subheading),
                      Text(
                        'explore_team_score'.trArgs([challengeValue(c.targetType, winner.first.average, fmt), winner.first.members]),
                        style: StrideText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (p != null) ...[
          const Gap(16),
          StrideCard(
            key: const Key('results-me'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('explore_results_yours'.tr, style: StrideText.label),
                const Gap(4),
                Text(
                  'explore_progress_of'.trArgs([challengeValue(c.targetType, p.progressValue, fmt), challengeValue(c.targetType, c.targetValue, fmt)]),
                  style: StrideText.metricSmall,
                ),
                Text(p.completed ? 'explore_challenge_complete'.tr : 'explore_results_not_complete'.tr, style: StrideText.bodySecondary),
                if (r.board.optedIn && (r.board.me?.rank ?? 0) > 0)
                  Text('explore_leaderboard_your_rank'.trArgs([r.board.me!.rank]), style: StrideText.bodySecondary)
                else
                  Text('explore_results_hidden'.tr, style: StrideText.caption),
                const Gap(8),
                OutlineButton(key: const Key('results-share'), label: 'explore_results_share_button'.tr, icon: Icons.ios_share, onPressed: () => _share(r)),
              ],
            ),
          ),
        ],
        const Gap(12),
        TextButton(key: const Key('results-appeal'), onPressed: _appeal, child: Text('explore_results_appeal'.tr)),
        Text('explore_results_note'.tr, style: StrideText.caption),
      ],
    );
  }
}

class _PodiumStep extends StatelessWidget {
  const _PodiumStep({required this.entry, required this.value, required this.height});
  final LeaderboardEntry entry;
  final String value;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'explore_results_place'.trArgs([entry.rank, entry.displayName, value]),
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(entry.displayName, style: StrideText.label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          Text(value, style: StrideText.caption, textAlign: TextAlign.center),
          const Gap(4),
          Container(
            key: Key('podium-${entry.rank}'),
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: entry.rank == 1 ? StrideColors.lime : StrideColors.subtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(StrideRadius.card)),
            ),
            child: Text('${entry.rank}', style: StrideText.heading),
          ),
        ],
      ),
    ),
  );
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('explore_results_appeal'.tr),
    content: TextField(
      key: const Key('appeal-reason'),
      controller: _c,
      maxLength: 500,
      minLines: 2,
      maxLines: 5,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: 'explore_results_appeal_hint'.tr),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('action_cancel'.tr)),
      FilledButton(
        key: const Key('appeal-send'),
        onPressed: _c.text.trim().isEmpty ? null : () => Navigator.pop(context, _c.text.trim()),
        child: Text('explore_results_appeal_send'.tr),
      ),
    ],
  );
}
