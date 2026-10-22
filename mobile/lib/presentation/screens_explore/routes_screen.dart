import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import 'components/explore_widgets.dart';

enum RouteDistanceBucket { any, short, medium, long }

const routeSurfaces = ['road', 'trail', 'track', 'mixed'];

String routeSurfaceLabel(String? s) => switch (s) {
  'road' => 'Road',
  'trail' => 'Trail',
  'track' => 'Track',
  'mixed' => 'Mixed',
  _ => missingValue,
};

/// Khoảng quãng đường (mét) của bucket theo đơn vị hiển thị: <5, 5–10, >10 km/mi.
(double?, double?) routeBucketRange(RouteDistanceBucket b, StrideFormat fmt) => switch (b) {
  RouteDistanceBucket.any => (null, null),
  RouteDistanceBucket.short => (null, fmt.unitToMeters(5)),
  RouteDistanceBucket.medium => (fmt.unitToMeters(5), fmt.unitToMeters(10)),
  RouteDistanceBucket.long => (fmt.unitToMeters(10), null),
};

String routeBucketLabel(RouteDistanceBucket b, StrideFormat fmt) => switch (b) {
  RouteDistanceBucket.any => 'Any distance',
  RouteDistanceBucket.short => 'Under 5 ${fmt.distanceUnitLabel}',
  RouteDistanceBucket.medium => '5–10 ${fmt.distanceUnitLabel}',
  RouteDistanceBucket.long => 'Over 10 ${fmt.distanceUnitLabel}',
};

/// Discover routes (M06): tìm theo vùng, lọc quãng đường/mặt đường.
class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'Discover routes',
      scroll: false,
      body: !flags.exploreRoutes
          ? const EmptyState(icon: Icons.place_outlined, title: 'Routes aren’t available', message: 'Discover routes isn’t turned on in this version.')
          : const ExploreGuestGate(
              icon: Icons.place_outlined,
              title: 'Sign in to discover routes',
              message: 'Create an account or sign in to find and save routes.',
              child: _RoutesBody(),
            ),
    );
  }
}

class _RoutesBody extends ConsumerStatefulWidget {
  const _RoutesBody();

  @override
  ConsumerState<_RoutesBody> createState() => _RoutesBodyState();
}

