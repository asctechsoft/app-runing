import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../app/routes.dart';
import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../data/activity_repository.dart';
import '../../data/owner_repository.dart';
import '../../data/settings_repository.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_service.dart';
import 'auth_repository.dart';
import 'google_sign_in_service.dart';

/// Chuyển dữ liệu khách sang tài khoản (E03). Idempotent: chạy lại không nhân đôi, không đụng owner khác.
class GuestTransferService {
  GuestTransferService({
    required AppDatabase db,
    required ActivityRepository activities,
    required SettingsRepository settings,
    required OwnerRepository owners,
    required SharedPreferences prefs,
  }) : _db = db,
       _prefs = prefs,
       _activities = activities,
       _settings = settings,
       _owners = owners;

  final AppDatabase _db;
  final ActivityRepository _activities;
  final SettingsRepository _settings;
  final OwnerRepository _owners;
  final SharedPreferences _prefs;

  /// Trả số hoạt động được chuyển ở lần gọi này (0 nếu đã chuyển trước đó).
  Future<int> transfer({required String guestId, required String userId}) async {
    if (!guestId.startsWith('guest:') || userId.startsWith('guest:') || guestId == userId) {
      throw ArgumentError('transfer chỉ từ owner khách sang tài khoản');
    }
    final moved = await _activities.transferOwnership(fromOwner: guestId, toOwner: userId);
    // transferOwnership tạo op mới cho user nhưng op cũ của khách (cùng idempotency_key, UNIQUE) vẫn mang owner khách
    // → op mới bị ignore. Chuyển các op khách sang user để engine sync của user xử lý; xóa bản trùng nếu có.
    await _db.db.transaction((txn) async {
      final guestOps = await txn.query('sync_outbox', where: "owner_id = ? AND state != 'acked'", whereArgs: [guestId]);
      for (final op in guestOps) {
        final entity = op['entity'] as String;
        if (entity == 'profile' || entity == 'settings') {
          // entityId của profile là userId; op của khách không áp dụng được.
          await txn.delete('sync_outbox', where: 'id = ?', whereArgs: [op['id']]);
          continue;
        }
        final dup = await txn.query(
          'sync_outbox',
          columns: ['id'],
          where: "owner_id = ? AND entity = ? AND entity_id = ? AND state != 'acked' AND id != ?",
          whereArgs: [userId, entity, op['entity_id'], op['id']],
        );
        if (dup.isNotEmpty) {
          await txn.delete('sync_outbox', where: 'id = ?', whereArgs: [op['id']]);
        } else {
          await txn.update('sync_outbox', {'owner_id': userId}, where: 'id = ?', whereArgs: [op['id']]);
        }
      }
      await txn.update(
        'kv',
        {'owner_id': userId},
        where: "owner_id = ? AND key LIKE 'sync.%'",
        whereArgs: [guestId],
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
    // Hồ sơ khách → tài khoản nếu tài khoản chưa có hồ sơ trên máy.
    final userSettings = await _settings.load(userId);
    final guestSettings = await _settings.load(guestId);
    if (userSettings.displayName.isEmpty && guestSettings.displayName.isNotEmpty) {
      await _settings.save(guestSettings.copyWith(ownerId: userId));
    }
    if (_owners.current().ownerId == userId && (_prefs.getBool('profile_setup_done:$guestId') ?? false)) {
      // Cùng khóa với OwnerRepository ('profile_setup_done:<owner>'): khách đã thiết lập thì tài khoản không phải làm lại.
      await _owners.markProfileSetupDone(userId);
    }
    return moved;
  }
}

final guestTransferProvider = Provider<GuestTransferService>(
  (ref) => GuestTransferService(
    db: ref.watch(databaseProvider),
    activities: ref.watch(activityRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    owners: ref.watch(ownerRepositoryProvider),
    prefs: ref.watch(sharedPrefsProvider),
  ),
);

/// Sau đăng nhập/đăng ký thành công: gắn owner, kiểm tra dữ liệu khách, chọn màn tiếp theo (F02 bước 3–5).
Future<String> completeSignInWidget(WidgetRef ref, AuthUser user) async {
  final read = ref.read;
  final owners = read(ownerRepositoryProvider);
  final guestId = owners.guestId();
  await owners.signIn(userId: user.id, email: user.email);
  await owners.markIntroSeen();
  // Hồ sơ trên server (best-effort, không chặn khi mạng yếu): tài khoản cũ trên máy mới không phải nhập lại.
  try {
    final me = await read(authRepositoryProvider).me().timeout(const Duration(seconds: 6));
    final profile = (me['profile'] as Map?)?.cast<String, Object?>();
    if (profile != null && (profile['displayName'] as String?)?.isNotEmpty == true) {
      final settingsRepo = read(settingsRepositoryProvider);
      final local = await settingsRepo.load(user.id);
      if (local.displayName.isEmpty) await settingsRepo.save(settingsFromServerProfile(local, profile), markDirty: false);
      await owners.markProfileSetupDone(user.id);
    }
  } catch (_) {}
  read(ownerProvider.notifier).reload();
  final guestCount = await read(activityRepositoryProvider).countSaved(guestId);
  unawaited(read(syncServiceProvider).syncNow());
  if (guestCount > 0) return Routes.mergeGuest;
  return read(ownerProvider).profileSetupDone ? Routes.home : Routes.setupProfile;
}

/// Màn tiếp theo sau khi xử lý dữ liệu khách.
String routeAfterMerge(OwnerState owner) => owner.profileSetupDone ? Routes.home : Routes.setupProfile;

/// Luồng "Continue with Google": chọn tài khoản → Firebase ID token → backend → cùng bước sau đăng nhập như email.
/// Trả route kế tiếp, hoặc null khi người dùng hủy. Ném lỗi để UI hiển thị thông báo.
Future<String?> signInWithGoogleWidget(WidgetRef ref) async {
  final String idToken;
  try {
    idToken = await ref.read(googleIdTokenSourceProvider).signInAndGetIdToken();
  } on GoogleSignInCancelled {
    return null;
  }
  final user = await ref.read(authRepositoryProvider).loginWithFirebase(idToken);
  return completeSignInWidget(ref, user);
}

/// Thông báo lỗi cho luồng Google.
String googleSignInErrorMessage(Object error) {
  if (error is GoogleSignInFailure) return "Couldn't sign in with Google. Check your connection and try again.";
  return authErrorMessage(error, AuthAction.login);
}
