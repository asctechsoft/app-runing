import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/models/data_models/steps.dart';
import 'package:stride/utils/calc/group_eligibility.dart';
import 'package:stride/utils/calc/streak.dart';

Activity _act({
  ActivityType type = ActivityType.run,
  double? distanceM = 3000,
  int movingMs = 18 * 60 * 1000,
  bool hasGps = true,
  bool mocked = false,
  Privacy privacy = Privacy.followers,
  ActivityStatus status = ActivityStatus.saved,
  int? deletedAt,
  int startedAt = 0,
  int tzOffsetMin = 0,
}) => Activity(
  id: 'a$startedAt',
  ownerId: 'o',
  type: type,
  status: status,
  startedAt: startedAt,
  tzId: 'UTC',
  tzOffsetMin: tzOffsetMin,
  distanceM: distanceM,
  movingMs: movingMs,
  hasGps: hasGps,
  distanceSource: type == ActivityType.indoorRun ? DistanceSource.steps : DistanceSource.gps,
  locationMocked: mocked,
  privacy: privacy,
  deletedAt: deletedAt,
);

/// Tập ngày đạt từ chuỗi 'x' (đạt) / '.' (không đạt), kết thúc ở [end].
Set<String> _days(String pattern, DateTime end) {
  final out = <String>{};
  for (var i = 0; i < pattern.length; i++) {
    final d = DateTime(end.year, end.month, end.day - (pattern.length - 1 - i));
    if (pattern[i] == 'x') out.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }
  return out;
}

