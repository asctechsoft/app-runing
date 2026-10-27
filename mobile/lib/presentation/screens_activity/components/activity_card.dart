import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../controller/providers.dart';
import '../../../models/data_models/activity.dart';
import '../../../utils/activity_format.dart';
import '../../../utils/date_locale.dart';
import '../../../utils/formatters.dart';
import '../../../utils/l10n.dart';
import '../../../utils/route_geometry.dart';
import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';

/// Tuyến rút gọn cho thumbnail (≤ ~150 điểm mỗi hoạt động), đọc từ DB local.
final activityThumbRouteProvider = FutureProvider.autoDispose.family<RouteLines?, String>((ref, id) async {
  final repo = ref.watch(activityRepositoryProvider);
  final pts = await repo.points(id, acceptedOnly: true);
  if (pts.length < 2) return null;
  final route = routeFromPoints(pts);
  final total = route.fold<int>(0, (a, s) => a + s.length);
  final step = (total / 150).ceil().clamp(1, 1 << 20);
  if (step == 1) return route;
  return [
    for (final s in route)
      [
        for (var i = 0; i < s.length; i++)
          if (i % step == 0 || i == s.length - 1) s[i],
      ],
  ];
});

/// Thẻ hoạt động: thumbnail tuyến, tiêu đề, ngày, loại, quãng đường, moving time, pace, trạng thái sync.
/// Cả thẻ mở chi tiết theo tab hiện tại.
class ActivityCard extends ConsumerWidget {
  const ActivityCard({super.key, required this.activity, this.compact = false});

  final Activity activity;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    final f = ref.watch(formatProvider);
    final route = a.hasGps ? ref.watch(activityThumbRouteProvider(a.id)).value : null;
    final title = activityDisplayTitle(a);
    final date = AppDates.shortWeekdayDate(activityLocalStart(a));
    final pace = f.pace(a.avgPaceSecPerKm);
    final estimated = a.distanceSource != DistanceSource.gps;
    return StrideCard(
      padding: const EdgeInsets.all(12),
      semanticLabel:
          '$title, ${activityTypeLabel(a.type)}, $date, ${f.distance(a.distanceM)}${estimated ? ' ${'activity_semantic_estimated'.tr}' : ''}, ${formatDuration(a.movingMs)}, $pace',
      onTap: () => context.push(activityPathFor(context, a.id)),
      child: ExcludeSemantics(
        child: Row(
          children: [
            RouteThumbnail(route: route, size: compact ? 64 : 84),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: StrideText.caption),
                  Text(
                    title,
                    style: StrideText.body.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Row(
                        children: [
                          Icon(a.type == ActivityType.walk ? Icons.directions_walk : Icons.directions_run, size: 16, color: StrideColors.primary),
                          const SizedBox(width: 4),
                          Text(activityTypeLabel(a.type), style: StrideText.caption.copyWith(color: StrideColors.textSecondary)),
                          const Spacer(),
                          SyncBadge(state: a.syncState.name),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(value: f.distance(a.distanceM), label: estimated ? 'activity_metric_distance_est'.tr : 'activity_metric_distance'.tr),
                      ),
                      Expanded(
                        child: _Stat(value: formatDuration(a.movingMs), label: 'activity_metric_moving_time'.tr),
                      ),
                      Expanded(
                        child: _Stat(value: pace, label: 'activity_metric_avg_pace'.tr),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: StrideColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: StrideText.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(label, style: StrideText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  );
}
