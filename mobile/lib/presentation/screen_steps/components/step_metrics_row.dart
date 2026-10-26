import 'package:flutter/material.dart';

import '../../../utils/formatters.dart';
import '../../../utils/l10n.dart';
import '../../../values/tokens.dart';
import '../../common_components/widgets.dart';
import '../../../utils/calc/calories.dart';
import '../../../models/data_models/profile.dart';

/// Ba chỉ số phụ dưới vòng bước: quãng đường ước tính, kcal ước tính, phút vận động.
/// Thiếu chiều cao/cân nặng hoặc không có bước → "—" (không đoán sải chân, không cân nặng mẫu).
class StepMetricsRow extends StatelessWidget {
  const StepMetricsRow({super.key, required this.steps, required this.settings, required this.format, required this.activeMinutes, this.onAddProfile});

  final int? steps;
  final UserSettings? settings;
  final StrideFormat format;
  final int? activeMinutes;

  /// Mở Edit profile khi thiếu chiều cao/cân nặng.
  final VoidCallback? onAddProfile;

  @override
  Widget build(BuildContext context) {
    final s = steps;
    final distM = s == null ? null : stepDistanceM(steps: s, heightCm: settings?.heightCm);
    final kcal = s == null ? null : estimateStepCalories(steps: s, weightKg: settings?.weightKg, heightCm: settings?.heightCm);
    final missingHeight = settings?.heightCm == null;
    final missingWeight = settings?.weightKg == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.place_outlined,
                label: 'steps_metric_distance'.tr,
                value: distM == null ? missingValue : format.distanceValue(distM),
                unit: distM == null ? null : format.distanceUnitLabel,
                estimated: true,
                center: true,
              ),
            ),
            Expanded(
              child: MetricTile(
                icon: Icons.local_fire_department_outlined,
                label: 'steps_metric_calories'.tr,
                value: kcal == null ? missingValue : format.kcal(kcal).replaceAll(' kcal', ''),
                unit: kcal == null ? null : 'steps_unit_kcal'.tr,
                estimated: true,
                center: true,
              ),
            ),
            Expanded(
              child: MetricTile(
                icon: Icons.bolt_outlined,
                label: 'steps_metric_active_min'.tr,
                value: activeMinutes == null ? missingValue : '$activeMinutes',
                unit: activeMinutes == null ? null : 'steps_unit_min'.tr,
                center: true,
              ),
            ),
          ],
        ),
        if (s != null && (missingHeight || missingWeight)) ...[
          const SizedBox(height: StrideSpace.s8),
          Semantics(
            button: onAddProfile != null,
            child: InkWell(
              onTap: onAddProfile,
              borderRadius: BorderRadius.circular(StrideRadius.small),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: StrideSpace.touchTarget),
                child: Center(
                  child: Text(
                    missingHeight ? 'steps_add_height'.tr : 'steps_add_weight'.tr,
                    style: StrideText.label.copyWith(color: StrideColors.primary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
