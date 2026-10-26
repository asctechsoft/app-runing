import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../utils/calc/records.dart';
import '../../utils/activity_format.dart';
import '../../utils/l10n.dart';
import 'progress_screen.dart' show formatRecordValue;
import '../../services/application/records_service.dart';
import '../../utils/date_locale.dart';

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
      title: 'progress_records_title'.tr,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Column(children: [LoadingCard(height: 120), SizedBox(height: 12), LoadingCard(height: 240)]),
        error: (_, _) => ErrorState(
          title: 'progress_records_error_title'.tr,
          message: 'progress_records_error_message'.tr,
          onRetry: () => ref.invalidate(personalRecordsProvider),
        ),
        data: (records) {
          final how = SettingsGroup(
            children: [SettingsRow(icon: Icons.help_outline, title: 'progress_records_how_title'.tr, onTap: () => context.push(Routes.recordsHow))],
          );
          if (records.isEmpty) {
            return Column(
              children: [
                EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'progress_records_empty_title'.tr,
                  message: 'progress_records_empty_message'.tr,
                  actionLabel: 'progress_start_run'.tr,
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
              Text('progress_records_achievements'.tr, style: StrideText.subheading, textAlign: TextAlign.center),
              Text('progress_records_calculated'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
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
                        final date = DateFormat('MMM d, y', appDateLocale).format(DateTime.fromMillisecondsSinceEpoch(r.achievedAt));
                        return Semantics(
                          button: true,
                          label: 'progress_record_semantic'.trArgs([recordTitle(kind), formatRecordValue(r, f), date]),
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
      title: 'progress_records_how_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          item(Icons.verified_outlined, 'progress_how_counts_title'.tr, 'progress_how_counts_body'.tr),
          item(Icons.timeline, 'progress_how_segments_title'.tr, 'progress_how_segments_body'.tr),
          item(Icons.straighten, 'progress_how_distance_title'.tr, 'progress_how_distance_body'.tr),
          item(Icons.timer_outlined, 'progress_how_times_title'.tr, 'progress_how_times_body'.tr),
          item(Icons.delete_sweep_outlined, 'progress_how_deleted_title'.tr, 'progress_how_deleted_body'.tr),
        ],
      ),
    );
  }
}
