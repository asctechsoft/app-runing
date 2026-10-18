import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/clock.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/steps.dart';
import 'hourly_steps_chart.dart';
import 'step_metrics_row.dart';
import 'step_source_priority.dart';
import 'steps_logic.dart';
import 'steps_providers.dart';

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
    final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(today.year - 5), lastDate: today, helpText: 'Choose a day');
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
      title: 'Steps',
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
              label: isToday ? 'Today, ${DateFormat('MMM d').format(_day)}' : DateFormat('EEE, MMM d, y').format(_day),
              onPrev: () => _shift(-1),
              onNext: isToday ? null : () => _shift(1),
              onPick: _pickDate,
            ),
            const Gap(StrideSpace.s16),
            async.when(
              loading: () => const Column(children: [LoadingCard(height: 120), Gap(StrideSpace.s16), LoadingCard(height: 220)]),
              error: (e, _) => ErrorState(
                title: "Couldn't load steps",
                message: 'Step data on this device could not be read. Try again.',
                onRetry: () => ref.invalidate(stepsDayProvider(key)),
              ),
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
              Text('Step tracking is off', style: StrideText.subheading),
              const Gap(StrideSpace.s4),
              Text(isToday ? 'Turn on motion access to count your steps.' : 'No step data was recorded for this day.', style: StrideText.bodySecondary),
              if (isToday) ...[const Gap(StrideSpace.s12), _enableButton(v.permission)],
            ] else if (day.status == StepDayStatus.noData) ...[
              Text('No step data yet', style: StrideText.subheading),
              const Gap(StrideSpace.s4),
              Text(
                isToday ? 'Last checked ${DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(v.checkedAt))}' : 'No steps were recorded on this day.',
                style: StrideText.bodySecondary,
              ),
            ] else ...[
              Semantics(
                label: '${fmt.steps(day.steps)} steps${v.goal == null ? '' : ' of ${fmt.steps(v.goal)} goal'}',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: fmt.steps(day.steps), style: StrideText.metric),
                      TextSpan(
                        text: v.goal == null ? ' steps' : ' / ${fmt.steps(v.goal)}',
                        style: StrideText.subheading.copyWith(color: StrideColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                v.goal == null
                    ? 'No goal set for this day'
                    : (day.steps! >= v.goal!
                          ? 'Goal reached · ${(day.steps! * 100 / v.goal!).round()}%'
                          : '${(day.steps! * 100 / v.goal!).round()}% of daily goal'),
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
            Text('Steps by hour', style: StrideText.subheading),
            const Gap(StrideSpace.s12),
            HourlyStepsChart(
              entries: entries,
              format: fmt,
              source: day.sourceUsed,
              targetPerHour: v.goal == null || !day.hasValue ? null : v.goal! / 24,
              height: 200,
            ),
            const Gap(StrideSpace.s8),
            Text(
              'Blank hours have no data ($missingValue); a short grey mark means 0 steps were recorded.'
              '${v.goal == null ? '' : ' Dashed line: steps per hour needed to reach the daily goal.'}',
              style: StrideText.caption,
            ),
            const Gap(StrideSpace.s8),
            TextButton.icon(
              onPressed: () => setState(() => _showList = !_showList),
              icon: Icon(_showList ? Icons.expand_less : Icons.list),
              label: Text(_showList ? 'Hide hourly list' : 'Show hourly list'),
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
            title: 'Source: ${sourceLabel(day.sourceUsed)}',
            subtitle: day.lastSampleAt == null ? 'No samples for this day' : 'Updated ${_updatedLabel(day.lastSampleAt!)}',
            onTap: () => context.go(Routes.dataSources),
          ),
          SettingsRow(
            icon: Icons.flag_outlined,
            title: 'Edit goal',
            subtitle: v.goal == null ? 'No goal set for this day' : 'Goal for this day: ${fmt.steps(v.goal)} steps',
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
    return DateFormat('MMM d, ').add_jm().format(t);
  }

  Widget _enableButton(PermStatus p) {
    final blocked = p == PermStatus.blocked || p == PermStatus.restricted;
    return PrimaryButton(
      label: blocked ? 'Open phone settings' : 'Enable access',
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
      IconButton(tooltip: 'Previous day', onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(label, style: StrideText.label.copyWith(fontSize: 16)),
        ),
      ),
      IconButton(tooltip: 'Next day', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
    ],
  );
}
