import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'explore_models.dart';
import 'explore_repository.dart';
import 'explore_widgets.dart';

String challengeTypeLabel(String t) => switch (t) {
  'run' => 'Outdoor runs',
  'indoorRun' => 'Indoor runs',
  'walk' => 'Walks',
  _ => t,
};

/// Giá trị mục tiêu/tiến độ theo loại target (distance: mét, time: ms, count: số hoạt động).
String challengeValue(ChallengeTarget t, double v, StrideFormat fmt) => switch (t) {
  ChallengeTarget.distance => fmt.distance(v),
  ChallengeTarget.time => formatDurationShort(v.round()),
  ChallengeTarget.count => v.round() == 1 ? '1 activity' : '${v.round()} activities',
};

/// Challenges catalog (M05).
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'Challenges',
      body: !flags.exploreChallenges
          ? const EmptyState(icon: Icons.emoji_events_outlined, title: 'Challenges aren’t available', message: 'Challenges aren’t turned on in this version.')
          : const ExploreGuestGate(
              icon: Icons.emoji_events_outlined,
              title: 'Sign in to join challenges',
              message: 'Progress is calculated from your synced activities, so you need an account.',
              child: _ChallengesBody(),
            ),
    );
  }
}

class _ChallengesBody extends ConsumerStatefulWidget {
  const _ChallengesBody();

  @override
  ConsumerState<_ChallengesBody> createState() => _ChallengesBodyState();
}

class _ChallengesBodyState extends ConsumerState<_ChallengesBody> {
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
      final list = await ref.read(exploreRepositoryProvider).challenges();
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
        const ExploreHeader(title: 'Challenges', subtitle: 'Set yourself a new challenge.'),
        if (items.isEmpty)
          const EmptyState(icon: Icons.emoji_events_outlined, title: 'No challenges right now', message: 'Check back soon for new challenges.'),
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
    label: p.completed ? 'Completed' : '${p.percent} percent complete',
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
        Text(p.completed ? 'Done' : '${p.percent}%', style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
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
      title: 'Challenge',
      body: !flags.exploreChallenges
          ? const EmptyState(icon: Icons.emoji_events_outlined, title: 'Challenges aren’t available', message: 'Challenges aren’t turned on in this version.')
          : ExploreGuestGate(
              icon: Icons.emoji_events_outlined,
              title: 'Sign in to join challenges',
              message: 'Progress is calculated from your synced activities, so you need an account.',
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
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(exploreRepositoryProvider).joinChallenge(widget.id);
      if (!mounted) return;
      setState(() => _c = c);
      showStrideSnack(context, 'You joined ${c.title}');
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await confirmDialog(
      context,
      title: 'Leave challenge?',
      message: 'Your progress won’t be shown while you’re not taking part.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(exploreRepositoryProvider).leaveChallenge(widget.id);
      if (!mounted) return;
      setState(() => _c = c);
      showStrideSnack(context, 'You left the challenge');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(8),
        Text(c.title, style: StrideText.title),
        if (c.description.isNotEmpty) ...[const Gap(4), Text(c.description, style: StrideText.bodySecondary)],
        const Gap(16),
        if (p != null) ...[
          StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.completed) ...[
                  const Row(
                    children: [
                      IconBadge(icon: Icons.military_tech, size: 48),
                      SizedBox(width: 12),
                      Expanded(child: Text('Challenge complete! Badge earned.', style: StrideText.subheading)),
                    ],
                  ),
                  const Gap(12),
                ],
                Text('Your progress', style: StrideText.label),
                const Gap(4),
                Text(
                  '${challengeValue(c.targetType, p.progressValue, fmt)} of ${challengeValue(c.targetType, c.targetValue, fmt)}',
                  style: StrideText.metricSmall,
                ),
                const Gap(8),
                _ProgressBar(p: p),
                const Gap(8),
                Text('Progress is calculated by STRIDE from eligible activities after they sync.', style: StrideText.caption),
              ],
            ),
          ),
          const Gap(16),
        ],
        ChallengeRules(c: c, fmt: fmt),
        const Gap(16),
        if (p == null)
          PrimaryButton(label: 'Join challenge', loading: _busy, onPressed: _busy ? null : _join)
        else
          SecondaryButton(label: 'Leave challenge', onPressed: _busy ? null : _leave),
      ],
    );
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
          Text('Rules', style: StrideText.subheading),
          row(Icons.flag_outlined, 'Target', challengeValue(c.targetType, c.targetValue, fmt)),
          row(Icons.directions_run, 'Eligible activities', c.activityTypes.isEmpty ? missingValue : c.activityTypes.map(challengeTypeLabel).join(', ')),
          row(Icons.date_range_outlined, 'Dates', '${formatLocalDate(c.startDate)} – ${formatLocalDate(c.endDate)}'),
          row(Icons.public, 'Time zone', c.tzId),
          const Gap(4),
          Text('Only activities started within these dates in this time zone count. Activities outside the dates don’t count.', style: StrideText.caption),
        ],
      ),
    );
  }
}
