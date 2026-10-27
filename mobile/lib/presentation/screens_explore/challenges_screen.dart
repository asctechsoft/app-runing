import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/analytics.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenge_teams.dart';
import 'components/explore_widgets.dart';

String challengeTypeLabel(String t) => switch (t) {
  'run' => 'explore_type_outdoor_runs'.tr,
  'indoorRun' => 'explore_type_indoor_runs'.tr,
  'walk' => 'explore_type_walks'.tr,
  _ => t,
};

/// Giá trị mục tiêu/tiến độ theo loại target (distance: mét, time: ms, count: số hoạt động).
String challengeValue(ChallengeTarget t, double v, StrideFormat fmt) => switch (t) {
  ChallengeTarget.distance => fmt.distance(v),
  ChallengeTarget.time => formatDurationShort(v.round()),
  ChallengeTarget.count => 'explore_activity'.trPlural(v.round(), [v.round()]),
};

/// Challenges catalog (M05).
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'explore_challenges_title'.tr,
      body: !flags.exploreChallenges
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'explore_challenges_unavailable_title'.tr,
              message: 'explore_challenges_unavailable_message'.tr,
            )
          : ExploreGuestGate(
              icon: Icons.emoji_events_outlined,
              title: 'explore_challenges_guest_title'.tr,
              message: 'explore_challenges_guest_message'.tr,
              child: const ChallengeList(),
            ),
    );
  }
}

/// Danh sách thử thách chung, hoặc của một club ([clubId], TM31) kèm nút tạo khi [canCreate] (owner/admin).
class ChallengeList extends ConsumerStatefulWidget {
  const ChallengeList({super.key, this.clubId, this.canCreate = false});
  final String? clubId;
  final bool canCreate;

  @override
  ConsumerState<ChallengeList> createState() => _ChallengeListState();
}

class _ChallengeListState extends ConsumerState<ChallengeList> {
  List<Challenge>? _items;
  ExploreFailure? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await ref.read(exploreRepositoryProvider).challenges(clubId: widget.clubId);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Column(children: [Gap(8), LoadingCard(), Gap(12), LoadingCard()]);
    final fmt = ref.watch(formatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.clubId == null) ExploreHeader(title: 'explore_challenges_title'.tr, subtitle: 'explore_challenges_subtitle'.tr),
        if (widget.canCreate && widget.clubId != null) ...[
          OutlineButton(
            key: const Key('challenge-create'),
            label: 'explore_challenge_create'.tr,
            icon: Icons.add,
            onPressed: () async {
              final id = await context.push<String>(Routes.clubChallengeCreate(widget.clubId!));
              if (id != null && mounted) _load();
            },
          ),
          const Gap(12),
        ],
        if (items.isEmpty)
          EmptyState(icon: Icons.emoji_events_outlined, title: 'explore_challenges_empty_title'.tr, message: 'explore_challenges_empty_message'.tr),
        for (final c in items) ...[
          StrideCard(
            onTap: () async {
              await context.push(Routes.challenge(c.id));
              if (mounted) _load();
            },
            child: Row(
              children: [
                IconBadge(icon: c.participation?.completed == true ? Icons.military_tech : Icons.emoji_events_outlined, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title, style: StrideText.subheading),
                      Text(
                        '${challengeValue(c.targetType, c.targetValue, fmt)} · ${formatLocalDate(c.startDate)} – ${formatLocalDate(c.endDate)}',
                        style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary),
                      ),
                      if (c.participation != null) ...[const Gap(8), _ProgressBar(p: c.participation!)],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: StrideColors.textMuted),
              ],
            ),
          ),
          const Gap(12),
        ],
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.p});
  final ChallengeParticipation p;

  @override
  Widget build(BuildContext context) => Semantics(
    label: p.completed ? 'explore_completed'.tr : 'explore_percent_complete'.trArgs([p.percent]),
    excludeSemantics: true,
    child: Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(StrideRadius.pill),
            child: LinearProgressIndicator(value: p.percent / 100, minHeight: 8, color: StrideColors.primary, backgroundColor: StrideColors.subtle),
          ),
        ),
        const SizedBox(width: 8),
        Text(p.completed ? 'explore_done'.tr : '${p.percent}%', style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    ),
  );
}

