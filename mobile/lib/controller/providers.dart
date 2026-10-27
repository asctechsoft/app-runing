import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../configs/env.dart';
import '../models/data_models/profile.dart';
import '../repository/activity_repository.dart';
import '../repository/owner_repository.dart';
import '../repository/settings_repository.dart';
import '../repository/step_repository.dart';
import '../services/native/permission_coordinator.dart';
import '../services/storage/app_database.dart';
import '../utils/clock.dart';
import '../utils/formatters.dart';
import 'language/language_controller.dart';

// Các provider gốc được override trong main()/test (C01: UI chỉ gọi repository/use case).
final envProvider = Provider<EnvConfig>((ref) => EnvConfig.fromEnvironment());
final flagsProvider = Provider<FeatureFlags>((ref) => ref.watch(envProvider).flags);
final clockProvider = Provider<Clock>((ref) => SystemClock());
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override databaseProvider'));
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override sharedPrefsProvider'));
final permissionsProvider = Provider<PermissionCoordinator>((ref) => DevicePermissionCoordinator());

final ownerRepositoryProvider = Provider<OwnerRepository>((ref) => OwnerRepository(ref.watch(sharedPrefsProvider)));
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository(ref.watch(databaseProvider), ref.watch(clockProvider)));
final activityRepositoryProvider = Provider<ActivityRepository>((ref) => ActivityRepository(ref.watch(databaseProvider), ref.watch(clockProvider)));
final stepRepositoryProvider = Provider<StepRepository>((ref) => StepRepository(ref.watch(databaseProvider), ref.watch(clockProvider)));

/// Owner hiện tại. Gọi `ref.read(ownerProvider.notifier).reload()` sau đăng nhập/đăng xuất/onboarding.
class OwnerNotifier extends Notifier<OwnerState> {
  @override
  OwnerState build() => ref.watch(ownerRepositoryProvider).current();

  void reload() => state = ref.read(ownerRepositoryProvider).current();
}

final ownerProvider = NotifierProvider<OwnerNotifier, OwnerState>(OwnerNotifier.new);

/// Settings của owner hiện tại; tự làm mới khi repository phát thay đổi.
final settingsProvider = StreamProvider<UserSettings>((ref) async* {
  final owner = ref.watch(ownerProvider).ownerId;
  final repo = ref.watch(settingsRepositoryProvider);
  yield await repo.load(owner);
  await for (final changed in repo.changes) {
    if (changed == owner) yield await repo.load(owner);
  }
});

/// Formatter theo đơn vị người dùng; mặc định km khi settings chưa tải xong.
/// L09: số theo ngôn ngữ app (dấu thập phân/phân tách hàng nghìn), không theo `localeTag` đã lưu; đổi ngôn ngữ → tính lại.
final formatProvider = Provider<StrideFormat>((ref) {
  final locale = ref.watch(languageProvider.select((l) => l.locale)).toString();
  final s = ref.watch(settingsProvider).value;
  return s == null
      ? StrideFormat(locale: locale)
      : StrideFormat(distanceUnit: s.distanceUnit, weightUnit: s.weightUnit, heightUnit: s.heightUnit, locale: locale);
});

/// Phiên bản dữ liệu hoạt động của owner — tăng mỗi khi có thay đổi, để các màn list/stat tự refresh.
final activityRevisionProvider = StreamProvider<int>((ref) async* {
  final owner = ref.watch(ownerProvider).ownerId;
  var n = 0;
  yield n;
  await for (final changed in ref.watch(activityRepositoryProvider).changes) {
    if (changed == owner) yield ++n;
  }
});

final stepRevisionProvider = StreamProvider<int>((ref) async* {
  final owner = ref.watch(ownerProvider).ownerId;
  var n = 0;
  yield n;
  await for (final changed in ref.watch(stepRepositoryProvider).changes) {
    if (changed == owner) yield ++n;
  }
});
