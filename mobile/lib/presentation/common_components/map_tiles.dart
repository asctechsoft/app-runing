import 'package:flutter_map/flutter_map.dart';

import '../../configs/env.dart';

/// Lớp tile bản đồ dùng chung cho mọi màn: nguồn chính + nguồn dự phòng (khi nguồn chính không tải được, ví dụ mạng chặn
/// `tile.openstreetmap.org`). Một chỗ cấu hình thay vì bốn `TileLayer` rải rác — đổi nhà cung cấp chỉ cần đổi `EnvConfig`.
TileLayer strideTileLayer(EnvConfig env, {ErrorTileCallBack? errorTileCallback}) => TileLayer(
  urlTemplate: env.tileUrlTemplate,
  fallbackUrl: env.tileFallbackUrlTemplate.isEmpty ? null : env.tileFallbackUrlTemplate,
  userAgentPackageName: 'com.asc.app_runing',
  errorTileCallback: errorTileCallback,
);