class _RoutesBodyState extends ConsumerState<_RoutesBody> {
  final _region = TextEditingController();
  final _debounce = Debouncer();
  RouteDistanceBucket _bucket = RouteDistanceBucket.any;
  String? _surface;
  List<RouteSummary>? _items;
  String? _cursor;
  ExploreFailure? _error;
  bool _loading = false;
  bool _loadingMore = false;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final id = ++_req;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    final (minM, maxM) = routeBucketRange(_bucket, ref.read(formatProvider));
    try {
      final page = await ref
          .read(exploreRepositoryProvider)
          .searchRoutes(region: _region.text, minDistanceM: minM, maxDistanceM: maxM, surface: _surface, cursor: more ? _cursor : null);
      if (id != _req || !mounted) return;
      setState(() {
        _items = more ? [...?_items, ...page.items] : page.items;
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (id != _req || !mounted) return;
      if (more) {
        showExploreError(context, e);
      } else {
        setState(() => _error = mapExploreError(e));
      }
    } finally {
      if (id == _req && mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(formatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExploreHeader(title: 'Discover routes', subtitle: 'Find your next running route.'),
        TextField(
          key: const Key('routes-region'),
          controller: _region,
          onChanged: (_) => _debounce(() {
            if (mounted) _load();
          }),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'City or region'),
        ),
        const Gap(4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final b in RouteDistanceBucket.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StrideChip(
                    label: routeBucketLabel(b, fmt),
                    selected: _bucket == b,
                    onTap: () {
                      setState(() => _bucket = b);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in <String?>[null, ...routeSurfaces])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StrideChip(
                    label: s == null ? 'Any surface' : routeSurfaceLabel(s),
                    selected: _surface == s,
                    onTap: () {
                      setState(() => _surface = s);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const Gap(8),
        Expanded(child: _content(fmt)),
      ],
    );
  }

  Widget _content(StrideFormat fmt) {
    if (_loading && _items == null) return ListView(children: const [LoadingCard(height: 88), Gap(12), LoadingCard(height: 88)]);
    if (_error != null) {
      return SingleChildScrollView(
        child: ExploreFailureView(failure: _error!, onRetry: _load),
      );
    }
    final items = _items ?? const <RouteSummary>[];
    if (items.isEmpty) {
      return const SingleChildScrollView(
        child: EmptyState(icon: Icons.search_off, title: 'No routes found', message: 'Try another area or fewer filters.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: items.length + (_cursor != null ? 1 : 0),
        separatorBuilder: (_, _) => const Gap(12),
        itemBuilder: (context, i) {
          if (i == items.length) return ExploreLoadMore(loading: _loadingMore, onPressed: () => _load(more: true));
          final r = items[i];
          return StrideCard(
            onTap: () async {
              await context.push(Routes.routeDetail(r.id));
              if (mounted) _load();
            },
            child: Row(
              children: [
                const IconBadge(icon: Icons.route_outlined, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: StrideText.subheading),
                      Text(
                        [fmt.distance(r.distanceM), routeSurfaceLabel(r.surface), if (r.region.isNotEmpty) r.region].join(' · '),
                        style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (r.saved)
                  Semantics(
                    label: 'Saved',
                    child: const Icon(Icons.bookmark, color: StrideColors.primary),
                  ),
                const Icon(Icons.chevron_right, color: StrideColors.textMuted),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Chi tiết route (M06): polyline trên bản đồ có attribution; chỉ xem trước, không dẫn đường.
class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key, required this.routeId});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'Route',
      body: !flags.exploreRoutes
          ? const EmptyState(icon: Icons.place_outlined, title: 'Routes aren’t available', message: 'Discover routes isn’t turned on in this version.')
          : ExploreGuestGate(
              icon: Icons.place_outlined,
              title: 'Sign in to discover routes',
              message: 'Create an account or sign in to view and save routes.',
              child: _RouteDetailBody(id: routeId),
            ),
    );
  }
}

class _RouteDetailBody extends ConsumerStatefulWidget {
  const _RouteDetailBody({required this.id});
  final String id;

  @override
  ConsumerState<_RouteDetailBody> createState() => _RouteDetailBodyState();
}

class _RouteDetailBodyState extends ConsumerState<_RouteDetailBody> {
  RouteDetail? _r;
  ExploreFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ref.read(exploreRepositoryProvider).route(widget.id);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _toggleSave() async {
    final r = _r!;
    setState(() => _busy = true);
    try {
      final s = await ref.read(exploreRepositoryProvider).saveRoute(r.summary.id, !r.summary.saved);
      if (!mounted) return;
      setState(() => _r = RouteDetail(summary: r.summary.withSaved(s.saved), points: r.points));
      showStrideSnack(context, s.saved ? 'Route saved' : 'Route removed from saved');
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final r = _r;
    if (r == null) return const Column(children: [Gap(8), LoadingCard(height: 240), Gap(12), LoadingCard()]);
    final fmt = ref.watch(formatProvider);
    final env = ref.watch(envProvider);
    final s = r.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(8),
        Text(s.name, style: StrideText.title),
        if (s.region.isNotEmpty) Text(s.region, style: StrideText.bodySecondary),
        const Gap(12),
        ClipRRect(
          borderRadius: BorderRadius.circular(StrideRadius.card),
          child: SizedBox(
            height: 260,
            child: r.points.length < 2
                ? Container(
                    color: StrideColors.subtle,
                    alignment: Alignment.center,
                    child: const Text('Map preview isn’t available for this route.', style: StrideText.bodySecondary),
                  )
                : Semantics(
                    label: 'Map preview of ${s.name}',
                    child: FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.coordinates(coordinates: r.points, padding: const EdgeInsets.all(32)),
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom),
                      ),
                      children: [
                        TileLayer(urlTemplate: env.tileUrlTemplate, userAgentPackageName: 'com.asc.app_runing'),
                        PolylineLayer(
                          polylines: [Polyline(points: r.points, strokeWidth: 5, color: StrideColors.primary)],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: r.points.first,
                              width: 20,
                              height: 20,
                              child: const _Dot(color: StrideColors.primary),
                            ),
                            Marker(
                              point: r.points.last,
                              width: 20,
                              height: 20,
                              child: const _Dot(color: StrideColors.iconNavy),
                            ),
                          ],
                        ),
                        SimpleAttributionWidget(source: Text(env.tileAttribution, style: StrideText.caption)),
                      ],
                    ),
                  ),
          ),
        ),
        const Gap(8),
        const StatusBanner(tone: BannerTone.info, message: 'Route preview only — no turn-by-turn navigation.', icon: Icons.map_outlined),
        const Gap(12),
        StrideCard(
          child: Row(
            children: [
              Expanded(
                child: MetricTile(label: 'Distance', value: fmt.distanceValue(s.distanceM), unit: fmt.distanceUnitLabel),
              ),
              Expanded(
                child: MetricTile(label: 'Surface', value: routeSurfaceLabel(s.surface)),
              ),
            ],
          ),
        ),
        if (s.attribution.isNotEmpty) ...[const Gap(8), Text('Route data: ${s.attribution}', style: StrideText.caption)],
        const Gap(16),
        if (s.saved)
          SecondaryButton(label: 'Unsave route', icon: Icons.bookmark_remove_outlined, onPressed: _busy ? null : _toggleSave)
        else
          PrimaryButton(label: 'Save route', icon: Icons.bookmark_add_outlined, loading: _busy, onPressed: _busy ? null : _toggleSave),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: StrideColors.surface, width: 3),
    ),
  );
}
