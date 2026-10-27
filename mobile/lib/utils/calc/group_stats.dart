import '../../models/data_models/activity.dart';
import '../clock.dart';
import 'group_eligibility.dart';
import 'streak.dart';

/// Số liệu nhóm do từng thành viên tự tính và ghi (ADR 0003: client tính). Mỗi người chỉ chia sẻ khi tự bật (TM60),
/// và chỉ phần tổng hợp theo ngày: đạt hay chưa, quãng đường/số buổi/thời gian của hoạt động hợp lệ cho nhóm (TM24 — không
/// có hoạt động riêng tư `onlyMe`, không tọa độ, không số bước thô).

/// Số ngày gần nhất được chia sẻ (đủ cho mục tiêu tháng và chuỗi nhóm hiển thị tới "60+").
const groupStatsDays = 62;

class MemberDay {
  const MemberDay({required this.achieved, this.distanceM = 0, this.activities = 0, this.movingMs = 0});

  /// Đạt mục tiêu ngày theo quy tắc chuỗi cá nhân (TM20): mục tiêu bước hoặc một buổi hợp lệ.
  final bool achieved;
  final double distanceM;
  final int activities;
  final int movingMs;

  Map<String, Object> toMap() => {'a': achieved, 'd': distanceM, 'n': activities, 't': movingMs};

