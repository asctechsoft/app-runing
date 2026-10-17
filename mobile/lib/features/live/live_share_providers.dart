import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/permissions/permission_coordinator.dart';
import '../../core/providers.dart';
import '../../core/run_plugins.dart';
import 'live_share_models.dart';
import 'live_share_plugin.dart';
import 'live_share_repository.dart';

final liveShareRepositoryProvider = Provider<LiveShareRepository>((ref) => LiveShareRepository(ref.watch(apiClientProvider)));

/// Cấu hình chia sẻ chờ cho buổi chạy kế tiếp (mặc định tắt).
class LiveShareConfigNotifier extends Notifier<LiveShareConfig> {
  @override
  LiveShareConfig build() => const LiveShareConfig();

  void setEnabled(bool v) => state = state.copyWith(enabled: v, consentedAt: () => null);
  void setExpiry(LiveShareExpiry e) => state = state.copyWith(expiry: e, consentedAt: () => null);

  /// Thêm người xem; trả false nếu đã có hoặc vượt giới hạn 20 của server.
  bool addViewer(LiveShareViewer v) {
    if (state.viewers.contains(v) || state.viewers.length >= 20) return false;
    state = state.copyWith(viewers: [...state.viewers, v], consentedAt: () => null);
    return true;
  }

  void removeViewer(LiveShareViewer v) => state = state.copyWith(
    viewers: [
      for (final x in state.viewers)
        if (x != v) x,
    ],
    consentedAt: () => null,
  );

  /// Ghi nhận đồng ý sau màn consent.
  void consent(int nowMs) => state = state.copyWith(consentedAt: () => nowMs);

  /// Xóa cấu hình (Cancel hoặc sau khi phiên bắt đầu).
  void clear() => state = const LiveShareConfig();

  void set(LiveShareConfig c) => state = c;
}

final liveShareConfigProvider = NotifierProvider<LiveShareConfigNotifier, LiveShareConfig>(LiveShareConfigNotifier.new);

class LiveShareStatusNotifier extends Notifier<LiveShareStatus> {
  @override
  LiveShareStatus build() => const LiveShareStatus();
  void set(LiveShareStatus s) => state = s;
}

/// Trạng thái chia sẻ trong phiên: off / starting / active / paused / interrupted (kèm last update) / ended / failed.
final liveShareStatusProvider = NotifierProvider<LiveShareStatusNotifier, LiveShareStatus>(LiveShareStatusNotifier.new);

/// Plugin M07; null khi flag live.sharing tắt. Integrator ghép vào runPluginsProvider.
final liveShareRunPluginProvider = Provider<RunPlugin?>((ref) {
  if (!ref.watch(flagsProvider).liveSharing) return null;
  return LiveSharePlugin(
    repository: ref.watch(liveShareRepositoryProvider),
    clock: ref.watch(clockProvider),
    readConfig: () => ref.read(liveShareConfigProvider),
    clearConfig: () => ref.read(liveShareConfigProvider.notifier).clear(),
    onStatus: (s) => ref.read(liveShareStatusProvider.notifier).set(s),
    isGuest: () => ref.read(ownerProvider).isGuest,
  );
});

/// Vị trí gần nhất đã biết cho bản đồ xem trước — đọc một lần, chỉ khi đã có quyền vị trí; không theo dõi.
final liveSharePreviewPositionProvider = FutureProvider.autoDispose<LatLng?>((ref) async {
  final perm = await ref.watch(permissionsProvider).status(PermKind.location);
  if (perm != PermStatus.granted && perm != PermStatus.limited) return null;
  try {
    final p = await Geolocator.getLastKnownPosition();
    return p == null ? null : LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
});
