import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../controller/badges/badges_providers.dart';
import '../../controller/explore/group_sharing.dart';
import '../../controller/home/home_logic.dart';
import '../../controller/home/home_providers.dart';
import '../../controller/providers.dart';
import '../../controller/steps/steps_logic.dart';
import '../../controller/steps/steps_providers.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../repository/notification_repository.dart';
import '../../services/application/reminder_scheduler.dart';
import '../../services/application/step_source_priority.dart';
import '../../services/application/step_tracking_service.dart';
import '../../services/native/permission_coordinator.dart';
import '../../utils/analytics.dart';
import '../../utils/clock.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/streak_summary.dart';
import '../common_components/widgets.dart';
import '../screen_steps/components/hourly_steps_chart.dart';
import '../screen_steps/components/step_metrics_row.dart';
import '../screens_progress/badges_screen.dart';

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
    // TM21/TM22: cập nhật số liệu nhóm ở các club tôi đang chia sẻ.
    try {
      await ref.read(groupSharingProvider).publishAll();
    } catch (_) {}
  }

  Future<void> _refresh(String todayKey) async {
    ref.read(permissionsProvider).refresh();
    await _kick();
    ref.invalidate(stepsDayProvider(todayKey));
    ref.invalidate(homeLatestActivityProvider);
    ref.invalidate(homeWeekStreakProvider);
    ref.invalidate(personalStreakProvider);
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
    // TM52: hôm nay vừa đạt (hoặc chuỗi đổi) → đặt lại nhắc giữ chuỗi để không nhắc khi đã đạt.
    ref.listen(personalStreakProvider, (prev, next) {
      final a = prev?.value;
      final b = next.value;
      if (b != null && a != null && (a.todayAchieved != b.todayAchieved || (a.current > 0) != (b.current > 0))) {
        ref.read(remindersSyncProvider)().catchError((_) {});
      }
      // TM76: chỉ ghi khi chuỗi tăng qua mốc trong phiên này (không ghi lại mỗi lần mở app).
      final m = (a != null && b != null) ? Analytics.crossedStreakMilestone(a.current, b.current) : null;
      if (m != null) Analytics.streakMilestone(days: m);
    });
    // TM40: huy hiệu mới → báo một lần (đánh dấu đã thấy trước khi mở hộp thoại để không lặp khi dựng lại).
    ref.listen(badgesProvider, (prev, next) async {
      final fresh = next.value?.fresh ?? const [];
      if (fresh.isEmpty) return;
      await ref.read(markBadgesSeenProvider)(fresh.map((b) => b.id));
      for (final b in fresh) {
        Analytics.badgeEarned(kind: b.kind.name);
      }
      ref.invalidate(badgesProvider);
      if (context.mounted) await showBadgeEarnedDialog(context, fresh);
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
                        title: 'home_steps_error_title'.tr,
                        message: 'home_steps_error_message'.tr,
                        onRetry: () => ref.invalidate(stepsDayProvider(todayKey)),
                      ),
                    ),
                    data: (v) => _StepsCard(view: v, state: state!, settings: settings, format: fmt, onEnable: () => _enableAccess(v.permission)),
                  ),
                  if (view != null && state != HomeStepState.noPermission && state != HomeStepState.unavailable) ...[
                    const Gap(StrideSpace.s16),
                    SectionHeader(
                      title: 'home_steps_today_title'.tr,
                      subtitle: 'home_steps_today_subtitle'.tr,
                      actionLabel: 'home_view_details'.tr,
                      onAction: () => context.push('${Routes.dailySteps}?date=$todayKey'),
                    ),
                    StrideCard(
                      onTap: () => context.push('${Routes.dailySteps}?date=$todayKey'),
                      semanticLabel: 'home_open_daily_steps'.tr,
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
                                child: Text('home_hourly_empty'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
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
          label: 'home_profile'.tr,
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
            tooltip: unread > 0 ? 'home_notifications_unread'.trArgs([unread]) : 'home_notifications'.tr,
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
          Text(
            achieved ? (first.isEmpty ? 'home_achieved_title'.tr : 'home_achieved_title_name'.trArgs([first])) : greetingFor(now, name),
            style: StrideText.title,
          ),
          Text(achieved ? 'home_goal_achieved'.tr : AppDates.longDate(now), style: StrideText.bodySecondary),
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
              Text('home_enable_title'.tr, style: StrideText.subheading, textAlign: TextAlign.center),
              const Gap(StrideSpace.s8),
              Text('home_enable_message'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
              const Gap(StrideSpace.s16),
              PrimaryButton(label: blocked ? 'home_open_phone_settings'.tr : 'home_enable_access'.tr, onPressed: onEnable),
            ],
          ),
        );
      case HomeStepState.unavailable:
        return StrideCard(
          child: Column(
            children: [
              const IconBadge(icon: Icons.sensors_off_outlined, size: 56),
              const Gap(StrideSpace.s12),
              Text('home_unavailable_title'.tr, style: StrideText.subheading, textAlign: TextAlign.center),
              const Gap(StrideSpace.s8),
              Text('home_unavailable_message'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
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
        ? 'home_no_step_data'.tr
        : '${'home_semantic_steps'.trArgs([format.steps(steps)])}${goal == null ? '' : 'home_semantic_of_goal'.trArgs([format.steps(goal)])}${pct == null ? '' : 'home_semantic_percent'.trArgs([pct])}';

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
                label: Text(goal == null ? 'home_set_goal'.tr : 'home_edit_goal'.tr),
              ),
            ],
          ),
          if (trackingOff) ...[
            StatusBanner(tone: BannerTone.warning, message: 'home_tracking_off'.tr, actionLabel: 'home_enable'.tr, onAction: onEnable),
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
                      Text('home_no_step_data'.tr, style: StrideText.caption)
                    else if (achieved)
                      Text('home_steps_percent'.trArgs([pct]), style: StrideText.label.copyWith(color: StrideColors.primary))
                    else
                      Text(
                        goal == null ? 'home_steps_unit'.tr : 'home_of_goal'.trArgs([format.steps(goal)]),
                        style: StrideText.label.copyWith(color: StrideColors.textSecondary),
                      ),
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
            PrimaryButton(label: 'home_keep_moving'.tr, trailingIcon: Icons.arrow_forward, onPressed: () => context.go(Routes.run)),
            const Gap(StrideSpace.s8),
            SecondaryButton(label: 'home_adjust_goal'.tr, onPressed: () => context.push(Routes.homeGoals)),
          ],
        ],
      ),
    );
  }

  String _statusLine() {
    final day = view.day;
    if (!day.hasValue) return 'home_last_checked'.trArgs([DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(view.checkedAt))]);
    final goalText = view.goal == null ? 'home_no_goal'.tr : 'home_goal_steps'.trArgs([format.steps(view.goal)]);
    final last = day.lastSampleAt;
    if (last == null) return goalText;
    return 'home_goal_updated'.trArgs([goalText, DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(last))]);
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
        child: ErrorState(title: 'home_runs_error_title'.tr, message: 'home_runs_error_message'.tr, onRetry: () => ref.invalidate(homeLatestActivityProvider)),
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
                      Text('home_no_runs_title'.tr, style: StrideText.subheading),
                      const Gap(StrideSpace.s4),
                      Text('home_no_runs_message'.tr, style: StrideText.bodySecondary),
                      const Gap(StrideSpace.s12),
                      PrimaryButton(
                        label: 'home_start_first_run'.tr,
                        trailingIcon: Icons.arrow_forward,
                        expand: false,
                        onPressed: () => context.go(Routes.run),
                      ),
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
            SectionHeader(title: 'home_latest_activity'.tr, actionLabel: 'home_view_all'.tr, onAction: () => context.go(Routes.history)),
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
      ActivityType.run => 'home_type_run'.tr,
      ActivityType.walk => 'home_type_walk'.tr,
      ActivityType.indoorRun => 'home_type_indoor_run'.tr,
    };
    final title = a.title.trim().isEmpty ? typeLabel : a.title;
    final start = DateTime.fromMillisecondsSinceEpoch(a.startedAt, isUtc: true).add(Duration(minutes: a.tzOffsetMin));
    final estimated = a.distanceSource == DistanceSource.steps;
    return StrideCard(
      onTap: onTap,
      semanticLabel: '$title, ${AppDates.weekdayMonthDay(start)}',
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
                Text(AppDates.shortWeekdayDateTime(start), style: StrideText.caption),
                const Gap(StrideSpace.s8),
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'home_distance'.tr,
                        value: format.distanceValue(a.distanceM),
                        unit: a.distanceM == null ? null : format.distanceUnitLabel,
                        estimated: estimated,
                      ),
                    ),
                    Expanded(
                      child: MetricTile(label: 'home_moving_time'.tr, value: formatDuration(a.movingMs)),
                    ),
                    Expanded(
                      child: MetricTile(
                        label: 'home_avg_pace'.tr,
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
          title: 'home_streak_title'.tr,
          subtitle: 'home_streak_subtitle'.tr,
          actionLabel: 'home_view_details'.tr,
          onAction: () => context.go(Routes.progress),
        ),
        async.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingCard(height: 88),
          error: (e, _) => StrideCard(
            child: ErrorState(
              title: 'home_streak_error_title'.tr,
              message: 'home_steps_error_message'.tr,
              onRetry: () => ref.invalidate(homeWeekStreakProvider),
            ),
          ),
          data: (w) => StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('home_streak_days'.trArgs([w.achievedCount]), style: StrideText.label),
                const Gap(StrideSpace.s12),
                Row(
                  children: [for (final d in w.days) Expanded(child: _StreakDot(day: d))],
                ),
                const _CurrentStreak(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// TM20: lỗi hoặc đang tải → ẩn (khối tuần phía trên vẫn hiển thị).
class _CurrentStreak extends ConsumerWidget {
  const _CurrentStreak();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(personalStreakProvider).value;
    return s == null ? const SizedBox.shrink() : StreakSummaryView(summary: s);
  }
}

class _StreakDot extends StatelessWidget {
  const _StreakDot({required this.day});
  final StreakDay day;

  @override
  Widget build(BuildContext context) {
    final label = AppDates.weekdayShort(day.date);
    final (Color bg, Color border, Widget inner, String status) = switch (day.status) {
      StreakDayStatus.achieved => (
        StrideColors.lime,
        StrideColors.lime,
        const Icon(Icons.check, size: 18, color: StrideColors.primary),
        'home_day_goal_reached'.tr,
      ),
      StreakDayStatus.missed => (StrideColors.surface, StrideColors.borderControl, const SizedBox.shrink(), 'home_day_goal_missed'.tr),
      StreakDayStatus.noData => (StrideColors.surface, StrideColors.borderSubtle, Text(missingValue, style: StrideText.caption), 'home_day_no_data'.tr),
      StreakDayStatus.future => (StrideColors.subtle, StrideColors.subtle, const SizedBox.shrink(), 'home_day_upcoming'.tr),
    };
    return Semantics(
      label: 'home_day_semantic'.trArgs([AppDates.weekday(day.date), status]),
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
