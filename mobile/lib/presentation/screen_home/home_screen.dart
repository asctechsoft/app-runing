import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../services/native/permission_coordinator.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../../utils/clock.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../repository/notification_repository.dart';
import '../../services/application/reminder_scheduler.dart';
import '../screen_steps/components/hourly_steps_chart.dart';
import '../screen_steps/components/step_metrics_row.dart';
import '../../services/application/step_source_priority.dart';
import '../../services/application/step_tracking_service.dart';
import '../../controller/steps/steps_logic.dart';
import '../../controller/steps/steps_providers.dart';
import '../../controller/home/home_logic.dart';
import '../../controller/home/home_providers.dart';

/// Home (E06): bước hôm nay theo trạng thái DS §06, biểu đồ giờ, buổi gần nhất, chuỗi tuần.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _kick();
  }

  /// Khởi động adapter bước (chỉ khi có quyền) và đồng bộ lịch nhắc (bắt đổi timezone/quyền).
  Future<void> _kick() async {
    if (!mounted) return;
    ref.invalidate(stepsSourcePriorityProvider); // Data sources có thể đã đổi ưu tiên nguồn
    try {
      await ref.read(stepTrackingServiceProvider).start();
    } catch (_) {}
    if (!mounted) return;
    try {
      await ref.read(remindersSyncProvider)();
    } catch (_) {}
  }

  Future<void> _refresh(String todayKey) async {
    ref.read(permissionsProvider).refresh();
    await _kick();
    ref.invalidate(stepsDayProvider(todayKey));
    ref.invalidate(homeLatestActivityProvider);
    ref.invalidate(homeWeekStreakProvider);
    try {
      await ref.read(stepsDayProvider(todayKey).future);
    } catch (_) {}
  }

  Future<void> _enableAccess(PermStatus p) async {
    final perms = ref.read(permissionsProvider);
    if (p == PermStatus.blocked || p == PermStatus.restricted) {
      await perms.openSettings();
      return;
    }
    final r = await perms.request(PermKind.motion);
    if (isMotionGranted(r)) await ref.read(stepTrackingServiceProvider).start();
  }

  @override
  Widget build(BuildContext context) {
    // Quyền vừa được cấp (vd. quay lại từ settings) → bắt đầu đếm.
    ref.listen(stepsMotionPermissionProvider, (prev, next) {
      final v = next.value;
      if (v != null && isMotionGranted(v)) ref.read(stepTrackingServiceProvider).start();
    });
    // Bấm thông báo nhắc → điều hướng qua router (auth guard của router vẫn áp dụng).
    ref.listen(remindersPendingLinkProvider, (prev, next) {
      if (next == null) return;
      ref.read(remindersPendingLinkProvider.notifier).set(null);
      context.go(next);
    });

    final now = ref.watch(clockProvider).nowLocal();
    final todayKey = localDateKey(now);
    final dayAsync = ref.watch(stepsDayProvider(todayKey));
    final settings = ref.watch(settingsProvider).value;
    final fmt = ref.watch(formatProvider);
    final tracking = ref.watch(stepTrackingStatusProvider).value ?? StepTrackingStatus.idle;
    final g = MediaQuery.sizeOf(context).width < 360 ? StrideSpace.gutterSmall : StrideSpace.gutter;

    final view = dayAsync.value;
    final state = view == null ? null : decideHomeStepState(permission: view.permission, day: view.day, goal: view.goal, tracking: tracking);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: RefreshIndicator(
              onRefresh: () => _refresh(todayKey),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(g, StrideSpace.s8, g, StrideSpace.s32),
                children: [
                  _Header(settings: settings),
                  const Gap(StrideSpace.s16),
                  _Greeting(now: now, name: settings?.displayName, achieved: state == HomeStepState.achieved),
                  const Gap(StrideSpace.s16),
                  dayAsync.when(
                    skipLoadingOnRefresh: true,
                    skipLoadingOnReload: true,
                    loading: () => const LoadingCard(height: 320),
                    error: (e, _) => StrideCard(
                      child: ErrorState(
                        title: "Couldn't load today's steps",
                        message: 'Step data on this device could not be read.',
                        onRetry: () => ref.invalidate(stepsDayProvider(todayKey)),
                      ),
                    ),
                    data: (v) => _StepsCard(view: v, state: state!, settings: settings, format: fmt, onEnable: () => _enableAccess(v.permission)),
                  ),
                  if (view != null && state != HomeStepState.noPermission && state != HomeStepState.unavailable) ...[
                    const Gap(StrideSpace.s16),
                    SectionHeader(
                      title: 'Steps today',
                      subtitle: 'Your activity throughout the day',
                      actionLabel: 'View details',
                      onAction: () => context.push('${Routes.dailySteps}?date=$todayKey'),
                    ),
                    StrideCard(
                      onTap: () => context.push('${Routes.dailySteps}?date=$todayKey'),
                      semanticLabel: 'Open daily steps',
                      child: view.day.hasValue
                          ? HourlyStepsChart(
                              entries: hourEntries(view.day, todayKey: todayKey, nowHour: now.hour),
                              format: fmt,
                              source: view.day.sourceUsed,
                              height: 120,
                              compact: true,
                            )
                          : SizedBox(
                              height: 72,
                              child: Center(
                                child: Text(
                                  'Your hourly steps will appear here once data arrives.',
                                  style: StrideText.bodySecondary,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                    ),
                  ],
                  const Gap(StrideSpace.s16),
                  const _LatestActivitySection(),
                  const Gap(StrideSpace.s16),
                  const _WeekStreakSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.settings});
  final UserSettings? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final unread = flags.notificationsInbox ? (ref.watch(notificationsUnreadProvider).value ?? 0) : 0;
    final name = settings?.displayName.trim() ?? '';
    return Row(
      children: [
        const StrideWordmark(),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Profile',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => context.go(Routes.profile),
            radius: 28,
            child: SizedBox(
              width: StrideSpace.touchTarget,
              height: StrideSpace.touchTarget,
              child: Center(
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: StrideColors.subtle,
                  foregroundColor: StrideColors.primary,
                  child: name.isEmpty ? const Icon(Icons.person_outline, size: 20) : Text(name.characters.first.toUpperCase(), style: StrideText.label),
                ),
              ),
            ),
          ),
        ),
        if (flags.notificationsInbox)
          IconButton(
            tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
            onPressed: () => context.push(Routes.notifications),
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none)),
          ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now, required this.name, required this.achieved});
  final DateTime now;
  final String? name;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(achieved ? (first.isEmpty ? 'You did it!' : 'You did it, $first!') : greetingFor(now, name), style: StrideText.title),
          Text(achieved ? 'Daily goal achieved' : DateFormat('EEEE, MMMM d, y').format(now), style: StrideText.bodySecondary),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.view, required this.state, required this.settings, required this.format, required this.onEnable});
  final StepsDayView view;
  final HomeStepState state;
  final UserSettings? settings;
  final StrideFormat format;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case HomeStepState.noPermission:
        final blocked = view.permission == PermStatus.blocked || view.permission == PermStatus.restricted;
        return StrideCard(
          child: Column(
            children: [
              const IconBadge(icon: Icons.directions_walk, size: 56),
              const Gap(StrideSpace.s12),
              Text('Turn on step tracking', style: StrideText.subheading, textAlign: TextAlign.center),
              const Gap(StrideSpace.s8),
              Text(
                'STRIDE uses your phone\'s motion sensor to count daily steps. Location is only used when you start a run.',
                style: StrideText.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const Gap(StrideSpace.s16),
              PrimaryButton(label: blocked ? 'Open phone settings' : 'Enable access', onPressed: onEnable),
            ],
          ),
        );
      case HomeStepState.unavailable:
        return StrideCard(
          child: Column(
            children: [
              const IconBadge(icon: Icons.sensors_off_outlined, size: 56),
              const Gap(StrideSpace.s12),
              Text("Step counting isn't available on this device", style: StrideText.subheading, textAlign: TextAlign.center),
              const Gap(StrideSpace.s8),
              Text('You can still record runs and walks with GPS.', style: StrideText.bodySecondary, textAlign: TextAlign.center),
            ],
          ),
        );
      case HomeStepState.noData:
      case HomeStepState.verifiedZero:
      case HomeStepState.populated:
      case HomeStepState.achieved:
        return _ringCard(context);
    }
  }

  Widget _ringCard(BuildContext context) {
    final day = view.day;
    final goal = view.goal;
    final steps = day.hasValue ? day.steps : null;
    final achieved = state == HomeStepState.achieved;
    final progress = steps == null || goal == null || goal <= 0 ? null : steps / goal;
    final pct = progress == null ? null : (progress * 100).round();
    final trackingOff = day.hasValue && !isMotionGranted(view.permission);
    final semantic = steps == null
        ? 'No step data yet'
        : '${format.steps(steps)} steps${goal == null ? '' : ' of ${format.steps(goal)} goal'}${pct == null ? '' : ', $pct percent'}';

    return StrideCard(
      child: Column(
        children: [
          Row(
            children: [
              if (achieved) const IconBadge(icon: Icons.emoji_events_outlined, size: 32),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.push(Routes.homeGoals),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(goal == null ? 'Set goal' : 'Edit goal'),
              ),
            ],
          ),
          if (trackingOff) ...[
            StatusBanner(tone: BannerTone.warning, message: 'Step tracking is off. Showing steps recorded earlier.', actionLabel: 'Enable', onAction: onEnable),
            const Gap(StrideSpace.s12),
          ],
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push('${Routes.dailySteps}?date=${day.date}'),
            child: ProgressRing(
              progress: progress,
              size: 200,
              semanticLabel: semantic,
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_walk, color: StrideColors.primary),
                    Text(steps == null ? missingValue : format.steps(steps), style: StrideText.metric.copyWith(fontSize: 40)),
                    if (steps == null)
                      Text('No step data yet', style: StrideText.caption)
                    else if (achieved)
                      Text('steps · $pct%', style: StrideText.label.copyWith(color: StrideColors.primary))
                    else
                      Text(goal == null ? 'steps' : '/ ${format.steps(goal)}', style: StrideText.label.copyWith(color: StrideColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          const Gap(StrideSpace.s8),
          Text(_statusLine(), style: StrideText.caption, textAlign: TextAlign.center),
          const Gap(StrideSpace.s16),
          StepMetricsRow(
            steps: steps,
            settings: settings,
            format: format,
            activeMinutes: view.activeMinutes,
            onAddProfile: () => context.go(Routes.editProfile),
          ),
          if (achieved) ...[
            const Gap(StrideSpace.s16),
            // Không tự tăng mục tiêu, không che CTA chạy (DS §06).
            PrimaryButton(label: 'Keep moving', trailingIcon: Icons.arrow_forward, onPressed: () => context.go(Routes.run)),
            const Gap(StrideSpace.s8),
            SecondaryButton(label: 'Adjust goal', onPressed: () => context.push(Routes.homeGoals)),
          ],
        ],
      ),
    );
  }

  String _statusLine() {
    final day = view.day;
    if (!day.hasValue) return 'Last checked ${DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(view.checkedAt))}';
    final goalText = view.goal == null ? 'No daily goal set' : '${format.steps(view.goal)} steps goal';
    final last = day.lastSampleAt;
    if (last == null) return goalText;
    return '$goalText · Updated ${DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(last))}';
  }
}

