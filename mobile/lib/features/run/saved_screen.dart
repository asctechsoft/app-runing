import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/activity.dart';
import 'engine/run_session_controller.dart';
import 'widgets/run_widgets.dart';

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
            title: 'Couldn\'t load your activity',
            message: 'It was saved, but we couldn\'t open it right now.',
            onRetry: () => ref.invalidate(_savedActivityProvider(activityId)),
          ),
          data: (a) {
            if (a == null) {
              return EmptyState(
                title: 'Activity not found',
                message: 'This activity isn\'t on this device.',
                icon: Icons.search_off,
                actionLabel: 'Back to home',
                onAction: () => _leave(context, ref, Routes.home),
              );
            }
            final pending = a.syncState == SyncState.pending;
            return Column(
              children: [
                const SizedBox(height: 48),
                const IconBadge(icon: Icons.check, size: 88),
                const SizedBox(height: 20),
                Semantics(liveRegion: true, child: Text('Activity saved', style: StrideText.title)),
                const SizedBox(height: 8),
                SyncBadge(state: a.syncState.name),
                const SizedBox(height: 8),
                Text(
                  pending ? 'Your activity is safe on this device. We\'ll sync it when you\'re online.' : 'Your activity is safe on this device.',
                  style: StrideText.bodySecondary,
                  textAlign: TextAlign.center,
                ),
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
                              label: 'Distance',
                              value: fmt.distanceValue(a.distanceM),
                              unit: fmt.distanceUnitLabel,
                              estimated: a.distanceSource == DistanceSource.steps,
                            ),
                          ),
                          Expanded(
                            child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs)),
                          ),
                          Expanded(
                            child: MetricTile(
                              label: 'Avg. pace',
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
                    label: 'View activity',
                    trailingIcon: Icons.arrow_forward,
                    onPressed: () => _leave(context, ref, Routes.historyActivity(activityId)),
                  ),
                  const SizedBox(height: 8),
                  OutlineButton(label: 'Back to home', onPressed: () => _leave(context, ref, Routes.home)),
                ],
              ),
      ),
    );
  }
}
