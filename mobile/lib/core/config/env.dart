/// Môi trường build (B03). Chọn bằng `--dart-define=STRIDE_ENV=staging` v.v.
enum StrideEnv { dev, staging, production }

class EnvConfig {
  const EnvConfig({required this.env, required this.apiBaseUrl, required this.tileUrlTemplate, required this.tileAttribution, required this.flags});

  final StrideEnv env;
  final String apiBaseUrl;
  final String tileUrlTemplate;
  final String tileAttribution;
  final FeatureFlags flags;

  bool get isProduction => env == StrideEnv.production;

  static EnvConfig fromEnvironment() {
    const envName = String.fromEnvironment('STRIDE_ENV', defaultValue: 'dev');
    final env = StrideEnv.values.firstWhere((e) => e.name == envName, orElse: () => StrideEnv.dev);
    const api = String.fromEnvironment('STRIDE_API_URL', defaultValue: '');
    // Android emulator truy cập host qua 10.0.2.2.
    final apiUrl = api.isNotEmpty ? api : (env == StrideEnv.dev ? 'http://10.0.2.2:3001/api/v1' : '');
    const tiles = String.fromEnvironment('STRIDE_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    const attribution = String.fromEnvironment('STRIDE_TILE_ATTRIBUTION', defaultValue: '© OpenStreetMap contributors');
    return EnvConfig(env: env, apiBaseUrl: apiUrl, tileUrlTemplate: tiles, tileAttribution: attribution, flags: FeatureFlags.defaultsFor(env));
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

  static FeatureFlags defaultsFor(StrideEnv env) => const FeatureFlags();
}
