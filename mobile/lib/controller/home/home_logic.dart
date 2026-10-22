import '../../services/native/permission_coordinator.dart';
import '../../utils/clock.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/steps.dart';
import '../../services/application/step_tracking_service.dart';
import '../../utils/l10n.dart';

/// Trạng thái khối bước trên Home (Design System §06).
enum HomeStepState {
  /// Chưa cấp quyền motion và chưa có dữ liệu → "Turn on step tracking", không hiển thị 0.
  noPermission,

  /// Máy không có cảm biến bước.
  unavailable,

  /// Có quyền nhưng chưa có mẫu → "No step data yet" + thời điểm kiểm tra, không hiển thị 0.
  noData,

  /// Nguồn xác nhận 0 bước.
  verifiedZero,

  /// Có dữ liệu, chưa đạt mục tiêu.
  populated,

  /// Đạt mục tiêu (giữ bước thực kể cả > 100%).
  achieved,
}

bool _granted(PermStatus p) => p == PermStatus.granted || p == PermStatus.limited;

/// Quyết định trạng thái Home. Dữ liệu đã có trong ngày vẫn được hiển thị kể cả khi quyền bị thu hồi sau đó
/// (UI hiển thị thêm banner); thiếu dữ liệu không bao giờ thành 0.
HomeStepState decideHomeStepState({
  required PermStatus permission,
  required StepDay day,
  required int? goal,
  StepTrackingStatus tracking = StepTrackingStatus.idle,
}) {
  if (!day.hasValue) {
    if (!_granted(permission)) return HomeStepState.noPermission;
    if (tracking == StepTrackingStatus.unavailable) return HomeStepState.unavailable;
    return HomeStepState.noData;
  }
  final steps = day.steps ?? 0;
  if (goal != null && goal > 0 && steps >= goal) return HomeStepState.achieved;
  if (day.status == StepDayStatus.verifiedZero || steps == 0) return HomeStepState.verifiedZero;
  return HomeStepState.populated;
}

/// Trạng thái một ngày trong "Your week streak".
enum StreakDayStatus { achieved, missed, noData, future }

class StreakDay {
  const StreakDay({required this.date, required this.status});
  final DateTime date;
  final StreakDayStatus status;
}

class WeekStreak {
  const WeekStreak({required this.days});
  final List<StreakDay> days;
  int get achievedCount => days.where((d) => d.status == StreakDayStatus.achieved).length;
}

/// Tuần hiện tại (theo [weekStart]) — ngày đạt khi steps ≥ mục tiêu áp dụng cho chính ngày đó.
/// Ngày không có dữ liệu hoặc không có mục tiêu KHÔNG được tính là đạt.
WeekStreak computeWeekStreak({required DateTime today, required int weekStart, required Map<String, StepDay> days, required List<GoalVersion> goals}) {
  final start = startOfWeek(today, weekStart);
  final t = DateTime(today.year, today.month, today.day);
  final out = <StreakDay>[];
  for (var i = 0; i < 7; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    if (d.isAfter(t)) {
      out.add(StreakDay(date: d, status: StreakDayStatus.future));
      continue;
    }
    final key = localDateKey(d);
    final day = days[key];
    final goal = goalForDate(goals, GoalType.dailySteps, key)?.value;
    if (day == null || !day.hasValue) {
      out.add(StreakDay(date: d, status: StreakDayStatus.noData));
    } else if (goal != null && goal > 0 && (day.steps ?? 0) >= goal) {
      out.add(StreakDay(date: d, status: StreakDayStatus.achieved));
    } else {
      out.add(StreakDay(date: d, status: StreakDayStatus.missed));
    }
  }
  return WeekStreak(days: out);
}

/// Lời chào theo giờ địa phương; không có tên → chỉ lời chào.
String greetingFor(DateTime local, String? name) {
  final h = local.hour;
  final g = h < 5 ? 'home_greeting_evening'.tr : (h < 12 ? 'home_greeting_morning'.tr : (h < 18 ? 'home_greeting_afternoon'.tr : 'home_greeting_evening'.tr));
  final n = name?.trim() ?? '';
  if (n.isEmpty) return g;
  return 'home_greeting_name'.trArgs([g, n.split(RegExp(r'\s+')).first]);
}
