import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../domain/models/activity.dart';

/// Nhãn hiển thị dùng chung cho History / Detail / Progress.
String activityTypeLabel(ActivityType t) => switch (t) {
  ActivityType.run => 'Run',
  ActivityType.walk => 'Walk',
  ActivityType.indoorRun => 'Indoor run',
};

String feelingLabel(Feeling? f) => switch (f) {
  Feeling.easy => 'Easy',
  Feeling.steady => 'Steady',
  Feeling.hard => 'Hard',
  null => 'Not set',
};

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only me',
  Privacy.followers => 'Followers',
  Privacy.public => 'Everyone',
};

String privacyDescription(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only you can see this activity.',
  Privacy.followers => 'People who follow you can see this activity.',
  Privacy.public => 'Anyone with access to your profile can see this activity.',
};

/// Thời điểm bắt đầu theo giờ địa phương nơi ghi (dùng offset đã lưu cùng hoạt động).
DateTime activityLocalStart(Activity a) => DateTime.fromMillisecondsSinceEpoch(a.startedAt, isUtc: true).add(Duration(minutes: a.tzOffsetMin));

/// Tiêu đề hiển thị: tên người dùng đặt, nếu trống thì "Morning run"... theo giờ bắt đầu (không bịa dữ liệu).
String activityDisplayTitle(Activity a) {
  if (a.title.trim().isNotEmpty) return a.title.trim();
  final h = activityLocalStart(a).hour;
  final part = h < 5
      ? 'Night'
      : h < 12
      ? 'Morning'
      : h < 17
      ? 'Afternoon'
      : h < 21
      ? 'Evening'
      : 'Night';
  return '$part ${activityTypeLabel(a.type).toLowerCase()}';
}

/// "Thursday, October 15 · 7:20 AM" (+ "UTC+07:00" nếu múi giờ ghi khác múi giờ máy hiện tại).
String activityDateTimeLabel(Activity a, {bool withTime = true, int? deviceOffsetMin}) {
  final local = activityLocalStart(a);
  final date = DateFormat('EEEE, MMMM d', 'en_US').format(local);
  if (!withTime) return date;
  final time = DateFormat('h:mm a', 'en_US').format(local);
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
