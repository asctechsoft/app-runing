import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/l10n.dart';
import '../../../utils/progress_data.dart';
import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';
import '../../screen_history/components/month_calendar.dart';
import '../../../models/ui_models/period.dart';
import '../../../utils/date_locale.dart';

/// Mở sheet "Choose period"; trả kỳ đã chọn khi bấm Apply, null khi đóng.
Future<PeriodRange?> showChoosePeriodSheet(BuildContext context, {required PeriodRange initial, required int weekStart, required DateTime now}) {
  return showStrideSheet<PeriodRange>(
    context,
    title: 'progress_choose_period'.tr,
    builder: (ctx) => ChoosePeriodPanel(initial: initial, weekStart: weekStart, now: now),
  );
}

class ChoosePeriodPanel extends StatefulWidget {
  const ChoosePeriodPanel({super.key, required this.initial, required this.weekStart, required this.now});
  final PeriodRange initial;
  final int weekStart;
  final DateTime now;

  @override
  State<ChoosePeriodPanel> createState() => _ChoosePeriodPanelState();
}

class _ChoosePeriodPanelState extends State<ChoosePeriodPanel> {
  late PeriodRange _sel = widget.initial;
  late DateTime _visibleMonth = DateTime(widget.initial.start.year, widget.initial.start.month);
  late int _visibleYear = widget.initial.start.year;

  DateTime get _today => dayOnly(widget.now);

  bool _isFuture(PeriodRange r) => r.start.isAfter(_today);

  void _setMode(ProgressPeriod p) {
    // Giữ mốc gần nhất: chọn kỳ mới chứa ngày đầu kỳ cũ (hoặc hôm nay nếu kỳ cũ chứa hôm nay).
    final anchor = _sel.contains(_today) ? _today : _sel.start;
    setState(() {
      _sel = periodFor(p, anchor, widget.weekStart);
      _visibleMonth = DateTime(anchor.year, anchor.month);
      _visibleYear = anchor.year;
    });
  }

  void _pick(PeriodRange r) {
    if (_isFuture(r)) return;
    setState(() => _sel = r);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _sel.period;
    final current = periodFor(mode, _today, widget.weekStart);
    final previous = shiftPeriod(current, -1, widget.weekStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StrideSegmented<ProgressPeriod>(values: ProgressPeriod.values, selected: mode, labelOf: periodSegmentLabel, onChanged: _setMode),
        const SizedBox(height: 12),
        switch (mode) {
          ProgressPeriod.week => _weekPicker(),
          ProgressPeriod.month => _monthPicker(),
          ProgressPeriod.year => _yearPicker(),
        },
        const SizedBox(height: 12),
        Text('progress_shortcuts'.tr, style: StrideText.label),
        Wrap(
          spacing: 8,
          children: [
            StrideChip(
              label: periodTr(mode, 'progress_this_week', 'progress_this_month', 'progress_this_year'),
              selected: _sel == current,
              onTap: () => _pick(current),
            ),
            StrideChip(
              label: periodTr(mode, 'progress_last_week', 'progress_last_month', 'progress_last_year'),
              selected: _sel == previous,
              onTap: () => _pick(previous),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'progress_selected_range'.tr, style: StrideText.caption),
                TextSpan(text: periodLabel(_sel), style: StrideText.subheading),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'progress_apply'.tr, onPressed: () => Navigator.of(context).pop(_sel)),
      ],
    );
  }

  Widget _weekPicker() {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'progress_previous_month'.tr,
              onPressed: () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(DateFormat('MMMM y', appDateLocale).format(_visibleMonth), style: StrideText.subheading, textAlign: TextAlign.center),
            ),
            IconButton(
              tooltip: 'progress_next_month'.tr,
              onPressed: nextMonth.isAfter(_today) ? null : () => setState(() => _visibleMonth = nextMonth),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        MonthCalendar(
          month: _visibleMonth,
          weekStart: widget.weekStart,
          today: widget.now,
          rangeStart: _sel.period == ProgressPeriod.week ? _sel.start : null,
          rangeEnd: _sel.period == ProgressPeriod.week ? _sel.end : null,
          isEnabled: (d) => !d.isAfter(_today),
          onDayTap: (d) => _pick(periodFor(ProgressPeriod.week, d, widget.weekStart)),
        ),
      ],
    );
  }

  Widget _monthPicker() {
    return Column(
      children: [
        Row(
          children: [
            IconButton(tooltip: 'progress_previous_year'.tr, onPressed: () => setState(() => _visibleYear--), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('$_visibleYear', style: StrideText.subheading, textAlign: TextAlign.center),
            ),
            IconButton(
              tooltip: 'progress_next_year'.tr,
              onPressed: _visibleYear >= _today.year ? null : () => setState(() => _visibleYear++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(
                builder: (_) {
                  final r = periodFor(ProgressPeriod.month, DateTime(_visibleYear, m), widget.weekStart);
                  return Center(
                    child: StrideChip(label: DateFormat.MMM(appDateLocale).format(r.start), selected: _sel == r, onTap: _isFuture(r) ? null : () => _pick(r)),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _yearPicker() {
    final years = [for (var y = _today.year; y > _today.year - 8; y--) y];
    return Wrap(
      spacing: 8,
      children: [
        for (final y in years)
          Builder(
            builder: (_) {
              final r = periodFor(ProgressPeriod.year, DateTime(y), widget.weekStart);
              return StrideChip(label: '$y', selected: _sel == r, onTap: () => _pick(r));
            },
          ),
      ],
    );
  }
}
