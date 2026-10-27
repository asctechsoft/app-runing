import 'package:flutter_test/flutter_test.dart';
import 'package:stride/controller/explore/explore_logic.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/ui_models/explore_models.dart';
import 'package:stride/utils/calc/badges.dart';
import 'package:stride/utils/calc/group_eligibility.dart';
import 'package:stride/utils/calc/group_stats.dart';

const _min = 60 * 1000;

Activity _a(String id, int startMin, int durMin, double m, {int? endedMin}) => Activity(
  id: id,
  ownerId: 'u',
  type: ActivityType.run,
  status: ActivityStatus.saved,
  startedAt: DateTime(2026, 10, 20, 7).millisecondsSinceEpoch + startMin * _min,
  endedAt: endedMin == null ? null : DateTime(2026, 10, 20, 7).millisecondsSinceEpoch + endedMin * _min,
  tzId: 'UTC',
  tzOffsetMin: DateTime(2026, 10, 20).timeZoneOffset.inMinutes,
  distanceM: m,
  movingMs: durMin * _min,
  elapsedMs: durMin * _min,
  avgPaceSecPerKm: 360,
  hasGps: true,
  distanceSource: DistanceSource.gps,
  privacy: Privacy.public,
);

/// TM62: chống gian lận — hoạt động chồng thời gian (ghi đôi / hai máy / nhập lại) chỉ tính một lần.
void main() {
  test('chồng thời gian → giữ buổi dài hơn; nối tiếp (không chồng) → giữ cả hai', () {
    final kept = dropOverlapping([
      _a('phone', 0, 40, 6000),
      _a('watch', 2, 38, 6500), // cùng buổi, ghi từ thiết bị khác
      _a('later', 40, 30, 5000), // bắt đầu đúng lúc buổi đầu kết thúc → không chồng
      _a('copy', 41, 20, 5000, endedMin: 61),
    ]);
    expect(kept.map((a) => a.id), ['watch', 'later']);
  });

  test('bằng quãng đường → buổi bắt đầu sớm hơn', () {
    expect(dropOverlapping([_a('b', 5, 30, 5000), _a('a', 0, 30, 5000)]).map((a) => a.id), ['a']);
  });

  test('áp dụng cho tiến độ thử thách, số liệu nhóm và huy hiệu quãng đường', () {
    final acts = [_a('phone', 0, 40, 6000), _a('watch', 2, 38, 6500)];
    final from = DateTime(2026, 10, 1).millisecondsSinceEpoch;
    final to = DateTime(2026, 11, 1).millisecondsSinceEpoch;
    expect(computeChallengeProgress(acts, metric: ChallengeTarget.distance, activityTypes: const ['run'], fromMs: from, toMs: to), 6500);
    expect(computeChallengeProgress(acts, metric: ChallengeTarget.count, activityTypes: const ['run'], fromMs: from, toMs: to), 1);
    final days = buildMemberDays(today: DateTime(2026, 10, 20, 20), achieved: const {}, activities: acts);
    expect((days['2026-10-20']!.distanceM, days['2026-10-20']!.activities), (6500.0, 1));
    final twice = [for (var i = 0; i < 20; i++) _a('x$i', 0, 40, 6000)];
    expect(evaluateBadges(activities: twice, longestStreak: 0).map((b) => b.id), ['first5k']); // không cộng thành 100 km
  });
}
