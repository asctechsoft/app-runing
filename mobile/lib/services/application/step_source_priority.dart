import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/providers.dart';
import '../../models/data_models/steps.dart';
import '../../controller/profile/profile_logic.dart' show loadStepSourcePriority;

/// Thứ tự ưu tiên nguồn bước của owner (F02). Màn Data sources (profile) lưu vào kv 'stepSourcePriority';
/// kvSet không phát sự kiện đổi → Home invalidate provider này khi resume/pull-to-refresh.
/// Dùng chung parser của profile để chỉ có một định dạng. Dùng cho tổng hợp ngày ở Home/Daily steps.
final stepsSourcePriorityProvider = FutureProvider.autoDispose<List<StepSource>>((ref) async {
  final owner = ref.watch(ownerProvider).ownerId;
  ref.watch(settingsProvider); // làm mới khi settings đổi
  return loadStepSourcePriority(ref.read(settingsRepositoryProvider), owner);
});
