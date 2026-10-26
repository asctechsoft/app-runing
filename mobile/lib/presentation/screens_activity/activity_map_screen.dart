import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../utils/activity_format.dart';
import 'components/activity_map_view.dart';
import '../../controller/activity/activity_providers.dart';
import '../../utils/route_geometry.dart';
import '../../utils/l10n.dart';

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
          title: 'activity_map_open_error_title'.tr,
          message: 'activity_map_open_error_message'.tr,
          onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (d) {
        if (d == null) {
          return StrideScreen(
            body: EmptyState(icon: Icons.search_off, title: 'activity_not_found_title'.tr, message: 'activity_not_found_message_short'.tr),
          );
        }
        if (!d.hasRoute) {
          return StrideScreen(
            title: activityDisplayTitle(d.activity),
            body: EmptyState(icon: Icons.location_off_outlined, title: 'activity_no_gps_title'.tr, message: 'activity_map_no_route_message'.tr),
          );
        }
        final a = d.activity;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(tooltip: 'activity_back'.tr, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
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
                    tooltip: 'activity_map_show_route'.tr,
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
                          child: MetricTile(label: 'activity_metric_distance'.tr, value: f.distanceValue(a.distanceM), unit: f.distanceUnitLabel, center: true),
                        ),
                        Expanded(
                          child: MetricTile(label: 'activity_metric_moving_time'.tr, value: formatDuration(a.movingMs), center: true),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: 'activity_metric_avg_pace'.tr,
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
