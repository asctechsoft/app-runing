import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'activity_format.dart';
import 'activity_map_view.dart';
import 'activity_providers.dart';
import 'route_geometry.dart';

/// Bản đồ toàn màn hình (I02): kéo/zoom, nút về toàn tuyến, chỉ số tóm tắt.
class ActivityMapScreen extends ConsumerStatefulWidget {
  const ActivityMapScreen({super.key, required this.activityId});
  final String activityId;

  @override
  ConsumerState<ActivityMapScreen> createState() => _ActivityMapScreenState();
}

class _ActivityMapScreenState extends ConsumerState<ActivityMapScreen> {
  final _mapKey = GlobalKey<ActivityRouteMapState>();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityDetailProvider(widget.activityId));
    final f = ref.watch(formatProvider);
    return async.when(
      loading: () => const StrideScreen(scroll: false, body: Center(child: CircularProgressIndicator())),
      error: (_, _) => StrideScreen(
        body: ErrorState(
          title: 'Couldn\'t open the map',
          message: 'Reading this route from the device failed.',
          onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (d) {
        if (d == null) {
          return const StrideScreen(
            body: EmptyState(icon: Icons.search_off, title: 'Activity not found', message: 'This activity may have been deleted.'),
          );
        }
        if (!d.hasRoute) {
          return StrideScreen(
            title: activityDisplayTitle(d.activity),
            body: const EmptyState(icon: Icons.location_off_outlined, title: 'No GPS route', message: 'This activity has no route to show on a map.'),
          );
        }
        final a = d.activity;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
            titleSpacing: 0,
            title: Text(activityDisplayTitle(a), style: StrideText.heading),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: ActivityRouteMap(key: _mapKey, route: routeFromPoints(d.points), interactive: true, padding: const EdgeInsets.fromLTRB(32, 32, 32, 160)),
              ),
              Positioned(
                right: 16,
                bottom: 140,
                child: Material(
                  color: StrideColors.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    tooltip: 'Show whole route',
                    icon: const Icon(Icons.center_focus_strong),
                    onPressed: () => _mapKey.currentState?.recenter(),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: StrideCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: MetricTile(label: 'Distance', value: f.distanceValue(a.distanceM), unit: f.distanceUnitLabel, center: true),
                        ),
                        Expanded(
                          child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs), center: true),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: 'Avg. pace',
                            value: f.paceValue(a.avgPaceSecPerKm),
                            unit: a.avgPaceSecPerKm == null ? null : f.paceUnitLabel,
                            center: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
