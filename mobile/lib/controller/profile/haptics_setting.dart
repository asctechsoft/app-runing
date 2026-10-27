import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/pref_const.dart';
import '../../utils/haptics.dart';
import '../providers.dart';

/// T06: bật/tắt rung — cài đặt theo THIẾT BỊ (không đồng bộ tài khoản), mặc định bật. Đồng bộ vào [StrideHaptics.enabled].
class HapticsSetting extends Notifier<bool> {
  @override
  bool build() {
    final v = ref.read(sharedPrefsProvider).getBool(PrefConst.hapticsEnabled) ?? true;
    StrideHaptics.enabled = v;
    return v;
  }

  Future<void> set(bool enabled) async {
    StrideHaptics.enabled = enabled;
    state = enabled;
    await ref.read(sharedPrefsProvider).setBool(PrefConst.hapticsEnabled, enabled);
    // Rung xác nhận khi vừa bật (không rung khi tắt).
    if (enabled) StrideHaptics.selection();
  }
}

final hapticsSettingProvider = NotifierProvider<HapticsSetting, bool>(HapticsSetting.new);
