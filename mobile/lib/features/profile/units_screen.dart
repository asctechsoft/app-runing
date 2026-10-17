import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/profile.dart';
import 'profile_logic.dart';

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
          loading: () => const StrideScreen(
            title: 'Units & language',
            body: Column(children: [Gap(16), LoadingCard(), Gap(12), LoadingCard()]),
          ),
          error: (e, _) => StrideScreen(
            title: 'Units & language',
            body: ErrorState(title: 'Couldn’t load settings', message: 'Try again.', onRetry: () => ref.invalidate(settingsProvider)),
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
      showStrideSnack(context, 'Units saved');
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) showStrideSnack(context, 'Couldn’t save units. Try again.', isError: true);
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
      title: 'Units & language',
      bottom: PrimaryButton(label: 'Save', loading: _saving, onPressed: _saving ? null : _save),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          _row(
            title: 'Distance',
            subtitle: 'Used for distance in your runs and stats.',
            control: StrideSegmented<DistanceUnit>(
              values: DistanceUnit.values,
              selected: _distance,
              labelOf: (u) => u == DistanceUnit.km ? 'Kilometers' : 'Miles',
              onChanged: (u) => setState(() => _distance = u),
            ),
          ),
          _row(
            title: 'Pace',
            subtitle: 'Preview of how pace will be displayed.',
            control: Semantics(
              label: 'Pace preview ${preview.pace(unitsPacePreviewSecPerKm)}',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: StrideColors.subtle, borderRadius: BorderRadius.circular(StrideRadius.control)),
                child: Column(
                  children: [
                    Text(preview.paceValue(unitsPacePreviewSecPerKm), style: StrideText.metricMedium),
                    Text(_distance == DistanceUnit.km ? 'min/km' : 'min/mi', style: StrideText.caption),
                  ],
                ),
              ),
            ),
          ),
          _row(
            title: 'Weight',
            subtitle: 'Used for more accurate calorie estimates.',
            control: StrideSegmented<WeightUnit>(
              values: WeightUnit.values,
              selected: _weight,
              labelOf: (u) => u == WeightUnit.kg ? 'Kilograms' : 'Pounds',
              onChanged: (u) => setState(() => _weight = u),
            ),
          ),
          _row(
            title: 'Height',
            subtitle: 'Used for more accurate calorie estimates.',
            control: StrideSegmented<HeightUnit>(
              values: HeightUnit.values,
              selected: _height,
              labelOf: (u) => u == HeightUnit.cm ? 'Centimeters' : 'Feet & inches',
              onChanged: (u) => setState(() => _height = u),
            ),
          ),
          _row(
            title: 'Language',
            subtitle: 'More languages are coming later.',
            control: const Align(
              alignment: Alignment.centerRight,
              child: Text('English (US)', style: StrideText.body),
            ),
          ),
          _row(
            title: 'Week starts',
            subtitle: 'Select which day your week begins on.',
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
            title: 'Date & time',
            subtitle: 'Uses your device settings for date, time and time zone.',
            control: const Align(
              alignment: Alignment.centerRight,
              child: Text('Use device settings', style: StrideText.body),
            ),
          ),
          Text('Changing units only changes how values are shown. Your saved activities stay the same.', style: StrideText.caption),
        ],
      ),
    );
  }
}