  static MemberDay fromMap(Object? m) {
    if (m is! Map) return const MemberDay(achieved: false);
    return MemberDay(
      achieved: m['a'] == true,
      distanceM: (m['d'] as num?)?.toDouble() ?? 0,
      activities: (m['n'] as num?)?.toInt() ?? 0,
      movingMs: (m['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ngày (YYYY-MM-DD, giờ địa phương) → số liệu, cho [groupStatsDays] ngày tính tới [today].
/// [achieved] là tập ngày đạt (từ `achievedDayKeys`); hoạt động chỉ cộng khi `isGroupEligible`.
Map<String, MemberDay> buildMemberDays({required DateTime today, required Set<String> achieved, required Iterable<Activity> activities}) {
  final t = DateTime(today.year, today.month, today.day);
  final keys = [for (var i = groupStatsDays - 1; i >= 0; i--) localDateKey(DateTime(t.year, t.month, t.day - i))];
  final sums = <String, (double, int, int)>{};
  for (final a in dropOverlapping(activities.where(isGroupEligible))) {
    final k = localDateKeyFor(a.startedAt, a.tzOffsetMin);
    final s = sums[k] ?? (0.0, 0, 0);
    sums[k] = (s.$1 + (a.distanceM ?? 0), s.$2 + 1, s.$3 + a.movingMs);
  }
  return {
    for (final k in keys) k: MemberDay(achieved: achieved.contains(k), distanceM: sums[k]?.$1 ?? 0, activities: sums[k]?.$2 ?? 0, movingMs: sums[k]?.$3 ?? 0),
  };
}

/// Số liệu một thành viên đang chia sẻ, đọc từ `clubs/{id}/memberStats/{uid}`.
class MemberStats {
  const MemberStats({required this.userId, required this.displayName, required this.days, this.updatedAt = 0});
  final String userId;
  final String displayName;
  final Map<String, MemberDay> days;
  final int updatedAt;

  factory MemberStats.fromDoc(String id, Map<String, Object?> d) {
    final raw = d['days'];
    return MemberStats(
      userId: id,
      displayName: '${d['displayName'] ?? ''}',
      days: raw is Map ? {for (final e in raw.entries) '${e.key}': MemberDay.fromMap(e.value)} : const {},
      updatedAt: (d['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// TM21: chuỗi nhóm — ngày đạt khi MỌI thành viên đang chia sẻ đều đạt. Dùng cùng thuật toán và ngày bảo lưu như chuỗi
/// cá nhân; hôm nay chưa xong chưa làm đứt. Chỉ có dữ liệu [groupStatsDays] ngày nên chuỗi tối đa bằng số đó.
class GroupStreak {
  const GroupStreak({required this.summary, required this.members, required this.doneToday});
  final StreakSummary summary;
  final int members;
  final int doneToday;
}

GroupStreak computeGroupStreak(List<MemberStats> members, DateTime today) {
  final todayKey = localDateKey(DateTime(today.year, today.month, today.day));
  if (members.isEmpty) return const GroupStreak(summary: StreakSummary.empty, members: 0, doneToday: 0);
  Set<String> done(MemberStats m) => {
    for (final e in m.days.entries)
      if (e.value.achieved) e.key,
  };
  var all = done(members.first);
  for (final m in members.skip(1)) {
    all = all.intersection(done(m));
  }
  return GroupStreak(
    summary: computeStreak(today: today, achieved: all),
    members: members.length,
    doneToday: members.where((m) => m.days[todayKey]?.achieved ?? false).length,
  );
}

// ---- TM22: mục tiêu nhóm (club `groupGoal`).
enum GroupGoalPeriod { week, month }

enum GroupGoalMetric { distance, count, time }

class GroupGoal {
  const GroupGoal({required this.period, required this.metric, required this.target, this.weekStart = DateTime.monday});
  final GroupGoalPeriod period;
  final GroupGoalMetric metric;

  /// Đơn vị gốc: m / buổi / ms.
  final double target;

  /// Ngày bắt đầu tuần (DateTime.monday…sunday) do người đặt mục tiêu chọn — mọi thành viên dùng chung.
  final int weekStart;

  Map<String, Object> toMap() => {'period': period.name, 'metric': metric.name, 'target': target, 'weekStart': weekStart};

  static GroupGoal? fromMap(Object? m) {
    if (m is! Map) return null;
    final p = GroupGoalPeriod.values.where((x) => x.name == m['period']).firstOrNull;
    final k = GroupGoalMetric.values.where((x) => x.name == m['metric']).firstOrNull;
    final t = (m['target'] as num?)?.toDouble();
    if (p == null || k == null || t == null || t <= 0) return null;
    return GroupGoal(period: p, metric: k, target: t, weekStart: (m['weekStart'] as num?)?.toInt() ?? DateTime.monday);
  }
}

/// Kỳ hiện tại (ngày địa phương, gồm cả hai đầu) chứa [today].
(DateTime, DateTime) groupGoalRange(GroupGoal g, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  if (g.period == GroupGoalPeriod.month) return (DateTime(t.year, t.month), DateTime(t.year, t.month + 1, 0));
  final back = (t.weekday - g.weekStart + 7) % 7;
  final s = DateTime(t.year, t.month, t.day - back);
  return (s, DateTime(s.year, s.month, s.day + 6));
}

class GroupGoalProgress {
  const GroupGoalProgress({required this.total, required this.byMember});
  final double total;

  /// (userId, tên, đóng góp) — giảm dần, bỏ người chưa đóng góp.
  final List<(String, String, double)> byMember;
}

GroupGoalProgress computeGroupGoalProgress(GroupGoal g, List<MemberStats> members, DateTime today) {
  final (start, end) = groupGoalRange(g, today);
  final keys = <String>{};
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    keys.add(localDateKey(d));
  }
  double value(MemberDay d) => switch (g.metric) {
    GroupGoalMetric.distance => d.distanceM,
    GroupGoalMetric.count => d.activities.toDouble(),
    GroupGoalMetric.time => d.movingMs.toDouble(),
  };
  final rows = <(String, String, double)>[];
  for (final m in members) {
    var v = 0.0;
    for (final e in m.days.entries) {
      if (keys.contains(e.key)) v += value(e.value);
    }
    if (v > 0) rows.add((m.userId, m.displayName, v));
  }
  rows.sort((a, b) => b.$3.compareTo(a.$3));
  return GroupGoalProgress(total: rows.fold(0, (s, r) => s + r.$3), byMember: rows);
}
