import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../services/application/activity_export.dart';
import '../../utils/activity_format.dart';
import '../../controller/activity/activity_providers.dart';
import '../../utils/route_geometry.dart';

enum ShareTemplate { map, photo, minimal }

/// Kích thước logic của ảnh chia sẻ (4:5). Xuất ở pixelRatio cố định → 1080 × 1350 px.
const Size shareCardSize = Size(360, 450);
const double shareExportPixelRatio = 3;

/// Bán kính ẩn đầu/cuối có thể chọn (mét).
const List<double> hideRadiusOptions = [200, 500];

/// Tuyến còn lại quá ngắn sau khi ẩn → đề nghị ẩn cả bản đồ.
const double minVisibleRouteM = 200;

/// Cấu hình ảnh chia sẻ — giữ nguyên khi xuất lỗi để thử lại (F17).
class ShareConfig {
  const ShareConfig({
    this.template = ShareTemplate.map,
    this.showDistance = true,
    this.showTime = true,
    this.showPace = true,
    this.showDate = true,
    this.hideEnds = true,
    this.hideRadiusM = 200,
    this.photoId,
  });

  final ShareTemplate template;
  final bool showDistance;
  final bool showTime;
  final bool showPace;
  final bool showDate;
  final bool hideEnds;
  final double hideRadiusM;
  final String? photoId;

  ShareConfig copyWith({
    ShareTemplate? template,
    bool? showDistance,
    bool? showTime,
    bool? showPace,
    bool? showDate,
    bool? hideEnds,
    double? hideRadiusM,
    String? photoId,
  }) => ShareConfig(
    template: template ?? this.template,
    showDistance: showDistance ?? this.showDistance,
    showTime: showTime ?? this.showTime,
    showPace: showPace ?? this.showPace,
    showDate: showDate ?? this.showDate,
    hideEnds: hideEnds ?? this.hideEnds,
    hideRadiusM: hideRadiusM ?? this.hideRadiusM,
    photoId: photoId ?? this.photoId,
  );
}

/// Tuyến dùng để vẽ ảnh: bản sao đã cắt khi bật ẩn đầu/cuối (tuyến gốc không đổi).
RouteLines shareRouteFor(RouteLines original, ShareConfig c) => c.hideEnds ? clipRouteEnds(original, c.hideRadiusM) : original;

/// Ảnh chia sẻ (I06, F17): mẫu Map / Photo / Minimal, preview chính là widget được raster hóa.
class ShareActivityScreen extends ConsumerStatefulWidget {
  const ShareActivityScreen({super.key, required this.activityId});
  final String activityId;

  @override
  ConsumerState<ShareActivityScreen> createState() => _ShareActivityScreenState();
}

class _ShareActivityScreenState extends ConsumerState<ShareActivityScreen> {
  final _boundaryKey = GlobalKey();
  final _guard = OnceGuard();
  ShareConfig _c = const ShareConfig();
  bool _exporting = false;
  bool _initialized = false;

  void _init(ActivityDetailData d) {
    if (_initialized) return;
    _initialized = true;
    // Không có tuyến → mẫu Minimal; có ảnh nhưng không có tuyến → Photo.
    if (!d.hasRoute) {
      final photo = d.photos.where((p) => p.fileExists).firstOrNull;
      _c = _c.copyWith(template: photo != null ? ShareTemplate.photo : ShareTemplate.minimal, photoId: photo?.id);
    }
  }

