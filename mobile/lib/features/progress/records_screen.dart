import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/calc/records.dart';
import '../activity/activity_format.dart';
import 'progress_screen.dart' show formatRecordValue;
import 'records_service.dart';

IconData _recordIcon(RecordKind k) => switch (k) {
  RecordKind.longestRun => Icons.route_outlined,
  RecordKind.longestDuration => Icons.timer_outlined,
  RecordKind.fastest1k => Icons.bolt_outlined,
  RecordKind.fastest5k => Icons.speed,
};

/// Personal records (I05): tính lại từ hoạt động còn hợp lệ; bấm mở hoạt động nguồn.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(personalRecordsProvider);
    final f = ref.watch(formatProvider);
    return StrideScreen(
      title: 'Personal records',
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Column(children: [LoadingCard(height: 120), SizedBox(height: 12), LoadingCard(height: 240)]),
        error: (_, _) => ErrorState(
          title: 'Couldn\'t calculate records',
          message: 'Reading your runs from this device failed.',
          onRetry: () => ref.invalidate(personalRecordsProvider),
        ),
        data: (records) {
          final how = SettingsGroup(
            children: [SettingsRow(icon: Icons.help_outline, title: 'How records work', onTap: () => context.push(Routes.recordsHow))],
          );
          if (records.isEmpty) {
            return Column(
              children: [
                EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'No records yet',
                  message: 'Save an outdoor run with GPS to start setting personal records.',
                  actionLabel: 'Start a run',
                  onAction: () => context.go(Routes.run),
                ),
                how,
              ],
            );
          }
          final byKind = {for (final r in records) r.kind: r};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Center(child: IconBadge(icon: Icons.emoji_events_outlined, size: 72)),
              const SizedBox(height: 12),
              Text('Your running achievements', style: StrideText.subheading, textAlign: TextAlign.center),
              Text('Records are calculated from eligible recorded runs.', style: StrideText.bodySecondary, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SettingsGroup(
                children: [
                  for (final kind in RecordKind.values)
                    Builder(
                      builder: (context) {
                        final r = byKind[kind];
                        if (r == null) {
                          return SettingsRow(icon: _recordIcon(kind), title: recordTitle(kind), subtitle: recordEmptyHint(kind), showChevron: false);
                        }
                        final date = DateFormat('MMM d, y', 'en_US').format(DateTime.fromMillisecondsSinceEpoch(r.achievedAt));
                        return Semantics(
                          button: true,
                          label: '${recordTitle(kind)}, ${formatRecordValue(r, f)}, $date. Opens the activity.',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: () => context.push(activityPathFor(context, r.activityId)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  IconBadge(icon: _recordIcon(kind), size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(recordTitle(kind), style: StrideText.label),
                                        Text(formatRecordValue(r, f), style: StrideText.metricSmall.copyWith(fontSize: 22)),
                                        Text(recordDescription(kind), style: StrideText.caption),
                                      ],
                                    ),
                                  ),
                                  Text(date, style: StrideText.caption),
                                  const Icon(Icons.chevron_right, size: 20, color: StrideColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              how,
            ],
          );
        },
      ),
    );
  }
}

/// Giải thích tiêu chí record (I05).
class RecordsHowScreen extends StatelessWidget {
  const RecordsHowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: StrideText.subheading),
                const SizedBox(height: 4),
                Text(body, style: StrideText.bodySecondary),
              ],
            ),
          ),
        ],
      ),
    );
    return StrideScreen(
      title: 'How records work',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          item(
            Icons.verified_outlined,
            'Which runs count',
            'Only saved outdoor runs recorded with GPS count. Walks, indoor runs and runs with step-estimated distance are not used.',
          ),
          item(
            Icons.timeline,
            'Continuous segments only',
            'Fastest 1 km and 5 km come from the best continuous stretch of GPS inside one run. Paused time and GPS gaps are never bridged.',
          ),
          item(Icons.straighten, 'Full distance required', 'A record is only set when the distance is really covered. A 4.9 km run never counts as 5 km.'),
          item(Icons.timer_outlined, 'Times, not paces', 'Fastest records show the time it took to cover the distance. Longest duration uses moving time.'),
          item(Icons.delete_sweep_outlined, 'Deleted runs', 'If you delete a run that holds a record, records are recalculated from your remaining runs.'),
        ],
      ),
    );
  }
}
