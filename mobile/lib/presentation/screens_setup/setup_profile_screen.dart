import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/profile.dart';
import '../../controller/sync/sync_providers.dart';
import '../../controller/setup/setup_logic.dart';
import 'components/setup_widgets.dart';
import '../../utils/l10n.dart';

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
      if (mounted) setState(() => _saveError = 'setup_profile_save_error'.tr);
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
                PrimaryButton(label: 'setup_continue'.tr, trailingIcon: Icons.arrow_forward, loading: _saving, onPressed: () => _save(skip: false)),
                TextButton(onPressed: _saving ? null : () => _save(skip: true), child: Text('setup_skip_for_now'.tr)),
              ],
            ),
      body: _loadError != null
          ? ErrorState(title: 'setup_profile_load_error_title'.tr, message: 'setup_profile_load_error_msg'.tr, onRetry: _load)
          : _base == null
          ? const Padding(padding: EdgeInsets.only(top: 48), child: LoadingCard(height: 240))
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SetupHeader(step: 0, title: 'setup_profile_title'.tr, subtitle: 'setup_profile_subtitle'.tr),
                  if (_saveError != null) ...[StatusBanner(tone: BannerTone.error, message: _saveError!), const SizedBox(height: StrideSpace.s12)],
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(labelText: 'setup_profile_name'.tr, prefixIcon: Icon(Icons.person_outline)),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: validateDisplayName,
                    style: StrideText.body,
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  _LabelRow(
                    label: 'setup_profile_height_optional'.tr,
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
                      decoration: InputDecoration(labelText: 'setup_profile_height'.tr, suffixText: 'cm'),
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
                            decoration: InputDecoration(labelText: 'setup_profile_feet'.tr, suffixText: 'ft'),
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
                            decoration: InputDecoration(labelText: 'setup_profile_inches'.tr, suffixText: 'in'),
                            style: StrideText.body,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: StrideSpace.s24),
                  _LabelRow(
                    label: 'setup_profile_weight_optional'.tr,
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
                      labelText: 'setup_profile_weight'.tr,
                      suffixText: _weightUnit.name,
                      helperText: 'setup_profile_weight_helper'.tr,
                      helperMaxLines: 2,
                    ),
                    validator: (_) => _weightParsed.error,
                    style: StrideText.body,
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  Text('setup_profile_distance_units'.tr, style: StrideText.label),
                  const SizedBox(height: StrideSpace.s8),
                  StrideSegmented<DistanceUnit>(
                    values: DistanceUnit.values,
                    selected: _distance,
                    labelOf: (u) => u == DistanceUnit.km ? 'setup_profile_kilometers'.tr : 'setup_profile_miles'.tr,
                    onChanged: (u) => setState(() => _distance = u),
                  ),
                  const SizedBox(height: StrideSpace.s24),
                  Text('setup_profile_activity_question'.tr, style: StrideText.label),
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
                  Text('setup_profile_skip_note'.tr, style: StrideText.caption),
                ],
              ),
            ),
    );
  }
}

String _levelLabel(ActivityLevel l) => switch (l) {
  ActivityLevel.newbie => 'setup_profile_level_newbie'.tr,
  ActivityLevel.occasional => 'setup_profile_level_occasional'.tr,
  ActivityLevel.regular => 'setup_profile_level_regular'.tr,
  ActivityLevel.active => 'setup_profile_level_active'.tr,
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
