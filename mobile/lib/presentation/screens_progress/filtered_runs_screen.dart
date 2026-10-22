import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../screens_activity/components/activity_card.dart';
import '../../controller/history/activity_feed_controller.dart';
import '../../utils/progress_data.dart';

enum _RunsFilter { all, run }

/// Danh sách hoạt động trong khoảng [fromMs, toMs) (View all từ Progress) với lọc All/Run.
class FilteredRunsScreen extends ConsumerStatefulWidget {
  const FilteredRunsScreen({super.key, this.fromMs, this.toMs, this.title});
  final int? fromMs;
  final int? toMs;
  final String? title;

  @override
  ConsumerState<FilteredRunsScreen> createState() => _FilteredRunsScreenState();
}

class _FilteredRunsScreenState extends ConsumerState<FilteredRunsScreen> {
  late final ActivityFeedController _feed = ActivityFeedController(ref.read(activityRepositoryProvider));
  final _scroll = ScrollController();
  _RunsFilter _filter = _RunsFilter.run;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_changed);
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 600) _feed.loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _feed.removeListener(_changed);
    _feed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Set<ActivityType>? get _types => _filter == _RunsFilter.all ? null : runningTypes(indoor: ref.read(flagsProvider).runIndoor);

  void _load({bool keep = false}) => _feed.load(
    ActivityFilter(ownerId: ref.read(ownerProvider).ownerId, types: _types, fromMs: widget.fromMs, toMs: widget.toMs),
    keepItems: keep,
  );

  String? get _rangeLabel {
    if (widget.fromMs == null || widget.toMs == null) return null;
    final s = DateTime.fromMillisecondsSinceEpoch(widget.fromMs!);
    final e = DateTime.fromMillisecondsSinceEpoch(widget.toMs!).subtract(const Duration(milliseconds: 1));
    final fmt = DateFormat('MMM d, y', 'en_US');
    return s.year == e.year && s.month == e.month && s.day == e.day ? fmt.format(s) : '${fmt.format(s)} – ${fmt.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activityRevisionProvider, (_, _) => _load(keep: true));
    final f = ref.watch(formatProvider);
    final t = _feed.totals;
    return StrideScreen(
      title: widget.title ?? 'Runs',
      scroll: false,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          if (_rangeLabel != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_rangeLabel!, style: StrideText.bodySecondary, textAlign: TextAlign.center),
              ),
            ),
          SliverToBoxAdapter(
            child: StrideSegmented<_RunsFilter>(
              values: _RunsFilter.values,
              selected: _filter,
              labelOf: (v) => v == _RunsFilter.all ? 'All' : 'Run',
              onChanged: (v) {
                setState(() => _filter = v);
                _load();
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: SageCard(
              child: t == null
                  ? const Skeleton(height: 56)
                  : Row(
                      children: [
                        Expanded(
                          child: MetricTile(value: f.distanceValue(t.distanceM), unit: f.distanceUnitLabel, label: 'Total distance', center: true),
                        ),
                        Expanded(
                          child: MetricTile(value: formatDurationShort(t.movingMs), label: 'Moving time', center: true),
                        ),
                        Expanded(
                          child: MetricTile(
                            value: f.paceValue(periodPaceSecPerKm(t)),
                            unit: periodPaceSecPerKm(t) == null ? null : f.paceUnitLabel,
                            label: 'Avg. pace',
                            center: true,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_feed.error != null && _feed.items.isEmpty)
            SliverToBoxAdapter(
              child: ErrorState(title: 'Couldn\'t load activities', message: 'Reading activities saved on this device failed.', onRetry: _load),
            )
          else if (_feed.loading && _feed.items.isEmpty)
            const SliverToBoxAdapter(child: LoadingCard(height: 108))
          else if (_feed.items.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.directions_run,
                title: 'No activities in this period',
                message: _filter == _RunsFilter.run ? 'No runs were saved in this period.' : 'Nothing was saved in this period.',
              ),
            )
          else ...[
            SliverList.separated(
              itemCount: _feed.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => ActivityCard(key: ValueKey(_feed.items[i].id), activity: _feed.items[i]),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: _feed.loadingMore
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : _feed.hasMore
                      ? TextButton(onPressed: _feed.loadMore, child: const Text('Load more'))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
