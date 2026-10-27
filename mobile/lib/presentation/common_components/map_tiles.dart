import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../configs/env.dart';
import '../../utils/l10n.dart';
import '../../utils/logger.dart';
import '../../values/tokens.dart';

/// MAP04: zoom tối đa của mọi bản đồ (ô phía trên `tileMaxNativeZoom` được phóng từ mức native).
const double mapMaxZoom = 20;

/// MAP04: khi tự canh khung theo lộ trình — tuyến rất ngắn (< 20 m) không phóng sát tới mức thấy từng viên gạch.
const double routeFitMaxZoom = 17;

/// Lớp tile bản đồ dùng chung cho mọi màn: nguồn chính + nguồn dự phòng (khi nguồn chính không tải được, ví dụ mạng chặn
/// `tile.openstreetmap.org`). Một chỗ cấu hình thay vì bốn `TileLayer` rải rác — đổi nhà cung cấp chỉ cần đổi `EnvConfig`.
///
/// MAP03: khi nhiều ô nền lỗi (cả nguồn dự phòng — mất mạng, bị chặn) hiện banner nhỏ trên bản đồ thay vì chỉ để nền xám;
/// lộ trình/vị trí vẫn vẽ bình thường vì không phụ thuộc tile. Đặt làm con của `FlutterMap` như một layer.
class StrideTileLayer extends StatefulWidget {
  const StrideTileLayer({super.key, required this.env, this.tileProvider});

  final EnvConfig env;

  /// Thay nguồn tải ô (test: tắt cache đĩa vì không có path_provider). null = mặc định của flutter_map.
  final TileProvider? tileProvider;

  /// Số ô lỗi trước khi coi là "không tải được nền" (một ô lẻ ở rìa lỗi thì không báo).
  static const errorThreshold = 4;

  @override
  State<StrideTileLayer> createState() => _StrideTileLayerState();
}

class _StrideTileLayerState extends State<StrideTileLayer> {
  int _errors = 0;

  void _onError(TileImage tile, Object error, StackTrace? stackTrace) {
    StrideLog.d('map', 'tile ${tile.coordinates} failed: $error');
    if (!mounted || _errors >= StrideTileLayer.errorThreshold) return;
    setState(() => _errors++);
  }

  @override
  Widget build(BuildContext context) {
    final env = widget.env;
    final unavailable = _errors >= StrideTileLayer.errorThreshold;
    return Stack(
      fit: StackFit.expand,
      children: [
        TileLayer(
          urlTemplate: env.tileUrlTemplate,
          fallbackUrl: env.tileFallbackUrlTemplate.isEmpty ? null : env.tileFallbackUrlTemplate,
          userAgentPackageName: 'com.asc.app_runing',
          errorTileCallback: _onError,
          maxNativeZoom: env.tileMaxNativeZoom,
          maxZoom: mapMaxZoom,
          tileProvider: widget.tileProvider,
        ),
        Positioned(
          left: StrideSpace.s8,
          right: StrideSpace.s8,
          top: StrideSpace.s8,
          child: AnimatedSwitcher(
            duration: StrideMotion.of(context, StrideMotion.state),
            child: unavailable ? const MapUnavailableBanner() : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Banner "không tải được nền bản đồ" — luôn có icon + chữ (không chỉ dựa vào màu).
class MapUnavailableBanner extends StatelessWidget {
  const MapUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s12, vertical: StrideSpace.s8),
        decoration: BoxDecoration(color: StrideColors.warningBg, borderRadius: BorderRadius.circular(StrideRadius.small)),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18, color: StrideColors.warning),
            const SizedBox(width: StrideSpace.s8),
            Expanded(
              child: Text('common_map_unavailable'.tr, style: StrideText.caption.copyWith(color: StrideColors.warning)),
            ),
          ],
        ),
      ),
    );
  }
}
