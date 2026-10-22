import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../values/tokens.dart';
import '../../../utils/clock.dart';

/// Lưới tháng dùng cho History (chấm ngày có hoạt động) và Choose period (chọn tuần).
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.weekStart,
    required this.onDayTap,
    this.markedDays = const {},
    this.selectedDay,
    this.rangeStart,
    this.rangeEnd,
    this.isEnabled,
    this.today,
  });

  /// Bất kỳ ngày nào trong tháng cần hiển thị.
  final DateTime month;
  final int weekStart;
  final ValueChanged<DateTime> onDayTap;

  /// dateKey (YYYY-MM-DD) → số hoạt động.
  final Map<String, int> markedDays;
  final DateTime? selectedDay;

  /// Tô nền khoảng [rangeStart, rangeEnd) (vd. tuần đang chọn).
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool Function(DateTime day)? isEnabled;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final gridStart = startOfWeek(first, weekStart);
    final nextMonth = DateTime(month.year, month.month + 1);
    final weeks = <List<DateTime>>[];
    for (var d = gridStart; d.isBefore(nextMonth); d = DateTime(d.year, d.month, d.day + 7)) {
      weeks.add([for (var i = 0; i < 7; i++) DateTime(d.year, d.month, d.day + i)]);
    }
    final now = today ?? DateTime.now();
    final todayKey = localDateKey(now);
    final selKey = selectedDay == null ? null : localDateKey(selectedDay!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final d in weeks.first)
              Expanded(
                child: Center(child: Text(DateFormat.E('en_US').format(d), style: StrideText.caption)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final w in weeks)
          Row(
            children: [
              for (final d in w)
                Expanded(
                  child: _DayCell(
                    day: d,
                    inMonth: d.month == month.month,
                    count: markedDays[localDateKey(d)] ?? 0,
                    selected: selKey == localDateKey(d),
                    inRange: rangeStart != null && rangeEnd != null && !d.isBefore(rangeStart!) && d.isBefore(rangeEnd!),
                    isToday: localDateKey(d) == todayKey,
                    enabled: isEnabled?.call(d) ?? true,
                    onTap: () => onDayTap(d),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.count,
    required this.selected,
    required this.inRange,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final int count;
  final bool selected;
  final bool inRange;
  final bool isToday;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? StrideColors.disabledText
        : selected
        ? StrideColors.surface
        : inMonth
        ? StrideColors.textPrimary
        : StrideColors.textMuted;
    final label = DateFormat('EEEE, MMMM d', 'en_US').format(day);
    return Semantics(
      button: enabled,
      selected: selected || inRange,
      enabled: enabled,
      label: count > 0 ? '$label, $count ${count == 1 ? 'activity' : 'activities'}' : label,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          height: 48,
          color: inRange && !selected ? StrideColors.subtle : null,
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: selected ? StrideColors.primary : null,
              shape: BoxShape.circle,
              border: isToday && !selected ? Border.all(color: StrideColors.primary) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: StrideText.label.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: count > 0 ? (selected ? StrideColors.lime : StrideColors.primary) : null, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
