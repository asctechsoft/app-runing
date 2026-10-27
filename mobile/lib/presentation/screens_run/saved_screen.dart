import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/providers.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../models/data_models/activity.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/run_widgets.dart';

final _savedActivityProvider = FutureProvider.autoDispose.family<Activity?, String>((ref, id) {
  ref.watch(activityRevisionProvider);
  return ref.watch(activityRepositoryProvider).byId(ref.watch(ownerProvider).ownerId, id);
});

/// "Activity saved" — chỉ hiển thị trạng thái thật: Saved on this device / Waiting to sync (không bao giờ tự ghi Synced).
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key, required this.activityId});
  final String activityId;

  void _leave(BuildContext context, WidgetRef ref, String to) {
    ref.read(runSessionProvider.notifier).reset();
    context.go(to);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_savedActivityProvider(activityId));
    final fmt = ref.watch(formatProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context, ref, Routes.home);
      },
      child: StrideScreen(
        showBack: false,
        body: async.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard(height: 260)),
          error: (e, _) => ErrorState(
            title: 'run_saved_load_failed_title'.tr,
            message: 'run_saved_load_failed_message'.tr,
            onRetry: () => ref.invalidate(_savedActivityProvider(activityId)),
          ),
          data: (a) {
            if (a == null) {
              return EmptyState(
                title: 'run_saved_not_found_title'.tr,
                message: 'run_saved_not_found_message'.tr,
                icon: Icons.search_off,
                actionLabel: 'run_back_home'.tr,
                onAction: () => _leave(context, ref, Routes.home),
              );
            }
            final pending = a.syncState == SyncState.pending;
            return Column(
              children: [
                const SizedBox(height: 48),
                const IconBadge(icon: Icons.check, size: 88),
                const SizedBox(height: 20),
                Semantics(liveRegion: true, child: Text('run_saved_title'.tr, style: StrideText.title)),
                const SizedBox(height: 8),
                SyncBadge(state: a.syncState.name),
                const SizedBox(height: 8),
                Text(pending ? 'run_saved_pending'.tr : 'run_saved_safe'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                StrideCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title, style: StrideText.subheading),
                      Text(longDate(a.startedAt), style: StrideText.caption),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: MetricTile(
                              label: 'run_label_distance'.tr,
                              value: fmt.distanceValue(a.distanceM),
                              unit: fmt.distanceUnitLabel,
                              estimated: a.distanceSource == DistanceSource.steps,
                            ),
                          ),
                          Expanded(
                            child: MetricTile(label: 'run_label_moving_time'.tr, value: formatDuration(a.movingMs)),
                          ),
                          Expanded(
                            child: MetricTile(
                              label: 'run_label_avg_pace'.tr,
                              value: fmt.paceValue(a.avgPaceSecPerKm),
                              unit: a.avgPaceSecPerKm == null ? null : fmt.paceUnitLabel,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottom: async.value == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    label: 'run_saved_view'.tr,
                    trailingIcon: Icons.arrow_forward,
                    onPressed: () => _leave(context, ref, Routes.historyActivity(activityId)),
                  ),
                  const SizedBox(height: 8),
                  OutlineButton(label: 'run_back_home'.tr, onPressed: () => _leave(context, ref, Routes.home)),
                ],
              ),
      ),
    );
  }
}
