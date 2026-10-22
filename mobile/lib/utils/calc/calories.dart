import '../../models/data_models/activity.dart';

const calorieModelId = 'met-v1';

/// MET theo tốc độ (Compendium of Physical Activities, xấp xỉ). Cần Product duyệt (docs/scope.md).
double metForSpeed(ActivityType type, double speedKmh) {
  if (type == ActivityType.walk) {
    if (speedKmh < 3.2) return 2.0;
    if (speedKmh < 4.8) return 3.0;
    if (speedKmh < 5.6) return 3.5;
    if (speedKmh < 6.4) return 4.3;
    return 5.0;
  }
  if (speedKmh < 6.4) return 6.0;
  if (speedKmh < 8.0) return 8.3;
  if (speedKmh < 9.7) return 9.8;
  if (speedKmh < 11.3) return 11.0;
  if (speedKmh < 12.9) return 11.8;
  if (speedKmh < 14.5) return 12.8;
  return 14.5;
}

/// Calo ước tính. Trả null khi thiếu cân nặng hoặc dữ liệu — không dùng cân nặng mẫu (E04).
double? estimateCalories({required ActivityType type, required double? weightKg, required int movingMs, required double? distanceM}) {
  if (weightKg == null || weightKg <= 0 || movingMs <= 0 || distanceM == null || distanceM <= 0) return null;
  final hours = movingMs / 3600000;
  final speedKmh = (distanceM / 1000) / hours;
  return metForSpeed(type, speedKmh) * weightKg * hours;
}

/// Calo ước tính từ bước hằng ngày (Home). Cần cân nặng và chiều cao; thiếu → null.
double? estimateStepCalories({required int steps, required double? weightKg, required double? heightCm}) {
  final d = stepDistanceM(steps: steps, heightCm: heightCm);
  if (d == null || weightKg == null) return null;
  // ~0.5 kcal / kg / km khi đi bộ.
  return 0.5 * weightKg * (d / 1000);
}

/// Quãng đường ước tính từ bước. Không có chiều cao → null (không đoán sải chân).
double? stepDistanceM({required int steps, required double? heightCm}) {
  if (heightCm == null || heightCm <= 0) return null;
  return steps * heightCm * 0.415 / 100;
}