class _LatestActivitySection extends ConsumerWidget {
  const _LatestActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeLatestActivityProvider);
    final fmt = ref.watch(formatProvider);
    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const LoadingCard(height: 96),
      error: (e, _) => StrideCard(
        child: ErrorState(
          title: "Couldn't load your runs",
          message: 'Activities on this device could not be read.',
          onRetry: () => ref.invalidate(homeLatestActivityProvider),
        ),
      ),
      data: (a) {
        if (a == null) {
          return SageCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No runs yet', style: StrideText.subheading),
                      const Gap(StrideSpace.s4),
                      Text('Get moving with your first run.', style: StrideText.bodySecondary),
                      const Gap(StrideSpace.s12),
                      PrimaryButton(label: 'Start your first run', trailingIcon: Icons.arrow_forward, expand: false, onPressed: () => context.go(Routes.run)),
                    ],
                  ),
                ),
                const SizedBox(width: StrideSpace.s12),
                const IconBadge(icon: Icons.directions_run, size: 56),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: 'Latest activity', actionLabel: 'View all', onAction: () => context.go(Routes.history)),
            _ActivityCard(activity: a, format: fmt, onTap: () => context.push(Routes.homeActivity(a.id))),
          ],
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.format, required this.onTap});
  final Activity activity;
  final StrideFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final typeLabel = switch (a.type) {
      ActivityType.run => 'Run',
      ActivityType.walk => 'Walk',
      ActivityType.indoorRun => 'Indoor run',
    };
    final title = a.title.trim().isEmpty ? typeLabel : a.title;
    final start = DateTime.fromMillisecondsSinceEpoch(a.startedAt, isUtc: true).add(Duration(minutes: a.tzOffsetMin));
    final estimated = a.distanceSource == DistanceSource.steps;
    return StrideCard(
      onTap: onTap,
      semanticLabel: '$title, ${DateFormat('EEEE, MMMM d').format(start)}',
      child: Row(
        children: [
          IconBadge(icon: a.type == ActivityType.walk ? Icons.directions_walk : Icons.directions_run, size: 48),
          const SizedBox(width: StrideSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: StrideText.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('${DateFormat('EEE, MMM d').format(start)} · ${DateFormat.jm().format(start)}', style: StrideText.caption),
                const Gap(StrideSpace.s8),
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Distance',
                        value: format.distanceValue(a.distanceM),
                        unit: a.distanceM == null ? null : format.distanceUnitLabel,
                        estimated: estimated,
                      ),
                    ),
                    Expanded(
                      child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs)),
                    ),
                    Expanded(
                      child: MetricTile(
                        label: 'Avg. pace',
                        value: format.paceValue(a.avgPaceSecPerKm),
                        unit: a.avgPaceSecPerKm == null ? null : format.paceUnitLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: StrideColors.textSecondary),
        ],
      ),
    );
  }
}

