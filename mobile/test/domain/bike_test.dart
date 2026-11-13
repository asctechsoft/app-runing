import 'package:flutter_test/flutter_test.dart';
import 'package:stride/models/data_models/activity.dart';
import 'package:stride/utils/calc/calories.dart';
import 'package:stride/utils/calc/group_eligibility.dart';

/// Đạp xe (bike): ghi bằng GPS như chạy ngoài trời nhưng calo theo MET xe đạp và không tính vào chuỗi/nhóm chạy-đi bộ.
void main() {
  Activity bike({double distanceM = 20000, int movingMs = 3600000}) => Activity(
    id: 'b1',
    ownerId: 'u',
    type: ActivityType.bike,
    status: ActivityStatus.saved,
    startedAt: 0,
    tzId: 'UTC',
    tzOffsetMin: 0,
    distanceM: distanceM,
    movingMs: movingMs,
    hasGps: true,
  );

  test('MET xe đạp tăng theo tốc độ và khác MET chạy bộ', () {
    expect(metForSpeed(ActivityType.bike, 15), 4.0);
    expect(metForSpeed(ActivityType.bike, 20), 8.0);
    expect(metForSpeed(ActivityType.bike, 32), 15.8);
    expect(metForSpeed(ActivityType.bike, 20), isNot(metForSpeed(ActivityType.run, 20)));
  });

  test('calo xe đạp 20 km/h trong 1 giờ, 70 kg = 8.0 × 70 × 1', () {
    expect(estimateCalories(type: ActivityType.bike, weightKg: 70, movingMs: 3600000, distanceM: 20000), closeTo(560, 0.001));
  });

  test('thiếu cân nặng → không ước tính calo (không dùng cân nặng mẫu)', () {
    expect(estimateCalories(type: ActivityType.bike, weightKg: null, movingMs: 3600000, distanceM: 20000), isNull);
  });

  test('đạp xe không tính vào chuỗi/nhóm/thử thách chạy-đi bộ', () {
    expect(streakIneligibility(bike()), IneligibleReason.cycling);
    expect(isStreakEligible(bike()), isFalse);
    expect(isGroupEligible(bike()), isFalse);
  });

  test('type bike lưu và đọc lại đúng; giá trị lạ lùi về run', () {
    final row = bike().toRow();
    expect(row['type'], 'bike');
    expect(Activity.fromRow(row).type, ActivityType.bike);
    expect(Activity.fromRow({...row, 'type': 'swim'}).type, ActivityType.run);
  });
}
