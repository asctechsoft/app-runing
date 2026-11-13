import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../controller/activity/activity_providers.dart';
import '../../repository/community_repository.dart' show maxCommunityImageBytes;
import '../../utils/formatters.dart';
import '../../utils/route_geometry.dart';
import '../screens_activity/share_activity_screen.dart';

/// Ảnh tuyến đường kèm bài Cộng đồng: cùng thẻ "Map" của màn chia sẻ ảnh, luôn ẩn 200 m đầu/cuối (không lộ nhà/nơi xuất phát).
const _communityConfig = ShareConfig(template: ShareTemplate.map, hideEnds: true, hideRadiusM: 200);

/// Tuyến đã ẩn đầu/cuối dùng để vẽ ảnh; rỗng khi buổi không có GPS hoặc phần còn lại quá ngắn (không nên đính kèm).
RouteLines communityRouteFor(ActivityDetailData d) {
  if (!d.hasRoute) return const [];
  final route = shareRouteFor(routeFromPoints(d.points), _communityConfig);
  return routeLengthM(route) < minVisibleRouteM ? const [] : route;
}

/// Raster hóa thẻ tuyến đường thành PNG nhỏ gọn (≤ [maxCommunityImageBytes]); null khi không có tuyến hợp lệ hoặc không dựng được.
/// Vẽ ngoài màn hình qua OverlayEntry (không ảnh hưởng giao diện đang xem).
Future<Uint8List?> renderCommunityRouteImage(BuildContext context, ActivityDetailData d, StrideFormat format) async {
  final route = communityRouteFor(d);
  if (route.isEmpty) return null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -shareCardSize.width * 2,
      top: 0,
      width: shareCardSize.width,
      height: shareCardSize.height,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: key,
            child: ShareCard(activity: d.activity, config: _communityConfig, format: format, route: route),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // Giảm độ phân giải dần cho tới khi vừa giới hạn kích thước của rules.
    for (final ratio in const [2.0, 1.5, 1.0]) {
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      if (bytes.length <= maxCommunityImageBytes) return bytes;
    }
    return null;
  } finally {
    entry.remove();
  }
}