/// Chi tiết challenge (M05): thể lệ, Join/Leave, tiến độ từ server, huy hiệu khi hoàn thành.
class ChallengeDetailScreen extends ConsumerWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});
  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'explore_challenge_title'.tr,
      body: !flags.exploreChallenges
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'explore_challenges_unavailable_title'.tr,
              message: 'explore_challenges_unavailable_message'.tr,
            )
          : ExploreGuestGate(
              icon: Icons.emoji_events_outlined,
              title: 'explore_challenges_guest_title'.tr,
              message: 'explore_challenges_guest_message'.tr,
              child: _ChallengeDetailBody(id: challengeId),
            ),
    );
  }
}

class _ChallengeDetailBody extends ConsumerStatefulWidget {
  const _ChallengeDetailBody({required this.id});
  final String id;

  @override
  ConsumerState<_ChallengeDetailBody> createState() => _ChallengeDetailBodyState();
}

class _ChallengeDetailBodyState extends ConsumerState<_ChallengeDetailBody> {
  Challenge? _c;
  ExploreFailure? _error;
  bool _busy = false;

  /// TM31: người xem là owner/admin của club tổ chức (được hủy trước khi bắt đầu).
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(exploreRepositoryProvider);
      var c = await repo.challenge(widget.id);
      if (c.joined) {
        // Tiến độ mới nhất do server tính từ hoạt động đủ điều kiện.
        try {
          c = c.withParticipation(await repo.challengeProgress(widget.id));
        } catch (_) {}
      }
      var manage = false;
      if (c.clubId != null) {
        try {
          manage = (await repo.club(c.clubId!)).membership?.canManage ?? false;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _c = c;
          _canManage = manage;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'explore_challenge_cancel_title'.tr,
      message: 'explore_challenge_cancel_message'.tr,
      confirmLabel: 'explore_challenge_cancel'.tr,
      cancelLabel: 'explore_keep'.tr,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(exploreRepositoryProvider).cancelChallenge(widget.id);
      if (!mounted) return;
      showStrideSnack(context, 'explore_challenge_cancelled'.tr);
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    if (_busy) return; // T04: hai lần chạm trong cùng frame
    setState(() => _busy = true);
    try {
      final c = await ref.read(exploreRepositoryProvider).joinChallenge(widget.id);
      Analytics.challengeJoin(metric: c.targetType.name);
      if (!mounted) return;
      setState(() => _c = c);
      showStrideSnack(context, 'explore_challenge_joined'.trArgs([c.title]));
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'explore_challenge_leave_title'.tr,
      message: 'explore_challenge_leave_message'.tr,
      confirmLabel: 'explore_leave'.tr,
      cancelLabel: 'explore_stay'.tr,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(exploreRepositoryProvider).leaveChallenge(widget.id);
      if (!mounted) return;
      setState(() => _c = c);
      showStrideSnack(context, 'explore_challenge_left'.tr);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final c = _c;
    if (c == null) return const Column(children: [Gap(8), LoadingCard(height: 160), Gap(12), LoadingCard()]);
    final fmt = ref.watch(formatProvider);
    final p = c.participation;
    final now = ref.watch(clockProvider).nowMs();
    final phase = challengePhase(startsAt: c.startsAt, endsAt: c.endsAt, cancelled: c.cancelled, nowMs: now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(8),
        Text(c.title, style: StrideText.title),
        if (c.description.isNotEmpty) ...[const Gap(4), Text(c.description, style: StrideText.bodySecondary)],
        const Gap(12),
        ChallengePhaseBanner(c: c, phase: phase),
        const Gap(16),
        if (p != null) ...[
          StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.completed) ...[
                  Row(
                    children: [
                      const IconBadge(icon: Icons.military_tech, size: 48),
                      const SizedBox(width: 12),
                      Expanded(child: Text('explore_challenge_complete'.tr, style: StrideText.subheading)),
                    ],
                  ),
                  const Gap(12),
                ],
                Text('explore_your_progress'.tr, style: StrideText.label),
                const Gap(4),
                Text(
                  'explore_progress_of'.trArgs([challengeValue(c.targetType, p.progressValue, fmt), challengeValue(c.targetType, c.targetValue, fmt)]),
                  style: StrideText.metricSmall,
                ),
                const Gap(8),
                _ProgressBar(p: p),
                const Gap(8),
                Text('explore_progress_note'.tr, style: StrideText.caption),
                Text('explore_progress_eligible_note'.tr, style: StrideText.caption),
              ],
            ),
          ),
          const Gap(12),
          OutlineButton(
            key: const Key('challenge-leaderboard'),
            label: 'explore_leaderboard'.tr,
            icon: Icons.leaderboard_outlined,
            onPressed: () => context.push(Routes.challengeLeaderboard(c.id)),
          ),
          const Gap(16),
        ],
        // TM41: kết quả (tạm thời trong thời gian chờ đồng bộ, chính thức sau khi khóa).
        if (phase == ChallengePhase.grace || phase == ChallengePhase.finished) ...[
          PrimaryButton(
            key: const Key('challenge-results'),
            label: 'explore_results_title'.tr,
            icon: Icons.emoji_events_outlined,
            onPressed: () => context.push(Routes.challengeResults(c.id)),
          ),
          const Gap(16),
        ],
        if (c.clubId != null && (p != null || _canManage)) ...[
          ChallengeTeams(key: ValueKey('teams-${c.id}-${p?.teamId}'), challenge: c, canManage: _canManage, onChanged: _load),
          const Gap(16),
        ],
        ChallengeRules(c: c, fmt: fmt),
        const Gap(16),
        if (p == null && canJoinChallenge(phase))
          PrimaryButton(label: 'explore_challenge_join'.tr, loading: _busy, onPressed: _busy ? null : _join)
        else if (p != null && canLeaveChallenge(phase) && phase != ChallengePhase.cancelled)
          SecondaryButton(label: 'explore_challenge_leave'.tr, onPressed: _busy ? null : _leave),
        if (_canManage && phase == ChallengePhase.upcoming) ...[
          const Gap(8),
          TextButton(
            key: const Key('challenge-cancel'),
            onPressed: _busy ? null : _cancel,
            child: Text('explore_challenge_cancel'.tr, style: StrideText.label.copyWith(color: StrideColors.error)),
          ),
        ],
      ],
    );
  }
}

