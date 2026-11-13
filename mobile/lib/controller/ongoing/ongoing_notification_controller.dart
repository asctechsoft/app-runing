import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/pref_const.dart';
import '../../models/data_models/session_state.dart';
import '../../services/application/ongoing_notification_service.dart';
import '../../services/application/reminder_scheduler.dart';
import '../../services/native/permission_coordinator.dart';
import '../../utils/clock.dart';
import '../../utils/l10n.dart';
import '../language/language_controller.dart';
import '../providers.dart';
import '../run/engine/run_session_controller.dart';
import '../run/engine/run_session_state.dart' show activityTypeLabel;
import '../steps/steps_providers.dart';

final ongoingNotificationServiceProvider = Provider<OngoingNotificationService>((ref) => OngoingNotificationService());

/// Khóa ngày địa phương hôm nay; đổi khi qua nửa đêm để thông báo bước chuyển sang ngày mới.
final _todayKeyProvider = StreamProvider<String>((ref) async* {
  final clock = ref.watch(clockProvider);
  var key = localDateKey(clock.nowLocal());
  yield key;
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 1))) {
    final next = localDateKey(clock.nowLocal());
    if (next != key) {
      key = next;
      yield key;
    }
  }
});

/// Thông báo đang chạy ở native: (1) số bước hôm nay luôn hiện khi đã cấp quyền chuyển động, (2) thẻ buổi chạy
/// (thời gian + quãng đường) khi đang ghi hoặc tạm dừng. Giữ sống trong `StrideApp` bằng `ref.watch`.
final ongoingNotificationsProvider = Provider<void>((ref) {
  final svc = ref.watch(ongoingNotificationServiceProvider);
  final todayKey = ref.watch(_todayKeyProvider).value;

  void pushSteps() {
    if (todayKey == null) return;
    final perm = ref.read(stepsMotionPermissionProvider).value;
    if (perm == null) return;
    if (!isMotionGranted(perm)) {
      unawaited(svc.hideSteps());
      return;
    }
    unawaited(_askNotificationOnce(ref));
    final view = ref.read(stepsDayProvider(todayKey)).value;
    final steps = view?.day.steps;
    final fmt = ref.read(formatProvider);
    final goal = view?.goal;
    final goalText = goal == null ? 'ongoing_steps_no_goal'.tr : 'ongoing_steps_goal'.trArgs([fmt.steps(goal)]);
    // Chưa có số liệu thật thì hiện "đang đếm" (không bịa số 0); có số liệu thì hiện số bước + mục tiêu.
    unawaited(
      svc.showSteps(
        channel: 'ongoing_channel_steps'.tr,
        title: steps == null ? 'ongoing_steps_waiting'.tr : 'steps_count'.trArgs([fmt.steps(steps)]),
        text: goalText,
        progress: steps == null || goal == null || goal <= 0 ? null : (steps * 100 ~/ goal).clamp(0, 100),
      ),
    );
  }

  void pushRun() {
    final st = ref.read(runSessionProvider);
    if (!st.isActive) {
      unawaited(svc.hideRun());
      return;
    }
    final fmt = ref.read(formatProvider);
    final recording = st.phase == SessionPhase.recording;
    unawaited(
      svc.showRun(
        channel: 'ongoing_channel_run'.tr,
        title: recording ? 'ongoing_run_title'.tr : 'run_live_paused'.tr,
        subtitle: activityTypeLabel(st.setup.type),
        timeLabel: 'ongoing_run_time'.tr,
        distanceLabel: 'run_label_distance'.tr,
        distance: fmt.distance(st.distanceM),
        movingMs: ref.read(runSessionProvider.notifier).movingMsNow(),
        running: recording,
      ),
    );
  }

  ref.listen(stepsMotionPermissionProvider, (_, _) => pushSteps());
  if (todayKey != null) ref.listen(stepsDayProvider(todayKey), (_, _) => pushSteps());
  ref.listen(runSessionProvider.select((s) => (s.phase, s.distanceM)), (_, _) => pushRun());
  // Đổi ngôn ngữ hoặc đơn vị: vẽ lại chữ (service bỏ qua khi nội dung không đổi).
  ref.listen(languageProvider.select((s) => s.locale), (_, _) {
    pushSteps();
    pushRun();
  });
  ref.listen(formatProvider, (_, _) {
    pushSteps();
    pushRun();
  });
  ref.onDispose(() {
    unawaited(svc.hideSteps());
    unawaited(svc.hideRun());
  });
  pushSteps();
  pushRun();
});

/// Android 13+ ẩn mọi thông báo cho tới khi cấp quyền: hỏi MỘT lần ngay khi đã có quyền chuyển động (người dùng vừa bật đếm bước)
/// để thông báo số bước và nhắc giờ hiện được; sau đó đồng bộ lại lịch nhắc. Bị từ chối thì không hỏi lại (xin lại ở màn Nhắc nhở).
Future<void> _askNotificationOnce(Ref ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool(PrefConst.notificationAsked) ?? false) return;
  await prefs.setBool(PrefConst.notificationAsked, true);
  final perms = ref.read(permissionsProvider);
  final status = await perms.status(PermKind.notification);
  if (isNotificationGranted(status) || status == PermStatus.blocked || status == PermStatus.restricted) return;
  await perms.request(PermKind.notification);
  perms.refresh();
  await ref.read(remindersSyncProvider)();
}
