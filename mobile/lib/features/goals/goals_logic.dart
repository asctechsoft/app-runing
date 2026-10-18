import '../../domain/models/profile.dart';

/// Giới hạn hợp lệ của mục tiêu (F06).
abstract final class GoalLimits {
  static const minSteps = 1000;
  static const maxSteps = 100000;
  static const stepIncrement = 500;
  static const minRuns = 1;
  static const maxRuns = 14;
  static const minDistanceKm = 1.0;
  static const maxDistanceKm = 500.0;

  static const stepPresets = [4000, 6000, 8000, 10000];
  static const runPresets = [1, 2, 3, 4, 5];

  /// Preset quãng đường theo đơn vị hiển thị (km hoặc mi).
  static const distancePresets = [5, 10, 20, 30, 50];
}

/// Lỗi kiểm tra; null = hợp lệ.
String? validateDailySteps(int? v) {
  if (v == null) return 'Enter a daily step goal.';
  if (v < GoalLimits.minSteps || v > GoalLimits.maxSteps) return 'Choose between 1,000 and 100,000 steps.';
  return null;
}

String? validateWeeklyRuns(int? v) {
  if (v == null) return 'Enter a weekly run goal.';
  if (v < GoalLimits.minRuns || v > GoalLimits.maxRuns) return 'Choose between 1 and 14 runs.';
  return null;
}

/// [meters] là giá trị gốc; giới hạn tính theo km bất kể đơn vị hiển thị.
String? validateWeeklyDistanceM(double? meters) {
  if (meters == null) return 'Enter a weekly distance goal.';
  final km = meters / 1000;
  // Dung sai nhỏ cho làm tròn khi đổi mi ↔ km.
  if (km < GoalLimits.minDistanceKm - 1e-6 || km > GoalLimits.maxDistanceKm + 1e-6) return 'Choose between 1 and 500 km (about 0.6–310 mi).';
  return null;
}

/// Bộ giá trị mục tiêu đang chỉnh. null = chưa từng đặt.
class GoalDraft {
  const GoalDraft({this.dailySteps, this.weeklyRuns, this.weeklyDistanceM});
  final int? dailySteps;
  final int? weeklyRuns;
  final double? weeklyDistanceM;

  GoalDraft copyWith({int? dailySteps, int? weeklyRuns, double? weeklyDistanceM}) =>
      GoalDraft(dailySteps: dailySteps ?? this.dailySteps, weeklyRuns: weeklyRuns ?? this.weeklyRuns, weeklyDistanceM: weeklyDistanceM ?? this.weeklyDistanceM);

  Map<GoalType, String?> errors() => {
    GoalType.dailySteps: validateDailySteps(dailySteps),
    GoalType.weeklyRuns: validateWeeklyRuns(weeklyRuns),
    GoalType.weeklyDistanceM: validateWeeklyDistanceM(weeklyDistanceM),
  };

  bool get isValid => errors().values.every((e) => e == null);

  /// Các mục tiêu thay đổi so với [original] — chỉ những mục này mới tạo GoalVersion mới.
  Map<GoalType, double> changedFrom(GoalDraft original) {
    final out = <GoalType, double>{};
    if (dailySteps != null && dailySteps != original.dailySteps) out[GoalType.dailySteps] = dailySteps!.toDouble();
    if (weeklyRuns != null && weeklyRuns != original.weeklyRuns) out[GoalType.weeklyRuns] = weeklyRuns!.toDouble();
    final d = weeklyDistanceM;
    if (d != null && (original.weeklyDistanceM == null || (d - original.weeklyDistanceM!).abs() > 0.5)) out[GoalType.weeklyDistanceM] = d;
    return out;
  }
}

int clampSteps(int v) => v.clamp(GoalLimits.minSteps, GoalLimits.maxSteps);
int clampRuns(int v) => v.clamp(GoalLimits.minRuns, GoalLimits.maxRuns);
