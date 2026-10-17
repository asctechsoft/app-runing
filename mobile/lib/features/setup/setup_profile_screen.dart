import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/profile.dart';
import '../sync/sync_providers.dart';
import 'setup_logic.dart';
import 'setup_widgets.dart';

/// Bước 1: hồ sơ tối thiểu (E04). Tên bắt buộc; chiều cao/cân nặng tùy chọn — không tự điền giá trị mẫu.
class SetupProfileScreen extends ConsumerStatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  ConsumerState<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _heightCm = TextEditingController();
  final _heightFt = TextEditingController();
  final _heightIn = TextEditingController();
  final _weight = TextEditingController();
  final _guard = OnceGuard();

  UserSettings? _base;
  Object? _loadError;
  DistanceUnit _distance = DistanceUnit.km;
  WeightUnit _weightUnit = WeightUnit.kg;
  HeightUnit _heightUnit = HeightUnit.cm;
  ActivityLevel? _level;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final s = await ref.read(settingsRepositoryProvider).load(ref.read(ownerProvider).ownerId);
      if (!mounted) return;
      _name.text = s.displayName;
      _distance = s.distanceUnit;
      _weightUnit = s.weightUnit;
      _heightUnit = s.heightUnit;
      _level = s.activityLevel;
      final h = s.heightCm;
      if (h != null) {
        _heightCm.text = trimNum(h);
        final (ft, inch) = cmToFtIn(h);
        _heightFt.text = '$ft';
        _heightIn.text = '$inch';
      }
      final w = s.weightKg;
      if (w != null) _weight.text = trimNum(_weightUnit == WeightUnit.lb ? w / kgPerLb : w);
      setState(() => _base = s);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _heightCm, _heightFt, _heightIn, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  ParsedMeasure get _height => _heightUnit == HeightUnit.cm ? parseHeightCm(_heightCm.text) : parseHeightFtIn(_heightFt.text, _heightIn.text);
  ParsedMeasure get _weightParsed => parseWeightKg(_weight.text, pounds: _weightUnit == WeightUnit.lb);

  void _switchWeightUnit(WeightUnit u) {
    if (u == _weightUnit) return;
    // Đổi đơn vị hiển thị, giữ nguyên giá trị đã nhập (quy đổi).
    final kg = _weightParsed.value;
    setState(() {
      _weightUnit = u;
      if (kg != null) _weight.text = trimNum(u == WeightUnit.lb ? kg / kgPerLb : kg);
    });
  }

  void _switchHeightUnit(HeightUnit u) {
    if (u == _heightUnit) return;
    final cm = _height.value;
    setState(() {
      _heightUnit = u;
      if (cm != null) {
        _heightCm.text = trimNum(cm);
        final (ft, inch) = cmToFtIn(cm);
        _heightFt.text = '$ft';
        _heightIn.text = '$inch';
      }
    });
  }

  Future<void> _save({required bool skip}) => _guard.run(() async {
    final base = _base;
    if (base == null) return;
    if (!skip && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final h = _height;
      final w = _weightParsed;
      final next = skip
          // Bỏ qua: giữ mặc định đang hiển thị (km, kg, cm), không lưu số đo.
          ? base.copyWith(displayName: base.displayName)
          : base.copyWith(
              displayName: _name.text.trim(),
              heightCm: h.value,
              clearHeight: h.value == null,
              weightKg: w.value,
              clearWeight: w.value == null,
              distanceUnit: _distance,
              weightUnit: _weightUnit,
              heightUnit: _heightUnit,
              activityLevel: _level,
            );
      final saved = await ref.read(settingsRepositoryProvider).save(next);
      if (!ref.read(ownerProvider).isGuest) await ref.read(syncServiceProvider).enqueueProfile(saved);
      if (mounted) context.push(Routes.setupGoal);
    } catch (e) {
      if (mounted) setState(() => _saveError = "Couldn't save your profile on this device. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return StrideScreen(
      showBack: context.canPop(),
      onBack: () => context.pop(),
      bottom: _base == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(label: 'Continue', trailingIcon: Icons.arrow_forward, loading: _saving, onPressed: () => _save(skip: false)),
                TextButton(onPressed: _saving ? null : () => _save(skip: true), child: const Text('Skip for now')),
              ],
            ),
      body: _loadError != null
          ? ErrorState(title: "Couldn't load your profile", message: 'Something went wrong reading data on this device.', onRetry: _load)
          : _base == null
          ? const Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard(height: 240))
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SetupHeader(step: 0, title: 'Tell us about you', subtitle: 'Only your name is required. Height and weight help estimate calories.'),
                  if (_saveError != null) ...[StatusBanner(tone: BannerTone.error, message: _saveError!), const SizedBox(height: StrideSpace.s12)],
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: validateDisplayName,
                    style: StrideText.body,
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  _LabelRow(
                    label: 'Height (optional)',
                    trailing: StrideSegmented<HeightUnit>(
                      dense: true,
                      values: HeightUnit.values,
                      selected: _heightUnit,
                      labelOf: (u) => u == HeightUnit.cm ? 'cm' : 'ft/in',
                      onChanged: _switchHeightUnit,
                    ),
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  if (_heightUnit == HeightUnit.cm)
                    TextFormField(
                      controller: _heightCm,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: digits,
                      decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm'),
                      validator: (_) => _height.error,
                      style: StrideText.body,
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heightFt,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Feet', suffixText: 'ft'),
                            validator: (_) => _height.error,
                            style: StrideText.body,
                          ),
                        ),
                        const SizedBox(width: StrideSpace.s12),
                        Expanded(
                          child: TextFormField(
                            controller: _heightIn,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Inches', suffixText: 'in'),
                            style: StrideText.body,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: StrideSpace.s24),
                  _LabelRow(
                    label: 'Weight (optional)',
                    trailing: StrideSegmented<WeightUnit>(
                      dense: true,
                      values: WeightUnit.values,
                      selected: _weightUnit,
                      labelOf: (u) => u.name,
                      onChanged: _switchWeightUnit,
                    ),
                  ),
                  const SizedBox(height: StrideSpace.s8),
                  TextFormField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: digits,
                    decoration: InputDecoration(
                      labelText: 'Weight',
                      suffixText: _weightUnit.name,
                      helperText: 'Without weight, calories are not shown.',
                      helperMaxLines: 2,
                    ),
                    validator: (_) => _weightParsed.error,
                    style: StrideText.body,
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  const Text('Distance units', style: StrideText.label),
                  const SizedBox(height: StrideSpace.s8),
                  StrideSegmented<DistanceUnit>(
                    values: DistanceUnit.values,
                    selected: _distance,
                    labelOf: (u) => u == DistanceUnit.km ? 'Kilometers' : 'Miles',
                    onChanged: (u) => setState(() => _distance = u),
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  const Text('How active are you?', style: StrideText.label),
                  const SizedBox(height: StrideSpace.s8),
                  Wrap(
                    spacing: StrideSpace.s8,
                    runSpacing: StrideSpace.s8,
                    children: [
                      for (final l in ActivityLevel.values)
                        StrideChip(label: _levelLabel(l), selected: _level == l, onTap: () => setState(() => _level = _level == l ? null : l)),
                    ],
                  ),
                  const SizedBox(height: StrideSpace.s16),
                  const Text(
                    'Skip for now keeps kilometers, kilograms and centimeters. You can change everything later in Profile.',
                    style: StrideText.caption,
                  ),
                ],
              ),
            ),
    );
  }
}

String _levelLabel(ActivityLevel l) => switch (l) {
  ActivityLevel.newbie => 'Just starting',
  ActivityLevel.occasional => 'Occasionally',
  ActivityLevel.regular => 'Regularly',
  ActivityLevel.active => 'Very active',
};

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.label, required this.trailing});
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: StrideText.label)),
      SizedBox(width: 150, child: trailing),
    ],
  );
}
