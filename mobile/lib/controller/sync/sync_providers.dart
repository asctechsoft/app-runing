import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../../services/application/firebase_providers.dart';
import '../../services/application/sync_remote.dart';
import '../../services/application/sync_service.dart';

/// Kênh Firestore của engine sync. Lazy: chỉ chạm `FirebaseFirestore` khi thật sự đồng bộ. Override trong test bằng bản in-memory.
final syncRemoteProvider = Provider<SyncRemote>((ref) => FirestoreSyncRemote(() => ref.read(firestoreProvider)));

/// Luồng online/offline (true = có mạng). Override trong test để không gọi plugin.
final syncConnectivityProvider = Provider<Stream<bool>>((ref) {
  try {
    return Connectivity().onConnectivityChanged.map((r) => r.any((c) => c != ConnectivityResult.none));
  } catch (_) {
    return const Stream<bool>.empty();
  }
});

/// Engine đồng bộ dùng chung toàn app (H03). StartupScreen gọi `start()` sau khi điều hướng.
final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(
    db: ref.watch(databaseProvider),
    activities: ref.watch(activityRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    remote: ref.watch(syncRemoteProvider),
    uid: () => ref.read(currentUidProvider),
    ready: () => ref.read(firebaseReadyProvider),
    clock: ref.watch(clockProvider),
    owner: () => ref.read(ownerProvider),
    enabled: ref.watch(flagsProvider).sync,
    online: ref.watch(syncConnectivityProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});

/// Trạng thái sync (idle/syncing/error/offline/signedOut + pending/conflicts) cho các màn khác.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final s = ref.watch(syncServiceProvider);
  // Đổi owner (đăng nhập/đăng xuất) → tính lại số pending theo owner mới.
  ref.watch(ownerProvider);
  yield s.status.value;
  unawaited(s.refreshStatus());
  yield* s.statusChanges;
});

/// Danh sách xung đột đang chờ chọn của owner hiện tại.
final syncConflictsProvider = FutureProvider.autoDispose<List<SyncConflict>>((ref) async {
  ref.watch(syncStatusProvider);
  return ref.watch(syncServiceProvider).conflicts(ref.watch(ownerProvider).ownerId);
});
