import 'package:flutter_test/flutter_test.dart';
import 'package:stride/services/native/permission_coordinator.dart';
import 'package:stride/models/data_models/profile.dart';
import 'package:stride/models/data_models/steps.dart';
import 'package:stride/controller/home/home_logic.dart';
import 'package:stride/services/application/step_tracking_service.dart';

StepDay _day(String date, StepDayStatus status, [int? steps]) =>
    StepDay(date: date, status: status, steps: steps, hourly: steps == null ? null : List.filled(24, 0));

GoalVersion _goal(String from, double v, {int createdAt = 0}) =>
    GoalVersion(id: '$from-$v', ownerId: 'o', type: GoalType.dailySteps, value: v, effectiveFrom: from, createdAt: createdAt);

void main() {
  group('decideHomeStepState (DS §06)', () {
    test('chưa cấp quyền và không có dữ liệu → noPermission (không phải 0)', () {
      expect(decideHomeStepState(permission: PermStatus.denied, day: _day('2026-10-18', StepDayStatus.noPermission), goal: 8000), HomeStepState.noPermission);
      expect(decideHomeStepState(permission: PermStatus.unknown, day: _day('2026-10-18', StepDayStatus.noData), goal: 8000), HomeStepState.noPermission);
    });

    test('có quyền nhưng chưa có mẫu → noData', () {
      expect(decideHomeStepState(permission: PermStatus.granted, day: _day('2026-10-18', StepDayStatus.noData), goal: 8000), HomeStepState.noData);
    });

    test('có quyền, không cảm biến → unavailable', () {
      expect(
        decideHomeStepState(
          permission: PermStatus.granted,
          day: _day('2026-10-18', StepDayStatus.noData),
          goal: 8000,
          tracking: StepTrackingStatus.unavailable,
        ),
        HomeStepState.unavailable,
      );
    });

    test('0 thật → verifiedZero', () {
      expect(
        decideHomeStepState(permission: PermStatus.granted, day: _day('2026-10-18', StepDayStatus.verifiedZero, 0), goal: 8000),
        HomeStepState.verifiedZero,
      );
    });

    test('có dữ liệu chưa đạt → populated; đạt và vượt → achieved', () {
      expect(decideHomeStepState(permission: PermStatus.granted, day: _day('d', StepDayStatus.populated, 4200), goal: 8000), HomeStepState.populated);
      expect(decideHomeStepState(permission: PermStatus.granted, day: _day('d', StepDayStatus.populated, 8000), goal: 8000), HomeStepState.achieved);
      expect(decideHomeStepState(permission: PermStatus.granted, day: _day('d', StepDayStatus.populated, 12000), goal: 8000), HomeStepState.achieved);
    });

    test('không có mục tiêu thì không bao giờ achieved', () {
      expect(decideHomeStepState(permission: PermStatus.granted, day: _day('d', StepDayStatus.populated, 12000), goal: null), HomeStepState.populated);
    });

    test('quyền bị thu hồi nhưng đã có dữ liệu hôm nay → vẫn hiển thị số thật', () {
      expect(decideHomeStepState(permission: PermStatus.denied, day: _day('d', StepDayStatus.populated, 3000), goal: 8000), HomeStepState.populated);
    });
  });

  group('computeWeekStreak', () {
    // Thứ Năm 2026-10-15, tuần bắt đầu thứ Hai 2026-10-12.
    final today = DateTime(2026, 10, 15, 9);

    test('ngày thiếu dữ liệu không được tính là đạt', () {
      final w = computeWeekStreak(
        today: today,
        weekStart: DateTime.monday,
        goals: [_goal('2026-01-01', 8000)],
        days: {
          '2026-10-12': _day('2026-10-12', StepDayStatus.populated, 9000),
          // 13: không có bản ghi
          '2026-10-14': _day('2026-10-14', StepDayStatus.noData),
          '2026-10-15': _day('2026-10-15', StepDayStatus.populated, 7999),
        },
      );
      expect(w.days.map((d) => d.status).toList(), [
        StreakDayStatus.achieved,
        StreakDayStatus.noData,
        StreakDayStatus.noData,
        StreakDayStatus.missed,
        StreakDayStatus.future,
        StreakDayStatus.future,
        StreakDayStatus.future,
      ]);
      expect(w.achievedCount, 1);
    });

    test('mỗi ngày dùng mục tiêu có hiệu lực của chính ngày đó', () {
      final w = computeWeekStreak(
        today: today,
        weekStart: DateTime.monday,
        goals: [_goal('2026-01-01', 5000), _goal('2026-10-14', 10000)],
        days: {
          '2026-10-13': _day('2026-10-13', StepDayStatus.populated, 6000), // goal 5000 → đạt
          '2026-10-14': _day('2026-10-14', StepDayStatus.populated, 6000), // goal 10000 → chưa
        },
      );
      expect(w.days[1].status, StreakDayStatus.achieved);
      expect(w.days[2].status, StreakDayStatus.missed);
    });

    test('weekStart = Chủ nhật đổi ngày đầu tuần', () {
      final w = computeWeekStreak(today: today, weekStart: DateTime.sunday, goals: const [], days: const {});
      expect(w.days.first.date, DateTime(2026, 10, 11));
      expect(w.days.where((d) => d.status == StreakDayStatus.future).length, 2);
    });

    test('không có mục tiêu → ngày có bước vẫn không đạt', () {
      final w = computeWeekStreak(
        today: today,
        weekStart: DateTime.monday,
        goals: const [],
        days: {'2026-10-12': _day('2026-10-12', StepDayStatus.populated, 20000)},
      );
      expect(w.achievedCount, 0);
    });
  });

  test('greetingFor: không có tên → chỉ lời chào', () {
    expect(greetingFor(DateTime(2026, 10, 18, 8), ''), 'Good morning');
    expect(greetingFor(DateTime(2026, 10, 18, 8), null), 'Good morning');
    expect(greetingFor(DateTime(2026, 10, 18, 14), 'Alex Morgan'), 'Good afternoon, Alex');
    expect(greetingFor(DateTime(2026, 10, 18, 20), 'Alex'), 'Good evening, Alex');
  });
}
