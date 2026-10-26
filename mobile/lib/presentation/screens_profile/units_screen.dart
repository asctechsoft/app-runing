import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/profile.dart';
import '../../controller/profile/profile_logic.dart';

/// Pace mẫu dùng để xem trước định dạng (6:12 /km) — chỉ là ví dụ định dạng, không phải dữ liệu người dùng.
const double unitsPacePreviewSecPerKm = 372;

/// Units & language (J03). Đổi đơn vị chỉ đổi hiển thị; dữ liệu đã lưu giữ nguyên.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(settingsProvider)
        .when(
          loading: () => StrideScreen(
            title: 'profile_units_title'.tr,
            body: const Column(children: [Gap(16), LoadingCard(), Gap(12), LoadingCard()]),
          ),
          error: (e, _) => StrideScreen(
            title: 'profile_units_title'.tr,
            body: ErrorState(title: 'profile_settings_load_error_title'.tr, message: 'profile_try_again'.tr, onRetry: () => ref.invalidate(settingsProvider)),
          ),
          data: (s) => _UnitsForm(key: ValueKey(s.ownerId), initial: s),
        );
  }
}

class _UnitsForm extends ConsumerStatefulWidget {
  const _UnitsForm({super.key, required this.initial});
  final UserSettings initial;

  @override
  ConsumerState<_UnitsForm> createState() => _UnitsFormState();
}

class _UnitsFormState extends ConsumerState<_UnitsForm> {
  late DistanceUnit _distance = widget.initial.distanceUnit;
  late WeightUnit _weight = widget.initial.weightUnit;
  late HeightUnit _height = widget.initial.heightUnit;
  late int _weekStart = widget.initial.weekStart;
  bool _saving = false;
  final _guard = OnceGuard();

  Future<void> _save() => _guard.run(() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final latest = await repo.load(widget.initial.ownerId);
      await repo.save(
        applyUnitPreferences(latest, distanceUnit: _distance, weightUnit: _weight, heightUnit: _height, weekStart: _weekStart, localeTag: 'en-US'),
      );
      if (!mounted) return;
      showStrideSnack(context, 'profile_units_saved'.tr);
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) showStrideSnack(context, 'profile_units_save_error'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  Widget _row({required String title, required String subtitle, required Widget control}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StrideCard(
      child: LayoutBuilder(
        builder: (context, c) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: StrideText.subheading),
              Text(subtitle, style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary)),
            ],
          );
          // Màn hẹp/chữ lớn: xếp dọc để không tràn.
          if (c.maxWidth < 380 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const Gap(8), control]);
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 12),
              SizedBox(width: 200, child: control),
            ],
          );
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final preview = StrideFormat(distanceUnit: _distance);
    return StrideScreen(
      title: 'profile_units_title'.tr,
      bottom: PrimaryButton(label: 'profile_units_save'.tr, loading: _saving, onPressed: _saving ? null : _save),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          _row(
            title: 'profile_units_distance'.tr,
            subtitle: 'profile_units_distance_subtitle'.tr,
            control: StrideSegmented<DistanceUnit>(
              values: DistanceUnit.values,
              selected: _distance,
              labelOf: (u) => u == DistanceUnit.km ? 'profile_units_kilometers'.tr : 'profile_units_miles'.tr,
              onChanged: (u) => setState(() => _distance = u),
            ),
          ),
          _row(
            title: 'profile_units_pace'.tr,
            subtitle: 'profile_units_pace_subtitle'.tr,
            control: Semantics(
              label: 'profile_units_pace_preview'.trArgs([preview.pace(unitsPacePreviewSecPerKm)]),
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(StrideRadius.control)),
                child: Column(
                  children: [
                    Text(preview.paceValue(unitsPacePreviewSecPerKm), style: StrideText.metricMedium),
                    Text(_distance == DistanceUnit.km ? 'profile_units_min_km'.tr : 'profile_units_min_mi'.tr, style: StrideText.caption),
                  ],
                ),
              ),
            ),
          ),
          _row(
            title: 'profile_units_weight'.tr,
            subtitle: 'profile_units_calorie_subtitle'.tr,
            control: StrideSegmented<WeightUnit>(
              values: WeightUnit.values,
              selected: _weight,
              labelOf: (u) => u == WeightUnit.kg ? 'profile_units_kilograms'.tr : 'profile_units_pounds'.tr,
              onChanged: (u) => setState(() => _weight = u),
            ),
          ),
          _row(
            title: 'profile_units_height'.tr,
            subtitle: 'profile_units_calorie_subtitle'.tr,
            control: StrideSegmented<HeightUnit>(
              values: HeightUnit.values,
              selected: _height,
              labelOf: (u) => u == HeightUnit.cm ? 'profile_units_centimeters'.tr : 'profile_units_feet_inches'.tr,
              onChanged: (u) => setState(() => _height = u),
            ),
          ),
          _row(
            title: 'profile_units_language'.tr,
            subtitle: 'profile_units_language_subtitle'.tr,
            control: Align(
              alignment: Alignment.centerRight,
              child: Text('profile_units_language_value'.tr, style: StrideText.body),
            ),
          ),
          _row(
            title: 'profile_units_week_starts'.tr,
            subtitle: 'profile_units_week_starts_subtitle'.tr,
            control: DropdownButtonFormField<int>(
              key: const Key('units-week-start'),
              initialValue: _weekStart,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              items: [
                for (final d in const [DateTime.monday, DateTime.sunday, DateTime.saturday]) DropdownMenuItem(value: d, child: Text(weekStartLabel(d))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _weekStart = v);
              },
            ),
          ),
          _row(
            title: 'profile_units_datetime'.tr,
            subtitle: 'profile_units_datetime_subtitle'.tr,
            control: Align(
              alignment: Alignment.centerRight,
              child: Text('profile_units_datetime_value'.tr, style: StrideText.body),
            ),
          ),
          Text('profile_units_footer'.tr, style: StrideText.caption),
        ],
      ),
    );
  }
}