/// TM33: pha hiện tại của thử thách — luôn có chữ (không chỉ màu).
class ChallengePhaseBanner extends StatelessWidget {
  const ChallengePhaseBanner({super.key, required this.c, required this.phase});
  final Challenge c;
  final ChallengePhase phase;

  @override
  Widget build(BuildContext context) {
    final graceEnd = DateTime.fromMillisecondsSinceEpoch(c.endsAt + challengeGrace.inMilliseconds);
    final (tone, message) = switch (phase) {
      ChallengePhase.upcoming => (BannerTone.info, 'explore_phase_upcoming'.trArgs([AppDates.monthDay(DateTime.fromMillisecondsSinceEpoch(c.startsAt))])),
      ChallengePhase.active => (BannerTone.info, 'explore_phase_active'.trArgs([AppDates.monthDay(DateTime.fromMillisecondsSinceEpoch(c.endsAt))])),
      ChallengePhase.grace => (BannerTone.warning, 'explore_phase_grace'.trArgs([AppDates.monthDayTime(graceEnd)])),
      ChallengePhase.finished => (BannerTone.info, 'explore_phase_finished'.tr),
      ChallengePhase.cancelled => (BannerTone.warning, 'explore_err_challenge_cancelled'.tr),
    };
    return StatusBanner(key: Key('phase-${phase.name}'), tone: tone, message: message);
  }
}

/// Thể lệ: loại hoạt động, ngày theo múi giờ challenge, mục tiêu.
class ChallengeRules extends StatelessWidget {
  const ChallengeRules({super.key, required this.c, required this.fmt});
  final Challenge c;
  final StrideFormat fmt;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 20, color: StrideColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: StrideText.caption),
                Text(value, style: StrideText.body),
              ],
            ),
          ),
        ],
      ),
    );
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('explore_rules'.tr, style: StrideText.subheading),
          row(Icons.flag_outlined, 'explore_rules_target'.tr, challengeValue(c.targetType, c.targetValue, fmt)),
          row(Icons.directions_run, 'explore_rules_eligible'.tr, c.activityTypes.isEmpty ? missingValue : c.activityTypes.map(challengeTypeLabel).join(', ')),
          row(Icons.date_range_outlined, 'explore_rules_dates'.tr, '${formatLocalDate(c.startDate)} – ${formatLocalDate(c.endDate)}'),
          row(Icons.public, 'explore_rules_time_zone'.tr, c.tzId),
          const Gap(4),
          Text('explore_rules_note'.tr, style: StrideText.caption),
        ],
      ),
    );
  }
}
