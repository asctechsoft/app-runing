import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/auth/auth_flow.dart';
import '../../controller/providers.dart';
import '../../controller/setup/setup_logic.dart';
import '../../controller/sync/sync_providers.dart';
import '../../models/data_models/profile.dart';
import '../../utils/date_locale.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../screens_profile/components/profile_widgets.dart';
import '../screens_profile/edit_profile_screen.dart' show profileAvatarPickerProvider;

/// Quốc gia chọn được ở bước cập nhật thông tin: mã ISO-3166 alpha-2. Tên hiển thị lấy từ khóa `country_<mã thường>`.
const setupCountryCodes = ['VN', 'US', 'GB', 'AU', 'CA', 'DE', 'FR', 'ES', 'IT', 'GR', 'IN', 'ID', 'JP', 'KR', 'TH', 'SG', 'PH', 'BR'];

/// Cờ emoji dựng từ mã quốc gia (hai ký tự regional indicator).
String countryFlag(String code) => String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));

String countryName(String code) => 'country_${code.toLowerCase()}'.tr;

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Cập nhật thông tin (E04): bước đầu sau intro. Tên bắt buộc; giới tính, quốc gia, ngày sinh, cân nặng, chiều cao tùy chọn
/// — không tự điền giá trị mẫu. "Bắt đầu" tiếp tục với tư cách khách; "Đăng nhập" (chỉ Google) cho người đã có tài khoản.
class SetupProfileScreen extends ConsumerStatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  ConsumerState<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _guard = OnceGuard();
  final _loginGuard = OnceGuard();

  UserSettings? _base;
  Object? _loadError;
  Gender? _gender;
  String? _country;
  DateTime? _birth;
  String? _avatarPath;
  bool _saving = false;
  bool _loggingIn = false;
  String? _saveError;

  WeightUnit get _weightUnit => _base?.weightUnit ?? WeightUnit.kg;

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
      _gender = s.gender;
      _country = s.countryCode;
      _avatarPath = s.avatarPath;
      _birth = s.birthDate == null ? null : DateTime.tryParse(s.birthDate!);
      final h = s.heightCm;
      if (h != null) _height.text = trimNum(h);
      final w = s.weightKg;
      if (w != null) _weight.text = trimNum(s.weightUnit == WeightUnit.lb ? w / kgPerLb : w);
      setState(() => _base = s);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _height, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  ParsedMeasure get _heightParsed => parseHeightCm(_height.text);
  ParsedMeasure get _weightParsed => parseWeightKg(_weight.text, pounds: _weightUnit == WeightUnit.lb);

  Future<void> _pickAvatar() async {
    try {
      final path = await ref.read(profileAvatarPickerProvider).pickAndStore(ref.read(ownerProvider).ownerId);
      if (path != null && mounted) setState(() => _avatarPath = path);
    } catch (_) {
      if (mounted) showStrideSnack(context, 'setup_profile_avatar_error'.tr, isError: true);
    }
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: Localizations.localeOf(context),
    );
    if (picked != null && mounted) setState(() => _birth = picked);
  }

  Future<void> _pickCountry() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final code in setupCountryCodes)
                ListTile(
                  leading: Text(countryFlag(code), style: const TextStyle(fontSize: 24)),
                  title: Text(countryName(code), style: StrideText.body),
                  trailing: code == _country ? const Icon(Icons.check, color: StrideColors.primary) : null,
                  onTap: () => Navigator.of(c).pop(code),
                ),
            ],
          ),
        ),
      ),
    );
    if (code != null && mounted) setState(() => _country = code);
  }

  /// Lưu hồ sơ rồi sang bước xin quyền. Dùng cho cả "Bắt đầu" (khách) lẫn khi đã đăng nhập mà chưa có hồ sơ.
  Future<void> _start() => _guard.run(() async {
    final base = _base;
    if (base == null || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final h = _heightParsed;
      final w = _weightParsed;
      final next = base.copyWith(
        displayName: _name.text.trim(),
        heightCm: h.value,
        clearHeight: h.value == null,
        weightKg: w.value,
        clearWeight: w.value == null,
        gender: _gender,
        countryCode: _country,
        birthDate: _birth == null ? null : _dateKey(_birth!),
        clearBirthDate: _birth == null,
        avatarPath: _avatarPath,
      );
      final saved = await ref.read(settingsRepositoryProvider).save(next);
      final owner = ref.read(ownerProvider);
      if (!owner.isGuest) await ref.read(syncServiceProvider).enqueueProfile(saved);
      await ref.read(ownerRepositoryProvider).markProfileSetupDone(owner.ownerId);
      ref.read(ownerProvider.notifier).reload();
      if (mounted) context.go(Routes.setupPermissions);
    } catch (e) {
      if (mounted) setState(() => _saveError = 'setup_profile_save_error'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  /// Chỉ Google. Hủy chọn tài khoản → im lặng; lỗi → thông báo cụ thể, không tự báo thành công.
  Future<void> _login() => _loginGuard.run(() async {
    setState(() => _loggingIn = true);
    try {
      final next = await signInWithGoogleWidget(ref);
      if (!mounted || next == null) return;
      // Tài khoản cũ đã có hồ sơ → vào thẳng Home; tài khoản mới → ở lại màn này để điền thông tin.
      if (next == Routes.setupProfile) {
        await _load();
        if (mounted) showStrideSnack(context, 'setup_profile_login_new'.tr);
        return;
      }
      context.go(next);
    } catch (e) {
      if (mounted) showStrideSnack(context, googleSignInErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider);
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return StrideScreen(
      title: 'setup_profile_title'.tr,
      showBack: false,
      bottom: _base == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(label: 'setup_profile_start'.tr, loading: _saving, onPressed: _loggingIn ? null : _start),
                if (flags.authGoogle) ...[
                  const SizedBox(height: StrideSpace.s12),
                  Text('setup_profile_had_account'.tr, style: StrideText.bodySecondary, textAlign: TextAlign.center),
                  const SizedBox(height: StrideSpace.s8),
                  OutlineButton(label: 'setup_profile_login'.tr, onPressed: (_saving || _loggingIn) ? null : _login),
                ],
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
                  if (_saveError != null) ...[StatusBanner(tone: BannerTone.error, message: _saveError!), const SizedBox(height: StrideSpace.s12)],
                  const SizedBox(height: StrideSpace.s8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AvatarPicker(name: _name.text, path: _avatarPath, onTap: _pickAvatar),
                      const SizedBox(width: StrideSpace.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('setup_profile_name'.tr, style: StrideText.bodySecondary),
                            const SizedBox(height: StrideSpace.s4),
                            TextFormField(
                              controller: _name,
                              decoration: InputDecoration(hintText: 'setup_profile_name_hint'.tr),
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              validator: validateDisplayName,
                              onChanged: (_) => setState(() {}),
                              style: StrideText.body,
                            ),
                            const SizedBox(height: StrideSpace.s12),
                            Text('setup_profile_gender'.tr, style: StrideText.bodySecondary),
                            const SizedBox(height: StrideSpace.s4),
                            Row(
                              children: [
                                Expanded(
                                  child: _GenderOption(
                                    label: 'setup_profile_gender_male'.tr,
                                    selected: _gender == Gender.male,
                                    onTap: () => setState(() => _gender = Gender.male),
                                  ),
                                ),
                                const SizedBox(width: StrideSpace.s8),
                                Expanded(
                                  child: _GenderOption(
                                    label: 'setup_profile_gender_female'.tr,
                                    selected: _gender == Gender.female,
                                    onTap: () => setState(() => _gender = Gender.female),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: StrideSpace.s20),
                  Text('setup_profile_country'.tr, style: StrideText.bodySecondary),
                  const SizedBox(height: StrideSpace.s4),
                  _PickerField(
                    onTap: _pickCountry,
                    leading: _country == null ? null : Text(countryFlag(_country!), style: const TextStyle(fontSize: 24)),
                    text: _country == null ? 'setup_profile_country_hint'.tr : countryName(_country!),
                    placeholder: _country == null,
                  ),
                  const SizedBox(height: StrideSpace.s20),
                  Text('setup_profile_birth'.tr, style: StrideText.bodySecondary),
                  const SizedBox(height: StrideSpace.s4),
                  _PickerField(
                    onTap: _pickBirth,
                    text: _birth == null ? 'setup_profile_birth_hint'.tr : AppDates.monthDayYear(_birth!),
                    placeholder: _birth == null,
                  ),
                  const SizedBox(height: StrideSpace.s20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('setup_profile_weight'.tr, style: StrideText.bodySecondary),
                            const SizedBox(height: StrideSpace.s4),
                            TextFormField(
                              controller: _weight,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: digits,
                              decoration: InputDecoration(suffixText: _weightUnit.name),
                              validator: (_) => _weightParsed.error,
                              style: StrideText.body,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: StrideSpace.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('setup_profile_height'.tr, style: StrideText.bodySecondary),
                            const SizedBox(height: StrideSpace.s4),
                            TextFormField(
                              controller: _height,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: digits,
                              decoration: const InputDecoration(suffixText: 'cm'),
                              validator: (_) => _heightParsed.error,
                              style: StrideText.body,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: StrideSpace.s12),
                  Text('setup_profile_skip_note'.tr, style: StrideText.caption),
                ],
              ),
            ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.name, required this.path, required this.onTap});
  final String name;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'setup_profile_avatar_pick'.tr,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 104,
        height: 104,
        child: Stack(
          children: [
            ProfileAvatar(name: name, path: path, size: 104),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: StrideColors.textMuted, shape: BoxShape.circle),
                child: const Icon(Icons.photo_camera, size: 18, color: StrideColors.surface),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StrideRadius.control),
      child: Container(
        constraints: const BoxConstraints(minHeight: StrideSpace.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s8),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? StrideColors.primary : StrideColors.borderControl, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(StrideRadius.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, size: 22, color: selected ? StrideColors.primary : StrideColors.textMuted),
            const SizedBox(width: StrideSpace.s4),
            Flexible(
              child: Text(label, style: StrideText.label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.onTap, required this.text, this.leading, this.placeholder = false});
  final VoidCallback onTap;
  final String text;
  final Widget? leading;
  final bool placeholder;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: text,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StrideRadius.control),
      child: Container(
        constraints: const BoxConstraints(minHeight: StrideSpace.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: StrideSpace.s12),
        decoration: BoxDecoration(
          border: Border.all(color: StrideColors.borderControl),
          borderRadius: BorderRadius.circular(StrideRadius.control),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: StrideSpace.s12)],
            Expanded(
              child: Text(text, style: placeholder ? StrideText.bodySecondary : StrideText.body.copyWith(fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.arrow_drop_down, color: StrideColors.textMuted),
          ],
        ),
      ),
    ),
  );
}
