import '../../models/data_models/activity.dart';
import '../../models/data_models/profile.dart';
import '../../models/data_models/steps.dart';
import '../clock.dart';
import 'group_eligibility.dart';

/// Chuỗi cá nhân (TM20, ADR 0003 câu 2).
///
/// Ngày đạt = đạt mục tiêu bước của chính ngày đó **hoặc** có một buổi run/walk hợp lệ (TM24) bắt đầu trong ngày
/// (ngày địa phương theo múi giờ lưu cùng hoạt động). Mỗi tháng có [defaultFreezesPerMonth] ngày bảo lưu: ngày không đạt
/// được bắc cầu nếu còn lượt, nhưng không cộng vào số ngày. Lượt chỉ bị trừ khi chuỗi thực sự nối tiếp được; hôm nay
/// chưa kết thúc nên chưa đạt cũng không làm mất chuỗi. Không giả lập ngày thiếu dữ liệu: ngày đó chỉ được giữ nhờ bảo lưu.
const defaultFreezesPerMonth = 2;

/// Giới hạn lịch sử dùng để tính (chuỗi dài hơn ~2 năm hiếm, tránh quét toàn bộ dữ liệu).
const streakHistoryDays = 730;

class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    required this.todayAchieved,
    required this.freezesLeftThisMonth,
    this.frozenDays = const {},
  });

  static const empty = StreakSummary(current: 0, longest: 0, todayAchieved: false, freezesLeftThisMonth: defaultFreezesPerMonth);

  /// Số ngày đạt trong chuỗi đang giữ (không tính ngày bảo lưu).
  final int current;
  final int longest;
  final bool todayAchieved;
  final int freezesLeftThisMonth;

  /// Các ngày (YYYY-MM-DD) đang được bảo lưu trong chuỗi hiện tại.
  final Set<String> frozenDays;

  /// Có chuỗi nhưng hôm nay chưa đạt → dùng cho nhắc giữ chuỗi (TM52).
  bool get atRisk => current > 0 && !todayAchieved;
}

/// Tập ngày đạt từ dữ liệu bước + hoạt động.
Set<String> achievedDayKeys({required Iterable<StepDay> days, required List<GoalVersion> goals, required Iterable<Activity> activities}) {
  final out = <String>{};
  for (final d in days) {
    if (!d.hasValue) continue;
    final goal = goalForDate(goals, GoalType.dailySteps, d.date)?.value;
    if (goal != null && goal > 0 && (d.steps ?? 0) >= goal) out.add(d.date);
  }
  for (final a in activities) {
    if (isStreakEligible(a)) out.add(localDateKeyFor(a.startedAt, a.tzOffsetMin));
  }
  return out;
}

/// Tính chuỗi từ [achieved] đến hết [today] (giờ địa phương). [freezesPerMonth] = 0 để tắt bảo lưu.
StreakSummary computeStreak({required DateTime today, required Set<String> achieved, int freezesPerMonth = defaultFreezesPerMonth}) {
  final t = DateTime(today.year, today.month, today.day);
  final todayKey = localDateKey(t);
  final monthKey = todayKey.substring(0, 7);
  if (achieved.isEmpty) {
    return StreakSummary(current: 0, longest: 0, todayAchieved: false, freezesLeftThisMonth: freezesPerMonth);
  }
  final earliest = achieved.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  final limit = DateTime(t.year, t.month, t.day - streakHistoryDays);
  var d = parseDateKey(earliest);
  d = DateTime(d.year, d.month, d.day);
  if (d.isBefore(limit)) d = limit;

  final used = <String, int>{}; // tháng → số lượt đã trừ
  var pending = <String>[]; // ngày bảo lưu chờ chuỗi nối tiếp mới trừ lượt
  var run = 0;
  var longest = 0;
  while (!d.isAfter(t)) {
    final key = localDateKey(d);
    if (achieved.contains(key)) {
      for (final p in pending) {
        used.update(p.substring(0, 7), (v) => v + 1, ifAbsent: () => 1);
      }
      pending = [];
      run++;
      if (run > longest) longest = run;
    } else if (key != todayKey) {
      final m = key.substring(0, 7);
      final inMonth = (used[m] ?? 0) + pending.where((p) => p.startsWith(m)).length;
      if (run > 0 && inMonth < freezesPerMonth) {
        pending.add(key);
      } else {
        run = 0;
        pending = [];
      }
    }
    d = DateTime(d.year, d.month, d.day + 1);
  }
  // Ngày bảo lưu cuối chuỗi đang giữ chuỗi sống → tính là đã dùng.
  final usedThisMonth = (used[monthKey] ?? 0) + pending.where((p) => p.startsWith(monthKey)).length;
  final frozen = <String>{};
  if (run > 0) {
    // Liệt kê ngày bảo lưu trong chuỗi hiện tại: đi lùi từ hôm qua đến ngày đạt đầu tiên của chuỗi.
    var counted = 0;
    var b = DateTime(t.year, t.month, t.day);
    while (counted < run) {
      final key = localDateKey(b);
      if (achieved.contains(key)) {
        counted++;
      } else if (key != todayKey) {
        frozen.add(key);
      }
      b = DateTime(b.year, b.month, b.day - 1);
    }
  }
  return StreakSummary(
    current: run,
    longest: longest,
    todayAchieved: achieved.contains(todayKey),
    freezesLeftThisMonth: (freezesPerMonth - usedThisMonth).clamp(0, freezesPerMonth),
    frozenDays: frozen,
  );
}