  /// Raster hóa đúng widget preview → PNG (PNG do engine tạo không chứa EXIF/vị trí).
  Future<List<int>> _renderPng() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: shareExportPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('png-encode-failed');
    return data.buffer.asUint8List();
  }

  Future<void> _share(Activity a) async {
    await _guard.run(() async {
      setState(() => _exporting = true);
      try {
        final bytes = await _renderPng();
        final r = await shareBytesAsFile(bytes: Uint8List.fromList(bytes), fileName: '${exportFileStem(a)}.png', mime: 'image/png');
        // Hủy bảng chia sẻ → không báo gì (không bao giờ nói "posted").
        if (r.status == ShareResultStatus.success && mounted) showStrideSnack(context, 'Image sent to the app you chose.');
      } catch (_) {
        if (mounted) {
          showStrideSnack(context, 'Couldn\'t create the image. Your settings are kept.', isError: true, actionLabel: 'Try again', onAction: () => _share(a));
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityDetailProvider(widget.activityId));
    return async.when(
      loading: () => const StrideScreen(title: 'Share activity', body: LoadingCard(height: 400)),
      error: (_, _) => StrideScreen(
        title: 'Share activity',
        body: ErrorState(
          title: 'Couldn\'t open this activity',
          message: 'Reading it from this device failed.',
          onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (d) {
        if (d == null) {
          return const StrideScreen(
            title: 'Share activity',
            body: EmptyState(icon: Icons.search_off, title: 'Activity not found', message: 'This activity may have been deleted.'),
          );
        }
        _init(d);
        return _build(d);
      },
    );
  }

  Widget _build(ActivityDetailData d) {
    final f = ref.watch(formatProvider);
    final a = d.activity;
    final original = d.hasRoute ? routeFromPoints(d.points) : <List<GeoPoint>>[];
    final usesRoute = _c.template == ShareTemplate.map && original.isNotEmpty;
    final shareRoute = usesRoute ? shareRouteFor(original, _c) : <List<GeoPoint>>[];
    final tooLittle = usesRoute && _c.hideEnds && routeLengthM(shareRoute) < minVisibleRouteM;
    final photos = d.photos.where((p) => p.fileExists).toList();
    final photo = photos.where((p) => p.id == _c.photoId).firstOrNull ?? photos.firstOrNull;
    final templates = [if (original.isNotEmpty) ShareTemplate.map, if (photos.isNotEmpty) ShareTemplate.photo, ShareTemplate.minimal];

    return StrideScreen(
      title: 'Share activity',
      bottom: PrimaryButton(label: 'Save or share image', icon: Icons.ios_share, loading: _exporting, onPressed: tooLittle ? null : () => _share(a)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // Preview = chính widget được xuất (FittedBox chỉ co hiển thị, không đổi nội dung ảnh).
          Semantics(
            label: 'Preview of the image that will be shared',
            child: AspectRatio(
              aspectRatio: shareCardSize.width / shareCardSize.height,
              child: FittedBox(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: SizedBox.fromSize(
                    size: shareCardSize,
                    child: ShareCard(
                      activity: a,
                      config: _c,
                      format: f,
                      route: tooLittle ? const [] : shareRoute,
                      photoPath: _c.template == ShareTemplate.photo ? photo?.localPath : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (tooLittle) ...[
            const SizedBox(height: 12),
            StatusBanner(
              tone: BannerTone.warning,
              title: 'Not enough route left',
              message: 'After hiding your start and finish, too little of the route remains to show.',
              actionLabel: 'Hide map',
              onAction: () => setState(() => _c = _c.copyWith(template: ShareTemplate.minimal)),
            ),
          ],
          const SectionHeader(title: 'Template'),
          StrideSegmented<ShareTemplate>(
            values: templates,
            selected: templates.contains(_c.template) ? _c.template : templates.first,
            labelOf: (t) => switch (t) {
              ShareTemplate.map => 'Map',
              ShareTemplate.photo => 'Photo',
              ShareTemplate.minimal => 'Minimal',
            },
            onChanged: (t) => setState(() => _c = _c.copyWith(template: t)),
          ),
          if (_c.template == ShareTemplate.photo && photos.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = photos[i];
                  final sel = p.id == photo?.id;
                  return Semantics(
                    button: true,
                    selected: sel,
                    label: 'Photo ${i + 1}',
                    child: GestureDetector(
                      onTap: () => setState(() => _c = _c.copyWith(photoId: p.id)),
                      child: Container(
                        width: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(StrideRadius.small),
                          border: Border.all(color: sel ? StrideColors.primary : StrideColors.borderSubtle, width: sel ? 3 : 1),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(File(p.localPath!), fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SectionHeader(title: 'Show on image'),
          SettingsGroup(
            children: [
              _toggle('Distance', _c.showDistance, (v) => _c = _c.copyWith(showDistance: v)),
              _toggle('Time', _c.showTime, (v) => _c = _c.copyWith(showTime: v)),
              _toggle('Pace', _c.showPace, (v) => _c = _c.copyWith(showPace: v)),
              _toggle('Date', _c.showDate, (v) => _c = _c.copyWith(showDate: v)),
            ],
          ),
          if (_c.template == ShareTemplate.map && original.isNotEmpty) ...[
            const SectionHeader(title: 'Location privacy'),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.shield_outlined,
                  title: 'Hide start & finish',
                  subtitle: _c.hideEnds
                      ? 'The route within ${_c.hideRadiusM.round()} m of where you started and finished is removed from the image.'
                      : 'Your full route, including start and finish, will be visible.',
                  showChevron: false,
                  trailing: Switch(
                    value: _c.hideEnds,
                    onChanged: (v) => setState(() => _c = _c.copyWith(hideEnds: v)),
                  ),
                  onTap: () => setState(() => _c = _c.copyWith(hideEnds: !_c.hideEnds)),
                ),
                if (_c.hideEnds)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final r in hideRadiusOptions)
                          StrideChip(
                            label: '${r.round()} m',
                            selected: _c.hideRadiusM == r,
                            onTap: () => setState(() => _c = _c.copyWith(hideRadiusM: r)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text('Sharing creates an image only. It doesn\'t change who can see this activity in STRIDE.', style: StrideText.caption),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) apply) => SettingsRow(
    title: label,
    showChevron: false,
    trailing: Switch(value: value, onChanged: (v) => setState(() => apply(v))),
    onTap: () => setState(() => apply(!value)),
  );
}

/// Nội dung ảnh chia sẻ. Không chứa tile bản đồ (tránh tải mạng và giữ ảnh tái tạo được offline).
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.activity, required this.config, required this.format, required this.route, this.photoPath});

  final Activity activity;
  final ShareConfig config;
  final StrideFormat format;
  final RouteLines route;
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final onPhoto = config.template == ShareTemplate.photo && photoPath != null;
    final fg = onPhoto ? StrideColors.surface : StrideColors.textPrimary;
    final sub = onPhoto ? StrideColors.surface : StrideColors.textSecondary;
    final metrics = <(String, String)>[
      if (config.showDistance) (format.distance(a.distanceM), a.distanceSource == DistanceSource.gps ? 'Distance' : 'Distance · est.'),
      if (config.showTime) (formatDuration(a.movingMs), 'Moving time'),
      if (config.showPace) (format.pace(a.avgPaceSecPerKm), 'Avg. pace'),
    ];
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          activityDisplayTitle(a),
          style: StrideText.heading.copyWith(color: fg),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (config.showDate) Text(DateFormat('EEEE, MMMM d, y', 'en_US').format(activityLocalStart(a)), style: StrideText.label.copyWith(color: sub)),
      ],
    );
    final metricRow = Row(
      children: [
        for (final (v, l) in metrics)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v,
                  style: StrideText.metricSmall.copyWith(color: fg, fontSize: 20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(l, style: StrideText.caption.copyWith(color: sub)),
              ],
            ),
          ),
      ],
    );
    final brand = Text(
      'STRIDE',
      style: TextStyle(
        fontFamily: StrideText.fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 16,
        letterSpacing: 0.5,
        color: onPhoto ? StrideColors.lime : StrideColors.iconNavy,
      ),
    );

    switch (config.template) {
      case ShareTemplate.photo when photoPath != null:
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(photoPath!), fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [StrideColors.textPrimary.withValues(alpha: 0.1), StrideColors.textPrimary.withValues(alpha: 0.75)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [brand, const Spacer(), header, const SizedBox(height: 12), metricRow]),
            ),
          ],
        );
      case ShareTemplate.map when route.isNotEmpty:
        return ColoredBox(
          color: StrideColors.canvas,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: header),
                    brand,
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(StrideRadius.card)),
                    child: CustomPaint(
                      // Không vẽ marker khi đã ẩn đầu/cuối: marker sẽ lộ vị trí.
                      painter: RoutePainter(route: route, strokeWidth: 4, padding: 20, showMarkers: !config.hideEnds),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                metricRow,
              ],
            ),
          ),
        );
      default:
        return ColoredBox(
          color: StrideColors.subtle,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                const Spacer(),
                header,
                const SizedBox(height: 20),
                for (final (v, l) in metrics) ...[
                  Text(v, style: StrideText.metric.copyWith(fontSize: 40, height: 1.1)),
                  Text(l, style: StrideText.label.copyWith(color: StrideColors.textSecondary)),
                  const SizedBox(height: 12),
                ],
                const Spacer(),
              ],
            ),
          ),
        );
    }
  }
}
