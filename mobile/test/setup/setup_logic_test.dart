import 'package:flutter_test/flutter_test.dart';
import 'package:stride/features/setup/setup_logic.dart';

void main() {
  group('Hồ sơ (E04)', () {
    test('tên bắt buộc, tối đa 60 ký tự', () {
      expect(validateDisplayName('  '), isNotNull);
      expect(validateDisplayName('Lan'), isNull);
      expect(validateDisplayName('x' * 61), isNotNull);
    });

    test('chiều cao/cân nặng bỏ trống là hợp lệ (optional), không tự điền', () {
      expect(parseHeightCm('').value, isNull);
      expect(parseHeightCm('').error, isNull);
      expect(parseWeightKg('', pounds: false).value, isNull);
      expect(parseWeightKg('', pounds: false).error, isNull);
    });

    test('ngoài khoảng hợp lệ báo lỗi tại trường', () {
      expect(parseHeightCm('20').error, isNotNull);
      expect(parseHeightCm('300').error, isNotNull);
      expect(parseWeightKg('10', pounds: false).error, isNotNull);
      expect(parseWeightKg('abc', pounds: false).error, isNotNull);
    });

    test('quy đổi lb → kg và ft/in → cm, lưu đơn vị gốc', () {
      expect(parseWeightKg('154', pounds: true).value, closeTo(69.85, 0.01));
      expect(parseHeightFtIn('5', '10').value, closeTo(177.8, 0.01));
      expect(parseHeightFtIn('5', '12').error, isNotNull);
      expect(parseHeightCm('172,5').value, 172.5);
      expect(cmToFtIn(177.8), (5, 10));
    });

    test('mục tiêu bước mặc định và preset', () {
      expect(StepGoalLimits.presets, [4000, 6000, 8000, 10000]);
      expect(StepGoalLimits.defaultValue, 8000);
    });
  });
}
