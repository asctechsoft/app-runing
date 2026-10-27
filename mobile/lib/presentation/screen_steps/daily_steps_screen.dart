import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../controller/providers.dart';
import '../../controller/steps/steps_logic.dart';
import '../../controller/steps/steps_providers.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/steps.dart';
import '../../services/application/step_source_priority.dart';
import '../../services/native/permission_coordinator.dart';
import '../../utils/clock.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/hourly_steps_chart.dart';
import 'components/step_metrics_row.dart';

/// Chi tiết bước theo ngày (F04): chọn ngày, biểu đồ giờ, mục tiêu theo goal history, nguồn + thời điểm cập nhật.
class DailyStepsScreen extends ConsumerStatefulWidget {
  const DailyStepsScreen({super.key, this.date});
  final String? date;

  @override
  ConsumerState<DailyStepsScreen> createState() => _DailyStepsScreenState();
}

class _DailyStepsScreenState extends ConsumerState<DailyStepsScreen> {
  late DateTime _day;
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    final today = _today();
    DateTime? parsed;
    try {
      parsed = widget.date == null ? null : parseDateKey(widget.date!);
    } catch (_) {
      parsed = null;
    }
    _day = parsed == null || parsed.isAfter(today) ? today : DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime _today() {
    final n = ref.read(clockProvider).nowLocal();
    return DateTime(n.year, n.month, n.day);
  }

  void _shift(int days) {
    final next = DateTime(_day.year, _day.month, _day.day + days);
    if (next.isAfter(_today())) return;
    setState(() => _day = next);
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      helpText: 'steps_choose_day'.tr,
    );
    if (picked != null && mounted) setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final key = localDateKey(_day);
    final async = ref.watch(stepsDayProvider(key));
    final fmt = ref.watch(formatProvider);
    final settings = ref.watch(settingsProvider).value;
    final today = _today();
    final isToday = _day == today;
    final now = ref.watch(clockProvider).nowLocal();

