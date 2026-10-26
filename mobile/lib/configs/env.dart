import 'package:asc_common/asc_common.dart';

/// Môi trường build (B03). Chọn bằng `--dart-define=STRIDE_ENV=staging` v.v.; không truyền thì suy ra từ `--flavor`
/// (product → production, còn lại → dev) để bản flavor product không bao giờ mang nhãn môi trường dev.
enum StrideEnv { dev, staging, production }

class EnvConfig {
  const EnvConfig({required this.env, required this.tileUrlTemplate, required this.tileAttribution, required this.flags, this.tileFallbackUrlTemplate = ''});

  final StrideEnv env;
  final String tileUrlTemplate;

  /// Nguồn tile dự phòng, dùng khi nguồn chính không tải được (mạng/ISP chặn tên miền, nguồn quá tải). Rỗng = không dự phòng.
  final String tileFallbackUrlTemplate;
  final String tileAttribution;
  final FeatureFlags flags;

  bool get isProduction => env == StrideEnv.production;

  static EnvConfig fromEnvironment() {
    const envName = String.fromEnvironment('STRIDE_ENV');
    const flavorDefault = AscBuildFlavor.isProduct ? StrideEnv.production : StrideEnv.dev;
    final env = StrideEnv.values.firstWhere((e) => e.name == envName, orElse: () => flavorDefault);
    const defaultTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    const tiles = String.fromEnvironment('STRIDE_TILE_URL', defaultValue: defaultTiles);
    // Chỉ dự phòng khi dùng nguồn mặc định; đã tự chọn nhà cung cấp riêng thì tôn trọng lựa chọn đó (truyền STRIDE_TILE_FALLBACK_URL nếu muốn).
    const fallback = String.fromEnvironment(
      'STRIDE_TILE_FALLBACK_URL',
      // OSM France (HOT): cùng dữ liệu OpenStreetMap, không cần API key, nhưng là máy chủ cộng đồng — chỉ để dev/dự phòng.
      // (CARTO voyager đã thôi cho dùng không key: trả ảnh watermark "API KEY REQUIRED".)
      defaultValue: tiles == defaultTiles ? 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png' : '',
    );
    const attribution = String.fromEnvironment('STRIDE_TILE_ATTRIBUTION', defaultValue: '© OpenStreetMap contributors');
    return EnvConfig(env: env, tileUrlTemplate: tiles, tileFallbackUrlTemplate: fallback, tileAttribution: attribution, flags: FeatureFlags.defaultsFor(env));
  }
}

/// Feature flag (docs/scope.md). Flag tắt → UI ẩn, không hiển thị nút giả.
class FeatureFlags {
  const FeatureFlags({
    this.authEmail = true,
    this.authApple = false,
    this.authGoogle = false,
    this.stepsHealth = false,
    this.notificationsInbox = true,
    this.workoutIntervals = true,
    this.workoutPlans = false,
    this.devicesBle = true,
    this.runIndoor = true,
    this.exploreClubs = true,
    this.exploreChallenges = true,
    this.exploreRoutes = true,
    this.liveSharing = true,
    this.sync = true,
  });

  final bool authEmail;
  final bool authApple;
  final bool authGoogle;
  final bool stepsHealth;
  final bool notificationsInbox;
  final bool workoutIntervals;
  final bool workoutPlans;
  final bool devicesBle;
  final bool runIndoor;
  final bool exploreClubs;
  final bool exploreChallenges;
  final bool exploreRoutes;
  final bool liveSharing;
  final bool sync;

  bool get exploreAny => exploreClubs || exploreChallenges || exploreRoutes;

  /// Flag phụ thuộc runtime (vd. Google chỉ bật khi Firebase khởi tạo được).
  FeatureFlags copyWith({bool? authGoogle}) => FeatureFlags(
    authEmail: authEmail,
    authApple: authApple,
    authGoogle: authGoogle ?? this.authGoogle,
    stepsHealth: stepsHealth,
    notificationsInbox: notificationsInbox,
    workoutIntervals: workoutIntervals,
    workoutPlans: workoutPlans,
    devicesBle: devicesBle,
    runIndoor: runIndoor,
    exploreClubs: exploreClubs,
    exploreChallenges: exploreChallenges,
    exploreRoutes: exploreRoutes,
    liveSharing: liveSharing,
    sync: sync,
  );

  static FeatureFlags defaultsFor(StrideEnv env) => const FeatureFlags();
}
