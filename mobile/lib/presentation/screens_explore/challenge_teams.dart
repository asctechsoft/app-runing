import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenges_screen.dart';
import 'components/explore_widgets.dart';

/// TM32: đội trong thử thách của club — bảng xếp hạng đội (điểm = trung bình mỗi người), chọn/đổi đội (một lần, khóa
/// 48 giờ trước khi kết thúc), chia cân bằng tự động, owner/admin thêm đội.
class ChallengeTeams extends ConsumerStatefulWidget {
  const ChallengeTeams({super.key, required this.challenge, required this.canManage, this.onChanged});
  final Challenge challenge;
  final bool canManage;

  /// Đội của tôi vừa đổi → màn cha tải lại participation.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ChallengeTeams> createState() => _ChallengeTeamsState();
}

class _ChallengeTeamsState extends ConsumerState<ChallengeTeams> {
  List<ChallengeTeam>? _teams;
  List<TeamMemberProgress> _members = const [];
  ExploreFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(exploreRepositoryProvider);
      final teams = await repo.teams(widget.challenge.id);
      final members = await repo.teamProgress(widget.challenge.id, teams);
      if (mounted) {
        setState(() {
          _teams = teams;
          _members = members;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _join(String teamId) async {
    if (_busy) return;
    final p = widget.challenge.participation;
    if (p?.teamId != null) {
      final ok = await confirmDialog(
        context,
        title: 'explore_team_change_title'.tr,
        message: 'explore_team_change_message'.tr,
        confirmLabel: 'explore_team_change'.tr,
        cancelLabel: 'explore_keep'.tr,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(exploreRepositoryProvider).setMyTeam(widget.challenge.id, teamId);
      if (!mounted) return;
      showStrideSnack(context, 'explore_team_joined'.tr);
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTeam() async {
    final created = await showStrideSheet<bool>(
      context,
      title: 'explore_team_add'.tr,
      builder: (_) => _TeamForm(challengeId: widget.challenge.id, used: {for (final t in _teams ?? const <ChallengeTeam>[]) t.color}),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final teams = _teams;
    if (teams == null) return const LoadingCard(height: 120);
    final c = widget.challenge;
    final p = c.participation;
    final fmt = ref.watch(formatProvider);
    final now = ref.watch(clockProvider).nowMs();
    final choice = teamChoice(currentTeamId: p?.teamId, teamChanges: p?.teamChanges ?? 0, endsAt: c.endsAt, nowMs: now);
    final standings = computeTeamStandings(teams, _members);
    final counts = {for (final s in standings) s.team.id: s.members};
    final canPick = p != null && choice != TeamChoice.locked && !c.cancelled;
    final lockOpen = choice != TeamChoice.locked;
    return StrideCard(
      key: const Key('challenge-teams'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('explore_teams_title'.tr, style: StrideText.subheading),
          Text('explore_teams_rule'.tr, style: StrideText.caption),
          const Gap(8),
          if (teams.isEmpty) Text(widget.canManage ? 'explore_teams_empty_manager'.tr : 'explore_teams_empty'.tr, style: StrideText.bodySecondary),
          for (final s in standings)
            Padding(
              key: Key('team-${s.team.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('#${s.rank}', style: StrideText.label)),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: StrideColors.teams[s.team.color], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p?.teamId == s.team.id ? 'explore_team_mine'.trArgs([s.team.name]) : s.team.name,
                          style: StrideText.body.copyWith(fontWeight: p?.teamId == s.team.id ? FontWeight.w700 : null),
                        ),
                        Text(
                          'explore_team_score'.trArgs([challengeValue(c.targetType, s.average, fmt), s.members]),
                          style: StrideText.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                  if (canPick && p.teamId != s.team.id)
                    TextButton(
                      key: Key('team-join-${s.team.id}'),
                      onPressed: _busy ? null : () => _join(s.team.id),
                      child: Text(p.teamId == null ? 'explore_team_join'.tr : 'explore_team_switch'.tr),
                    ),
                ],
              ),
            ),
          if (canPick && p.teamId == null && teams.length > 1) ...[
            const Gap(4),
            OutlineButton(
              key: const Key('team-auto'),
              label: 'explore_team_auto'.tr,
              icon: Icons.shuffle,
              onPressed: _busy ? null : () => _join(pickBalancedTeam(teams, counts)!),
            ),
          ],
          const Gap(4),
          Text(
            !lockOpen
                ? 'explore_team_locked'.tr
                : (p?.teamId != null ? 'explore_team_change_left'.trArgs([maxTeamChanges - (p?.teamChanges ?? 0)]) : 'explore_team_lock_note'.tr),
            style: StrideText.caption,
          ),
          if (widget.canManage && lockOpen && teams.length < teamColorCount) ...[
            const Gap(8),
            TextButton.icon(key: const Key('team-add'), onPressed: _addTeam, icon: const Icon(Icons.add), label: Text('explore_team_add'.tr)),
          ],
        ],
      ),
    );
  }
}

class _TeamForm extends ConsumerStatefulWidget {
  const _TeamForm({required this.challengeId, required this.used});
  final String challengeId;
  final Set<int> used;

  @override
  ConsumerState<_TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends ConsumerState<_TeamForm> {
  final _name = TextEditingController();
  late int _color = List.generate(teamColorCount, (i) => i).firstWhere((i) => !widget.used.contains(i), orElse: () => 0);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(exploreRepositoryProvider).createTeam(widget.challengeId, name: _name.text, color: _color);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('team-name'),
        controller: _name,
        maxLength: teamNameMax,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'explore_team_name'.tr),
      ),
      Text('explore_team_color'.tr, style: StrideText.label),
      const Gap(8),
      Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < teamColorCount; i++)
            Semantics(
              selected: _color == i,
              button: true,
              label: 'explore_team_color_n'.trArgs([i + 1]),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = i),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: StrideColors.teams[i],
                        shape: BoxShape.circle,
                        border: _color == i ? Border.all(color: StrideColors.textPrimary, width: 3) : null,
                      ),
                      child: _color == i ? const Icon(Icons.check, color: StrideColors.surface, size: 18) : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const Gap(16),
      PrimaryButton(key: const Key('team-save'), label: 'explore_team_add'.tr, loading: _busy, onPressed: _busy || _name.text.trim().isEmpty ? null : _save),
    ],
  );
}
