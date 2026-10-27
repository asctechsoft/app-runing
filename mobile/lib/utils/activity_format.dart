import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/data_models/activity.dart';
import '../values/routes.dart';
import 'date_locale.dart';
import 'l10n.dart';

/// Nhãn hiển thị dùng chung cho History / Detail / Progress.
String activityTypeLabel(ActivityType t) => switch (t) {
  ActivityType.run => 'activity_type_run'.tr,
  ActivityType.walk => 'activity_type_walk'.tr,
  ActivityType.indoorRun => 'activity_type_indoor_run'.tr,
};

String feelingLabel(Feeling? f) => switch (f) {
  Feeling.easy => 'activity_feeling_easy'.tr,
  Feeling.steady => 'activity_feeling_steady'.tr,
  Feeling.hard => 'activity_feeling_hard'.tr,
  null => 'activity_feeling_not_set'.tr,
};

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'activity_privacy_only_me'.tr,
  Privacy.followers => 'activity_privacy_followers'.tr,
  Privacy.public => 'activity_privacy_everyone'.tr,
};

String privacyDescription(Privacy p) => switch (p) {
  Privacy.onlyMe => 'activity_privacy_only_me_desc'.tr,
  Privacy.followers => 'activity_privacy_followers_desc'.tr,
  Privacy.public => 'activity_privacy_everyone_desc'.tr,
};

/// Thời điểm bắt đầu theo giờ địa phương nơi ghi (dùng offset đã lưu cùng hoạt động).
DateTime activityLocalStart(Activity a) => DateTime.fromMillisecondsSinceEpoch(a.startedAt, isUtc: true).add(Duration(minutes: a.tzOffsetMin));

/// Tiêu đề hiển thị: tên người dùng đặt, nếu trống thì "Morning run"... theo giờ bắt đầu (không bịa dữ liệu).
String activityDisplayTitle(Activity a) {
  if (a.title.trim().isNotEmpty) return a.title.trim();
  final h = activityLocalStart(a).hour;
  final part = h < 5
      ? 'night'
      : h < 12
      ? 'morning'
      : h < 17
      ? 'afternoon'
      : h < 21
      ? 'evening'
      : 'night';
  final kind = switch (a.type) {
    ActivityType.run => 'run',
    ActivityType.walk => 'walk',
    ActivityType.indoorRun => 'indoor_run',
  };
  return 'activity_title_${part}_$kind'.tr;
}

/// "Thursday, October 15 · 7:20 AM" (+ "UTC+07:00" nếu múi giờ ghi khác múi giờ máy hiện tại).
String activityDateTimeLabel(Activity a, {bool withTime = true, int? deviceOffsetMin}) {
  final local = activityLocalStart(a);
  final date = AppDates.weekdayMonthDay(local);
  if (!withTime) return date;
  final time = AppDates.time(local);
  final dev = deviceOffsetMin ?? DateTime.now().timeZoneOffset.inMinutes;
  final tz = dev == a.tzOffsetMin ? '' : ' (${utcOffsetLabel(a.tzOffsetMin)})';
  return '$date · $time$tz';
}

String utcOffsetLabel(int offsetMin) {
  final sign = offsetMin < 0 ? '-' : '+';
  final abs = offsetMin.abs();
  return 'UTC$sign${(abs ~/ 60).toString().padLeft(2, '0')}:${(abs % 60).toString().padLeft(2, '0')}';
}

/// Đường dẫn chi tiết hoạt động trong tab hiện tại (Home / Progress / History) để back giữ đúng stack.
String activityPathFor(BuildContext context, String id) {
  String path;
  try {
    path = GoRouterState.of(context).uri.path;
  } catch (_) {
    path = Routes.history;
  }
  if (path.startsWith(Routes.home)) return Routes.homeActivity(id);
  if (path.startsWith(Routes.progress)) return Routes.progressActivity(id);
  return Routes.historyActivity(id);
}