class _WeekStreakSection extends ConsumerWidget {
  const _WeekStreakSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeWeekStreakProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Your week streak',
          subtitle: 'Reach your step goal each day to build your streak.',
          actionLabel: 'View details',
          onAction: () => context.go(Routes.progress),
        ),
        async.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingCard(height: 88),
          error: (e, _) => StrideCard(
            child: ErrorState(
              title: "Couldn't load your streak",
              message: 'Step data on this device could not be read.',
              onRetry: () => ref.invalidate(homeWeekStreakProvider),
            ),
          ),
          data: (w) => StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${w.achievedCount} of 7 days', style: StrideText.label),
                const Gap(StrideSpace.s12),
                Row(
                  children: [for (final d in w.days) Expanded(child: _StreakDot(day: d))],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StreakDot extends StatelessWidget {
  const _StreakDot({required this.day});
  final StreakDay day;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('E').format(day.date);
    final (Color bg, Color border, Widget inner, String status) = switch (day.status) {
      StreakDayStatus.achieved => (StrideColors.lime, StrideColors.lime, const Icon(Icons.check, size: 18, color: StrideColors.primary), 'goal reached'),
      StreakDayStatus.missed => (StrideColors.surface, StrideColors.borderControl, const SizedBox.shrink(), 'goal not reached'),
      StreakDayStatus.noData => (StrideColors.surface, StrideColors.borderSubtle, Text(missingValue, style: StrideText.caption), 'no step data'),
      StreakDayStatus.future => (StrideColors.subtle, StrideColors.subtle, const SizedBox.shrink(), 'upcoming'),
    };
    return Semantics(
      label: '${DateFormat('EEEE').format(day.date)}, $status',
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 1.5),
            ),
            child: inner,
          ),
          const Gap(StrideSpace.s4),
          Text(label, style: StrideText.caption),
        ],
      ),
    );
  }
}