    return StrideScreen(
      title: 'steps_title'.tr,
      scroll: false,
      padding: EdgeInsets.zero,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(permissionsProvider).refresh();
          ref.invalidate(stepsSourcePriorityProvider);
          ref.invalidate(stepsDayProvider(key));
          try {
            await ref.read(stepsDayProvider(key).future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: StrideScreen.gutterOf(context), vertical: StrideSpace.s8),
          children: [
            _DateBar(
              label: isToday ? 'steps_today_label'.trArgs([AppDates.monthDay(_day)]) : AppDates.shortWeekdayDateYear(_day),
              onPrev: () => _shift(-1),
              onNext: isToday ? null : () => _shift(1),
              onPick: _pickDate,
            ),
            const Gap(StrideSpace.s16),
            async.when(
              loading: () => const Column(children: [LoadingCard(height: 120), Gap(StrideSpace.s16), LoadingCard(height: 220)]),
              error: (e, _) =>
                  ErrorState(title: 'steps_error_title'.tr, message: 'steps_error_message'.tr, onRetry: () => ref.invalidate(stepsDayProvider(key))),
              data: (v) => _content(context, v, fmt, settings, isToday, now),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, StepsDayView v, StrideFormat fmt, UserSettings? settings, bool isToday, DateTime now) {
    final day = v.day;
    final entries = hourEntries(day, todayKey: localDateKey(_today()), nowHour: now.hour);
    final children = <Widget>[];

    // Tóm tắt
    children.add(
      StrideCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (day.status == StepDayStatus.noPermission) ...[
              Text('steps_tracking_off'.tr, style: StrideText.subheading),
              const Gap(StrideSpace.s4),
              Text(isToday ? 'steps_turn_on_motion'.tr : 'steps_no_data_day'.tr, style: StrideText.bodySecondary),
              if (isToday) ...[const Gap(StrideSpace.s12), _enableButton(v.permission)],
            ] else if (day.status == StepDayStatus.noData) ...[
              Text('steps_no_data_title'.tr, style: StrideText.subheading),
              const Gap(StrideSpace.s4),
              Text(
                isToday
                    ? 'steps_last_checked'.trArgs([DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(v.checkedAt))])
                    : 'steps_none_recorded_day'.tr,
                style: StrideText.bodySecondary,
              ),
            ] else ...[
              Semantics(
                label: v.goal == null ? 'steps_count'.trArgs([fmt.steps(day.steps)]) : 'steps_semantic_goal'.trArgs([fmt.steps(day.steps), fmt.steps(v.goal)]),
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: fmt.steps(day.steps), style: StrideText.metric),
                      TextSpan(
                        text: v.goal == null ? ' ${'steps_unit'.tr}' : ' / ${fmt.steps(v.goal)}',
                        style: StrideText.subheading.copyWith(color: StrideColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                v.goal == null
                    ? 'steps_no_goal_day'.tr
                    : (day.steps! >= v.goal!
                          ? 'steps_goal_reached'.trArgs(['${(day.steps! * 100 / v.goal!).round()}%'])
                          : 'steps_goal_percent'.trArgs(['${(day.steps! * 100 / v.goal!).round()}%'])),
                style: StrideText.bodySecondary,
              ),
            ],
          ],
        ),
      ),
    );
    children.add(const Gap(StrideSpace.s16));

    // Biểu đồ
    children.add(
      StrideCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('steps_by_hour'.tr, style: StrideText.subheading),
            const Gap(StrideSpace.s12),
            HourlyStepsChart(
              entries: entries,
              format: fmt,
              source: day.sourceUsed,
              targetPerHour: v.goal == null || !day.hasValue ? null : v.goal! / 24,
              height: 200,
            ),
            const Gap(StrideSpace.s8),
            Text('${'steps_chart_note'.trArgs([missingValue])}${v.goal == null ? '' : ' ${'steps_chart_note_goal'.tr}'}', style: StrideText.caption),
            const Gap(StrideSpace.s8),
            TextButton.icon(
              onPressed: () => setState(() => _showList = !_showList),
              icon: Icon(_showList ? Icons.expand_less : Icons.list),
              label: Text(_showList ? 'steps_hide_hourly_list'.tr : 'steps_show_hourly_list'.tr),
            ),
            if (_showList) HourlyStepsList(entries: entries, format: fmt),
          ],
        ),
      ),
    );
    children.add(const Gap(StrideSpace.s16));

    children.add(
      StrideCard(
        child: StepMetricsRow(
          steps: day.hasValue ? day.steps : null,
          settings: settings,
          format: fmt,
          activeMinutes: v.activeMinutes,
          onAddProfile: () => context.go(Routes.editProfile),
        ),
      ),
    );
    children.add(const Gap(StrideSpace.s16));

    children.add(
      SettingsGroup(
        children: [
          SettingsRow(
            icon: Icons.smartphone_outlined,
            title: 'steps_source_title'.trArgs([sourceLabel(day.sourceUsed)]),
            subtitle: day.lastSampleAt == null ? 'steps_no_samples'.tr : 'steps_updated'.trArgs([_updatedLabel(day.lastSampleAt!)]),
            onTap: () => context.go(Routes.dataSources),
          ),
          SettingsRow(
            icon: Icons.flag_outlined,
            title: 'steps_edit_goal'.tr,
            subtitle: v.goal == null ? 'steps_no_goal_day'.tr : 'steps_goal_for_day'.trArgs([fmt.steps(v.goal)]),
            onTap: () => context.push(Routes.homeGoals),
          ),
        ],
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  String _updatedLabel(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = ref.read(clockProvider).nowLocal();
    if (t.year == now.year && t.month == now.month && t.day == now.day) return DateFormat.jm().format(t);
    return AppDates.monthDayTime(t);
  }

  Widget _enableButton(PermStatus p) {
    final blocked = p == PermStatus.blocked || p == PermStatus.restricted;
    return PrimaryButton(
      label: blocked ? 'steps_open_settings'.tr : 'steps_enable_access'.tr,
      expand: false,
      onPressed: () async {
        final perms = ref.read(permissionsProvider);
        if (blocked) {
          await perms.openSettings();
        } else {
          await perms.request(PermKind.motion);
        }
      },
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.label, required this.onPrev, required this.onNext, required this.onPick});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(tooltip: 'steps_previous_day'.tr, onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(label, style: StrideText.label.copyWith(fontSize: 16)),
        ),
      ),
      IconButton(tooltip: 'steps_next_day'.tr, onPressed: onNext, icon: const Icon(Icons.chevron_right)),
    ],
  );
}
