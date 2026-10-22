import '../../utils/l10n.dart';

/// Quy tắc nhập hồ sơ (E04) — khoảng hợp lệ của chiều cao/cân nặng/mục tiêu.
abstract final class ProfileLimits {
  static const minHeightCm = 50.0;
  static const maxHeightCm = 272.0;
  static const minWeightKg = 20.0;
  static const maxWeightKg = 400.0;
  static const maxNameLength = 60;
}

const kgPerLb = 0.45359237;
const cmPerInch = 2.54;

String? validateDisplayName(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'setup_err_name_empty'.tr;
  if (s.length > ProfileLimits.maxNameLength) return 'setup_err_name_long'.trArgs([ProfileLimits.maxNameLength]);
  return null;
}

double? _parse(String? s) {
  final t = s?.trim().replaceAll(',', '.') ?? '';
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Kết quả parse trường số: `value` null + `error` null nghĩa là bỏ trống (hợp lệ, trường optional).
class ParsedMeasure {
  const ParsedMeasure(this.value, [this.error]);
  final double? value;
  final String? error;
}

ParsedMeasure parseHeightCm(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return const ParsedMeasure(null);
  final v = _parse(t);
  if (v == null) return ParsedMeasure(null, 'setup_err_number'.tr);
  if (v < ProfileLimits.minHeightCm || v > ProfileLimits.maxHeightCm) return ParsedMeasure(null, 'setup_err_height_range'.tr);
  return ParsedMeasure(v);
}

ParsedMeasure parseHeightFtIn(String? ft, String? inch) {
  final f = ft?.trim() ?? '';
  final i = inch?.trim() ?? '';
  if (f.isEmpty && i.isEmpty) return const ParsedMeasure(null);
  final fv = f.isEmpty ? 0.0 : _parse(f);
  final iv = i.isEmpty ? 0.0 : _parse(i);
  if (fv == null || iv == null || fv < 0 || iv < 0 || iv >= 12) return ParsedMeasure(null, 'setup_err_height_ftin'.tr);
  final cm = (fv * 12 + iv) * cmPerInch;
  if (cm < ProfileLimits.minHeightCm || cm > ProfileLimits.maxHeightCm) return ParsedMeasure(null, 'setup_err_height_ftin_range'.tr);
  return ParsedMeasure(cm);
}

ParsedMeasure parseWeightKg(String? text, {required bool pounds}) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return const ParsedMeasure(null);
  final v = _parse(t);
  if (v == null) return ParsedMeasure(null, 'setup_err_number'.tr);
  final kg = pounds ? v * kgPerLb : v;
  if (kg < ProfileLimits.minWeightKg || kg > ProfileLimits.maxWeightKg) {
    return ParsedMeasure(null, pounds ? 'setup_err_weight_lb'.tr : 'setup_err_weight_kg'.tr);
  }
  return ParsedMeasure(kg);
}

/// cm → (ft, in) để hiển thị lại giá trị đã lưu.
(int, int) cmToFtIn(double cm) {
  final totalIn = (cm / cmPerInch).round();
  return (totalIn ~/ 12, totalIn % 12);
}

String trimNum(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Mục tiêu bước (F03/F06).
abstract final class StepGoalLimits {
  static const min = 1000;
  static const max = 100000;
  static const step = 500;
  static const defaultValue = 8000;
  static const presets = [4000, 6000, 8000, 10000];
}
