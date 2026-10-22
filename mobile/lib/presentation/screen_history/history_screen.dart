import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../../utils/clock.dart';
import '../common_components/widgets.dart';
import '../../repository/activity_repository.dart';
import '../../models/data_models/activity.dart';
import '../screens_activity/components/activity_card.dart';
import '../../controller/history/activity_feed_controller.dart';
import 'components/month_calendar.dart';

enum HistoryView { list, calendar }

enum HistoryTypeFilter { all, run, walk, indoor }

extension on HistoryTypeFilter {
  String get label => switch (this) {
    HistoryTypeFilter.all => 'All',
    HistoryTypeFilter.run => 'Run',
    HistoryTypeFilter.walk => 'Walk',
    HistoryTypeFilter.indoor => 'Indoor',
  };

  Set<ActivityType>? get types => switch (this) {
    HistoryTypeFilter.all => null,
    HistoryTypeFilter.run => {ActivityType.run},
    HistoryTypeFilter.walk => {ActivityType.walk},
    HistoryTypeFilter.indoor => {ActivityType.indoorRun},
  };
}

/// History (I01, F14): list/calendar, lọc loại, chọn tháng, tổng theo đúng bộ lọc, phân trang keyset.
/// State nằm trong State của màn — shell giữ nhánh nên back từ chi tiết không mất filter/scroll.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final ActivityFeedController _feed = ActivityFeedController(ref.read(activityRepositoryProvider));
  final _scroll = ScrollController();

  HistoryView _view = HistoryView.list;
  HistoryTypeFilter _type = HistoryTypeFilter.all;
  late DateTime _month;
  DateTime? _day;
  Map<String, int> _marks = const {};
  int _marksGen = 0;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).nowLocal();
    _month = DateTime(now.year, now.month);
    _feed.addListener(_onFeed);
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeed);
    _feed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) _feed.loadMore();
  }

  String get _owner => ref.read(ownerProvider).ownerId;

  ActivityFilter get _filter {
    final from = _day ?? _month;
    final to = _day == null ? DateTime(_month.year, _month.month + 1) : DateTime(_day!.year, _day!.month, _day!.day + 1);
    return ActivityFilter(ownerId: _owner, types: _type.types, fromMs: from.millisecondsSinceEpoch, toMs: to.millisecondsSinceEpoch);
  }

  void _reload({bool keep = false}) {
    _feed.load(_filter, keepItems: keep);
    _loadMarks();
  }

  /// Chấm lịch: ngày địa phương có hoạt động trong tháng (cùng owner/loại với list).
  Future<void> _loadMarks() async {
    final gen = ++_marksGen;
    final repo = ref.read(activityRepositoryProvider);
    final from = _month.millisecondsSinceEpoch;
    final to = DateTime(_month.year, _month.month + 1).millisecondsSinceEpoch;
    try {
      final acts = await repo.list(ActivityQuery(ownerId: _owner, types: _type.types, fromMs: from, toMs: to, limit: 10000));
      if (!mounted || gen != _marksGen) return;
      final m = <String, int>{};
      for (final a in acts) {
        final k = localDateKey(DateTime.fromMillisecondsSinceEpoch(a.startedAt));
        m[k] = (m[k] ?? 0) + 1;
      }
      setState(() => _marks = m);
    } catch (_) {
      // Lịch không có chấm khi lỗi đọc; danh sách hiển thị lỗi riêng.
    }
  }

  void _setType(HistoryTypeFilter t) {
    if (t == _type) return;
    setState(() => _type = t);
    _reload();
  }

  void _setMonth(DateTime m) {
    setState(() {
      _month = DateTime(m.year, m.month);
      _day = null;
    });
    _reload();
  }

  void _setDay(DateTime? d) {
    setState(() => _day = (d != null && _day != null && localDateKey(d) == localDateKey(_day!)) ? null : d);
    _feed.load(_filter);
  }

  /// Xóa bộ lọc: về All, bỏ ngày; nếu tháng vẫn trống thì nhảy tới tháng có hoạt động gần nhất.
  Future<void> _clearFilters() async {
    final latest = await ref.read(activityRepositoryProvider).latest(_owner);
    if (!mounted) return;
    setState(() {
      _type = HistoryTypeFilter.all;
      _day = null;
      if (latest != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(latest.startedAt);
        _month = DateTime(d.year, d.month);
      }
    });
    _reload();
  }

  Future<void> _pickMonth() async {
    final now = ref.read(clockProvider).nowLocal();
    final picked = await showStrideSheet<DateTime>(
      context,
      title: 'Choose month',
      builder: (ctx) => _MonthPicker(initial: _month, latest: DateTime(now.year, now.month)),
    );
    if (picked != null) _setMonth(picked);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activityRevisionProvider, (_, _) => _reload(keep: true));
    ref.listen(ownerProvider, (_, _) => _reload());
    final f = ref.watch(formatProvider);
    final flags = ref.watch(flagsProvider);
    final weekStart = ref.watch(settingsProvider).value?.weekStart ?? DateTime.monday;
    final now = ref.watch(clockProvider).nowLocal();
    final g = StrideScreen.gutterOf(context);

    final noActivitiesAtAll = _feed.ownerTotal == 0 && !_feed.loading && _feed.error == null;
    final filters = [HistoryTypeFilter.all, HistoryTypeFilter.run, HistoryTypeFilter.walk, if (flags.runIndoor) HistoryTypeFilter.indoor];

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text('Your activities', style: StrideText.title),
        ),
      ),
    ];

    if (noActivitiesAtAll) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyState(
              icon: Icons.directions_run,
              title: 'Your first run starts here',
              message: 'Record a walk or run to see it on your timeline.',
              actionLabel: 'Start a run',
              onAction: () => context.go(Routes.run),
              secondaryLabel: 'Daily steps are available on Home',
              onSecondary: () => context.go(Routes.home),
            ),
          ),
        ),
      );
    } else {
      final isCurrentMonth = _month.year == now.year && _month.month == now.month;
      slivers.addAll([
        SliverToBoxAdapter(
          child: Row(
            children: [
              IconButton(tooltip: 'Previous month', onPressed: () => _setMonth(DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: TextButton(
                  onPressed: _pickMonth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('MMMM y', 'en_US').format(_month), style: StrideText.subheading),
                      const Icon(Icons.expand_more, size: 20),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: isCurrentMonth ? null : () => _setMonth(DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: _TotalsCard(totals: _feed.totals, type: _type, format: f),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: StrideSegmented<HistoryView>(
            values: HistoryView.values,
            selected: _view,
            labelOf: (v) => v == HistoryView.list ? 'List' : 'Calendar',
            onChanged: (v) => setState(() => _view = v),
          ),
        ),
        SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            children: [for (final t in filters) StrideChip(label: t.label, selected: t == _type, onTap: () => _setType(t))],
          ),
        ),
        if (_view == HistoryView.calendar)
          SliverToBoxAdapter(
            child: StrideCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: MonthCalendar(
                month: _month,
                weekStart: weekStart,
                markedDays: _marks,
                selectedDay: _day,
                today: now,
                isEnabled: (d) => d.month == _month.month && !d.isAfter(now),
                onDayTap: _setDay,
              ),
            ),
          ),
        if (_day != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text('Showing ${DateFormat('EEE, MMM d', 'en_US').format(_day!)}'),
                  onDeleted: () => _setDay(null),
                  deleteButtonTooltipMessage: 'Show the whole month',
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ..._content(),
      ]);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: StrideSpace.maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: g),
              child: CustomScrollView(key: const PageStorageKey('history-scroll'), controller: _scroll, slivers: slivers),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (_feed.error != null && _feed.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ErrorState(
            title: 'Couldn\'t load your activities',
            message: 'Reading activities saved on this device failed. Your data has not been changed.',
            onRetry: () => _reload(),
          ),
        ),
      ];
    }
    if (_feed.loading && _feed.items.isEmpty) {
      return [
        SliverList.separated(itemCount: 3, separatorBuilder: (_, _) => const SizedBox(height: 12), itemBuilder: (_, _) => const LoadingCard(height: 108)),
      ];
    }
    if (_feed.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'No activities found',
            message: _day != null ? 'Nothing was recorded on this day with the current filter.' : 'Nothing matches this month and activity type.',
            actionLabel: 'Clear filters',
            onAction: _clearFilters,
          ),
        ),
      ];
    }
    final items = _feed.items;
    return [
      SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => ActivityCard(key: ValueKey(items[i].id), activity: items[i]),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: _feed.loadingMore
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                : _feed.hasMore
                ? TextButton(onPressed: _feed.loadMore, child: const Text('Load more'))
                : Text(items.length == 1 ? '1 activity' : '${items.length} activities', style: StrideText.caption),
          ),
        ),
      ),
    ];
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.type, required this.format});
  final ActivityTotals? totals;
  final HistoryTypeFilter type;
  final StrideFormat format;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final countLabel = switch (type) {
      HistoryTypeFilter.run => t?.count == 1 ? 'run' : 'runs',
      HistoryTypeFilter.walk => t?.count == 1 ? 'walk' : 'walks',
      HistoryTypeFilter.indoor => t?.count == 1 ? 'indoor run' : 'indoor runs',
      HistoryTypeFilter.all => t?.count == 1 ? 'activity' : 'activities',
    };
    return SageCard(
      child: t == null
          ? const Skeleton(height: 64)
          : Row(
              children: [
                Expanded(
                  child: MetricTile(icon: Icons.directions_run, value: '${t.count}', label: countLabel, center: true),
                ),
                Expanded(
                  child: MetricTile(
                    icon: Icons.route_outlined,
                    value: format.distanceValue(t.distanceM),
                    unit: format.distanceUnitLabel,
                    label: 'total distance',
                    center: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(icon: Icons.timer_outlined, value: formatDurationShort(t.movingMs), label: 'total time', center: true),
                ),
              ],
            ),
    );
  }
}

class _MonthPicker extends StatefulWidget {
  const _MonthPicker({required this.initial, required this.latest});
  final DateTime initial;
  final DateTime latest;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Previous year', onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('$_year', style: StrideText.subheading, textAlign: TextAlign.center),
            ),
            IconButton(
              tooltip: 'Next year',
              onPressed: _year >= widget.latest.year ? null : () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(
                builder: (context) {
                  final d = DateTime(_year, m);
                  final enabled = !d.isAfter(widget.latest);
                  final selected = d.year == widget.initial.year && d.month == widget.initial.month;
                  return Padding(
                    padding: const EdgeInsets.all(4),
                    child: StrideChip(label: DateFormat.MMM('en_US').format(d), selected: selected, onTap: enabled ? () => Navigator.of(context).pop(d) : null),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