void main() {
  group('TM24: hoạt động hợp lệ', () {
    test('run/walk có GPS, ≥ 1 km hoặc ≥ 10 phút', () {
      expect(isStreakEligible(_act()), isTrue);
      expect(isStreakEligible(_act(type: ActivityType.walk, distanceM: 1200, movingMs: 12 * 60000)), isTrue);
      expect(isStreakEligible(_act(distanceM: 900, movingMs: 11 * 60000)), isTrue, reason: 'đủ 10 phút');
      expect(streakIneligibility(_act(distanceM: 800, movingMs: 5 * 60000)), IneligibleReason.tooShort);
    });

    test('indoor, không GPS, vị trí giả, chưa lưu/đã xóa → không tính', () {
      expect(streakIneligibility(_act(type: ActivityType.indoorRun)), IneligibleReason.indoor);
      expect(streakIneligibility(_act(hasGps: false)), IneligibleReason.noGps);
      expect(streakIneligibility(_act(mocked: true)), IneligibleReason.mockedLocation);
      expect(streakIneligibility(_act(status: ActivityStatus.awaitingSave)), IneligibleReason.notSaved);
      expect(streakIneligibility(_act(deletedAt: 5)), IneligibleReason.notSaved);
    });

    test('tốc độ bất thường (đi xe) → không tính', () {
      // 10 km trong 20 phút = 2:00/km — nhanh hơn ngưỡng run 2:30/km.
      expect(streakIneligibility(_act(distanceM: 10000, movingMs: 20 * 60000)), IneligibleReason.implausibleSpeed);
      // walk 3 km trong 15 phút = 5:00/km — nhanh hơn ngưỡng walk 6:00/km.
      expect(streakIneligibility(_act(type: ActivityType.walk, distanceM: 3000, movingMs: 15 * 60000)), IneligibleReason.implausibleSpeed);
      // run 3:00/km vẫn hợp lệ.
      expect(isStreakEligible(_act(distanceM: 5000, movingMs: 15 * 60000)), isTrue);
    });

    test('riêng tư: tính cho chuỗi cá nhân nhưng không đóng góp cho nhóm', () {
      final a = _act(privacy: Privacy.onlyMe);
      expect(isStreakEligible(a), isTrue);
      expect(groupIneligibility(a), IneligibleReason.private);
      expect(isGroupEligible(_act(privacy: Privacy.public)), isTrue);
    });
  });

  group('TM20: ngày đạt', () {
    final goals = [const GoalVersion(id: 'g', ownerId: 'o', type: GoalType.dailySteps, value: 8000, effectiveFrom: '2026-01-01', createdAt: 1)];

    test('đạt bước HOẶC có buổi hợp lệ; thiếu dữ liệu không thành 0', () {
      final keys = achievedDayKeys(
        days: const [
          StepDay(date: '2026-10-20', status: StepDayStatus.populated, steps: 9000),
          StepDay(date: '2026-10-21', status: StepDayStatus.populated, steps: 4000),
          StepDay(date: '2026-10-22', status: StepDayStatus.noData),
        ],
        goals: goals,
        activities: [_act(startedAt: DateTime.utc(2026, 10, 22, 7).millisecondsSinceEpoch)],
      );
      expect(keys, {'2026-10-20', '2026-10-22'});
    });

    test('hoạt động tính theo ngày địa phương của chính nó (qua nửa đêm UTC)', () {
      // 23:30 UTC ngày 21 = 06:30 ngày 22 ở UTC+7.
      final a = _act(startedAt: DateTime.utc(2026, 10, 21, 23, 30).millisecondsSinceEpoch, tzOffsetMin: 420);
      expect(achievedDayKeys(days: const [], goals: goals, activities: [a]), {'2026-10-22'});
    });

    test('đổi mục tiêu giữa chừng: ngày cũ dùng mục tiêu cũ', () {
      final g2 = [...goals, const GoalVersion(id: 'g2', ownerId: 'o', type: GoalType.dailySteps, value: 12000, effectiveFrom: '2026-10-21', createdAt: 2)];
      final keys = achievedDayKeys(
        days: const [
          StepDay(date: '2026-10-20', status: StepDayStatus.populated, steps: 9000),
          StepDay(date: '2026-10-21', status: StepDayStatus.populated, steps: 9000),
        ],
        goals: g2,
        activities: const [],
      );
      expect(keys, {'2026-10-20'});
    });

    test('hoạt động bị xóa → ngày đó không còn đạt', () {
      final a = _act(startedAt: DateTime.utc(2026, 10, 22, 7).millisecondsSinceEpoch, deletedAt: 9);
      expect(achievedDayKeys(days: const [], goals: goals, activities: [a]), isEmpty);
    });
  });

  group('TM20: chuỗi', () {
    final today = DateTime(2026, 10, 27, 9);

    test('không có dữ liệu → 0', () {
      final s = computeStreak(today: today, achieved: const {});
      expect(s.current, 0);
      expect(s.longest, 0);
      expect(s.freezesLeftThisMonth, 2);
    });

    test('hôm nay chưa đạt không làm mất chuỗi', () {
      final s = computeStreak(today: today, achieved: _days('xxxxx.', today));
      expect(s.current, 5);
      expect(s.todayAchieved, isFalse);
      expect(s.atRisk, isTrue);
      expect(s.freezesLeftThisMonth, 2);
    });

    test('hôm nay đạt → cộng vào chuỗi', () {
      final s = computeStreak(today: today, achieved: _days('xxxxxx', today));
      expect(s.current, 6);
      expect(s.atRisk, isFalse);
    });

    test('một ngày lỡ được bảo lưu, không cộng ngày', () {
      final s = computeStreak(today: today, achieved: _days('xxx.xx', today));
      expect(s.current, 5);
      expect(s.longest, 5);
      expect(s.freezesLeftThisMonth, 1);
      expect(s.frozenDays, {'2026-10-25'});
    });

    test('hết lượt bảo lưu trong tháng → đứt chuỗi', () {
      final s = computeStreak(today: today, achieved: _days('xx.x.x.xx', today));
      // 3 ngày lỡ trong tháng 10, chỉ 2 lượt → đứt ở ngày lỡ thứ 3; chuỗi mới = 2.
      expect(s.current, 2);
      expect(s.longest, 4);
    });

    test('lượt không bị trừ khi chuỗi đứt luôn', () {
      // 3 ngày lỡ liên tiếp: 2 lượt chờ rồi đứt → không trừ lượt nào; chuỗi mới vẫn còn đủ 2 lượt.
      final s = computeStreak(today: today, achieved: _days('xxx...xx', today));
      expect(s.current, 2);
      expect(s.longest, 3);
      expect(s.freezesLeftThisMonth, 2);
    });

    test('lượt bảo lưu tính theo tháng của ngày lỡ', () {
      final t = DateTime(2026, 11, 3);
      // 29/10 và 31/10 lỡ (tháng 10), 2/11 lỡ (tháng 11) → đều được bảo lưu.
      final s = computeStreak(today: t, achieved: _days('xx.x.x.x', t));
      expect(s.current, 5);
      expect(s.freezesLeftThisMonth, 1);
    });

    test('tắt bảo lưu', () {
      expect(computeStreak(today: today, achieved: _days('xxx.xx', today), freezesPerMonth: 0).current, 2);
    });

    test('qua chuyển giờ mùa hè (DST) không nhảy ngày', () {
      // Chuỗi đi qua 29/3 và 25/10 (các ngày DST phổ biến) — lịch theo ngày, không theo 24h.
      final t = DateTime(2026, 3, 31);
      expect(computeStreak(today: t, achieved: _days('xxxxxxx', t)).current, 7);
      expect(computeStreak(today: today, achieved: _days('xxxxxxxxx', today)).current, 9);
    });
  });
}
