import 'package:intl/intl.dart';

import '../models/data_models/profile.dart';

const double metersPerMile = 1609.344;
const double kgPerLb = 0.45359237;

/// Ký tự hiển thị khi thiếu dữ liệu (DS: pace thiếu dữ liệu hiển thị —).
const String missingValue = '—';

/// Định dạng hiển thị theo cài đặt. Dữ liệu gốc luôn là mét / ms / kg.
class StrideFormat {
  const StrideFormat({this.distanceUnit = DistanceUnit.km, this.weightUnit = WeightUnit.kg, this.heightUnit = HeightUnit.cm, this.locale = 'en_US'});

  final DistanceUnit distanceUnit;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final String locale;

  factory StrideFormat.fromSettings(UserSettings s) =>
      StrideFormat(distanceUnit: s.distanceUnit, weightUnit: s.weightUnit, heightUnit: s.heightUnit, locale: s.localeTag.replaceAll('-', '_'));

  String get distanceUnitLabel => distanceUnit == DistanceUnit.km ? 'km' : 'mi';
  String get paceUnitLabel => distanceUnit == DistanceUnit.km ? '/km' : '/mi';

  double metersToUnit(double m) => distanceUnit == DistanceUnit.km ? m / 1000 : m / metersPerMile;
  double unitToMeters(double v) => distanceUnit == DistanceUnit.km ? v * 1000 : v * metersPerMile;

  /// "5.20" (không kèm đơn vị). null → —.
  String distanceValue(double? meters) {
    if (meters == null) return missingValue;
    return NumberFormat('0.00', locale).format(metersToUnit(meters));
  }

  /// "5.20 km".
  String distance(double? meters) => meters == null ? missingValue : '${distanceValue(meters)} $distanceUnitLabel';

  /// Pace từ giây/km → "6:12" theo đơn vị hiển thị. null → —.
  String paceValue(double? secPerKm) {
    if (secPerKm == null || secPerKm.isNaN || secPerKm.isInfinite || secPerKm <= 0) return missingValue;
    final perUnit = distanceUnit == DistanceUnit.km ? secPerKm : secPerKm * metersPerMile / 1000;
    final total = perUnit.round();
    if (total >= 3600) return missingValue; // pace > 60 phút/đv: coi như không có ý nghĩa
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String pace(double? secPerKm) {
    final v = paceValue(secPerKm);
    return v == missingValue ? v : '$v $paceUnitLabel';
  }

  String steps(int? steps) => steps == null ? missingValue : NumberFormat.decimalPattern(locale).format(steps);

  String kcal(double? kcal) => kcal == null ? missingValue : '${NumberFormat('#,##0', locale).format(kcal.round())} kcal';

  String weight(double? kg) {
    if (kg == null) return missingValue;
    return weightUnit == WeightUnit.kg ? '${NumberFormat('0.#', locale).format(kg)} kg' : '${NumberFormat('0.#', locale).format(kg / kgPerLb)} lb';
  }

  String height(double? cm) {
    if (cm == null) return missingValue;
    if (heightUnit == HeightUnit.cm) return '${cm.round()} cm';
    final totalIn = (cm / 2.54).round();
    return '${totalIn ~/ 12}′${totalIn % 12}″';
  }
}

/// Thời lượng "32:14" hoặc "1:24:12" (DS mục 02).
String formatDuration(int? ms) {
  if (ms == null || ms < 0) return missingValue;
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// "1h 55m" cho tổng thời gian dài trong thống kê.
String formatDurationShort(int? ms) {
  if (ms == null) return missingValue;
  final mins = ms ~/ 60000;
  final h = mins ~/ 60;
  final m = mins % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String plural(int n, String one, String other) => Intl.plural(n, one: '$n $one', other: '$n $other');
