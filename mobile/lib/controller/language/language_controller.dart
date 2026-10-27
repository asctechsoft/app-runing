import 'dart:async';
import 'dart:ui';

import 'package:asc_common/asc_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/pref_const.dart';
import '../../services/application/reminder_scheduler.dart';
import '../../utils/date_locale.dart';
import '../../utils/logger.dart';
import '../providers.dart';

/// Ngôn ngữ đang hiển thị và chế độ "theo hệ thống".
class LanguageState {
  const LanguageState({required this.locale, required this.followSystem});

  final Locale locale;
  final bool followSystem;

  @override
  bool operator ==(Object other) => other is LanguageState && other.locale == locale && other.followSystem == followSystem;

  @override
  int get hashCode => Object.hash(locale, followSystem);
}

/// L06: đổi ngôn ngữ lúc chạy. `AscLocale.setAppLocale` chỉ cập nhật GetX (app không có `GetMaterialApp`), nên mọi lần đổi
/// đi qua controller này: `StrideApp` nghe [languageProvider] để đổi `MaterialApp.locale` và dựng lại cây widget (`.tr` đọc lại).
class LanguageController extends Notifier<LanguageState> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  LanguageState build() => LanguageState(locale: AscLocale.getAppLocale(), followSystem: _prefs.getBool(PrefConst.followSystemLanguage) ?? false);

  /// Ghim một ngôn ngữ cụ thể (tắt "theo hệ thống").
  Future<void> select(Locale locale) async {
    await _prefs.setBool(PrefConst.followSystemLanguage, false);
    await AscLocale.setAppLocale(locale);
    _apply(followSystem: false);
  }

  /// "Theo hệ thống": dùng ngôn ngữ máy, lần mở sau dò lại (đổi ngôn ngữ máy thì app theo).
  Future<void> useSystemDefault() async {
    await AscLocale.useSystemLocale();
    _apply(followSystem: true);
  }

  /// Bấm "Tiếp tục" ở màn ngôn ngữ lần đầu: từ giờ không hỏi lại trên thiết bị này.
  Future<void> confirmFirstRun() => _prefs.setBool(PrefConst.languageChosen, true);

  void _apply({required bool followSystem}) {
    final changed = AscLocale.getAppLocale() != state.locale;
    Intl.defaultLocale = appDateLocale;
    state = LanguageState(locale: AscLocale.getAppLocale(), followSystem: followSystem);
    if (changed) unawaited(_rescheduleReminders());
  }

  /// L14: tiêu đề/nội dung nhắc nhở và tên kênh Android được dịch lúc lên lịch → lên lịch lại theo ngôn ngữ mới.
  Future<void> _rescheduleReminders() async {
    try {
      await ref.read(remindersSyncProvider)();
    } catch (e, st) {
      StrideLog.e('language', e, st);
    }
  }
}

final languageProvider = NotifierProvider<LanguageController, LanguageState>(LanguageController.new);

/// L19: đã chọn ngôn ngữ lần đầu chưa (cờ theo thiết bị). Người dùng cũ đã qua intro trước khi có màn này được coi là đã chọn
/// và giữ ngôn ngữ hiện tại — migration lặng lẽ ghi cờ, không ép chọn lại.
bool languageChosen(SharedPreferences prefs, {required bool introSeen}) {
  final chosen = prefs.getBool(PrefConst.languageChosen);
  if (chosen != null) return chosen;
  if (introSeen) {
    prefs.setBool(PrefConst.languageChosen, true);
    return true;
  }
  return false;
}
