import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/profile.dart';
import 'profile_logic.dart';
import 'profile_widgets.dart';

/// Chọn ảnh và chép vào thư mục documents của app; override trong test.
abstract class ProfileAvatarPicker {
  /// Trả đường dẫn file đã chép, null nếu người dùng hủy.
  Future<String?> pickAndStore(String ownerId);
}

class DeviceAvatarPicker implements ProfileAvatarPicker {
  @override
  Future<String?> pickAndStore(String ownerId) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (picked == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'avatars'));
    await dir.create(recursive: true);
    final safeOwner = ownerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
    final target = p.join(dir.path, 'avatar_${safeOwner}_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(picked.path).copy(target);
    return target;
  }
}

final profileAvatarPickerProvider = Provider<ProfileAvatarPicker>((ref) => DeviceAvatarPicker());

/// Edit profile (J01): tên bắt buộc, ảnh, số đo optional, kinh nghiệm chạy.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      loading: () => const StrideScreen(
        title: 'Edit profile',
        body: Column(children: [Gap(16), LoadingCard(), Gap(12), LoadingCard()]),
      ),
      error: (e, _) => StrideScreen(
        title: 'Edit profile',
        body: ErrorState(
          title: 'Couldn’t load your profile',
          message: 'Your profile is stored on this device. Try again.',
          onRetry: () => ref.invalidate(settingsProvider),
        ),
      ),
      data: (s) => _EditProfileForm(key: ValueKey(s.ownerId), initial: s),
    );
  }
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({super.key, required this.initial});
  final UserSettings initial;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _height;
  late final TextEditingController _heightIn;
  late final TextEditingController _weight;
  late HeightUnit _heightUnit;
  late WeightUnit _weightUnit;
  ActivityLevel? _level;
  String? _avatarPath;

  // Text ban đầu để nhận biết ô chưa sửa → giữ nguyên giá trị gốc.
  late String _origHeight;
  late String _origHeightIn;
  late String _origWeight;
  late HeightUnit _origHeightUnit;
  late WeightUnit _origWeightUnit;

  String? _nameError;
  String? _heightError;
  String? _weightError;
  final _guard = OnceGuard();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _heightUnit = _origHeightUnit = s.heightUnit;
    _weightUnit = _origWeightUnit = s.weightUnit;
    final (h1, h2) = heightFieldText(s.heightCm, s.heightUnit);
    _origHeight = h1;
    _origHeightIn = h2;
    _origWeight = weightFieldText(s.weightKg, s.weightUnit);
    _name = TextEditingController(text: s.displayName);
    _height = TextEditingController(text: h1);
    _heightIn = TextEditingController(text: h2);
    _weight = TextEditingController(text: _origWeight);
    _level = s.activityLevel;
    _avatarPath = s.avatarPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _heightIn.dispose();
    _weight.dispose();
    super.dispose();
  }

  bool get _heightUnchanged => _heightUnit == _origHeightUnit && _height.text == _origHeight && _heightIn.text == _origHeightIn;
  bool get _weightUnchanged => _weightUnit == _origWeightUnit && _weight.text == _origWeight;

  /// Đổi đơn vị trong form: quy đổi giá trị đang nhập (nếu hợp lệ) sang đơn vị mới.
  void _switchHeightUnit(HeightUnit u) {
    if (u == _heightUnit) return;
    final r = parseHeightInput(_heightUnit, _height.text, _heightIn.text);
    final cm = _heightUnchanged ? widget.initial.heightCm : r.value;
    setState(() {
      _heightUnit = u;
      if (cm != null) {
        final (a, b) = heightFieldText(cm, u);
        _height.text = a;
        _heightIn.text = b;
      } else if (r.error == null) {
        _height.clear();
        _heightIn.clear();
      }
      if (u == _origHeightUnit && cm == widget.initial.heightCm) {
        _height.text = _origHeight;
        _heightIn.text = _origHeightIn;
      }
    });
  }

  void _switchWeightUnit(WeightUnit u) {
    if (u == _weightUnit) return;
    final r = parseWeightInput(_weightUnit, _weight.text);
    final kg = _weightUnchanged ? widget.initial.weightKg : r.value;
    setState(() {
      _weightUnit = u;
      if (kg != null) _weight.text = weightFieldText(kg, u);
      if (u == _origWeightUnit && kg == widget.initial.weightKg) _weight.text = _origWeight;
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final path = await ref.read(profileAvatarPickerProvider).pickAndStore(widget.initial.ownerId);
      if (path != null && mounted) setState(() => _avatarPath = path);
    } catch (e) {
      if (mounted) showStrideSnack(context, 'Couldn’t use that photo. Check photo access and try again.', isError: true);
    }
  }

  Future<void> _save() => _guard.run(() async {
    final nameErr = validateDisplayName(_name.text);
    final h = parseHeightInput(_heightUnit, _height.text, _heightIn.text);
    final w = parseWeightInput(_weightUnit, _weight.text);
    setState(() {
      _nameError = nameErr;
      _heightError = _heightUnchanged ? null : h.error;
      _weightError = _weightUnchanged ? null : w.error;
    });
    if (nameErr != null || _heightError != null || _weightError != null) return;
    final heightCm = keepStoredIfUnchanged(stored: widget.initial.heightCm, unchanged: _heightUnchanged, parsed: h.value);
    final weightKg = keepStoredIfUnchanged(stored: widget.initial.weightKg, unchanged: _weightUnchanged, parsed: w.value);
    setState(() => _saving = true);
    try {
      final current = await ref.read(settingsRepositoryProvider).load(widget.initial.ownerId);
      final next = current.copyWith(
        displayName: _name.text.trim(),
        heightCm: heightCm,
        clearHeight: heightCm == null,
        weightKg: weightKg,
        clearWeight: weightKg == null,
        heightUnit: _heightUnit,
        weightUnit: _weightUnit,
        activityLevel: _level,
        avatarPath: _avatarPath,
      );
      await ref.read(settingsRepositoryProvider).save(next);
      if (!mounted) return;
      showStrideSnack(context, 'Profile saved');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showStrideSnack(context, 'Couldn’t save your profile. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  InputDecoration _dec(String label, {String? error, String? hint}) => InputDecoration(labelText: label, errorText: error, hintText: hint);

  @override
  Widget build(BuildContext context) {
    return StrideScreen(
      title: 'Edit profile',
      bottom: PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _saving ? null : _save),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          Center(
            child: Semantics(
              button: true,
              label: 'Change profile photo',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    ProfileAvatar(name: _name.text, path: _avatarPath, size: 104),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: StrideColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: StrideColors.surface, width: 2),
                        ),
                        child: const Icon(Icons.photo_camera_outlined, size: 18, color: StrideColors.surface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(16),
          ProfileSection(
            title: 'Name',
            child: TextField(
              key: const Key('profile-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: _dec('Name', error: _nameError),
              onChanged: (_) => setState(() => _nameError = null),
            ),
          ),
          ProfileSection(
            title: 'Body measurements',
            subtitle: 'New body measurements apply to future calorie estimates. Past activities keep their calories.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('profile-height'),
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _dec(_heightUnit == HeightUnit.cm ? 'Height (optional)' : 'Feet (optional)', error: _heightError),
                        onChanged: (_) => setState(() => _heightError = null),
                      ),
                    ),
                    if (_heightUnit == HeightUnit.ftin) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('profile-height-in'),
                          controller: _heightIn,
                          keyboardType: TextInputType.number,
                          decoration: _dec('Inches'),
                          onChanged: (_) => setState(() => _heightError = null),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _UnitDropdown<HeightUnit>(
                      label: 'Height unit',
                      value: _heightUnit,
                      items: const {HeightUnit.cm: 'cm', HeightUnit.ftin: 'ft-in'},
                      onChanged: _switchHeightUnit,
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('profile-weight'),
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _dec('Weight (optional)', error: _weightError),
                        onChanged: (_) => setState(() => _weightError = null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _UnitDropdown<WeightUnit>(
                      label: 'Weight unit',
                      value: _weightUnit,
                      items: const {WeightUnit.kg: 'kg', WeightUnit.lb: 'lb'},
                      onChanged: _switchWeightUnit,
                    ),
                  ],
                ),
                const Gap(8),
                Text('Leave blank if you prefer not to share. STRIDE won’t fill in sample values.', style: StrideText.caption),
              ],
            ),
          ),
          ProfileSection(
            title: 'Running experience',
            subtitle: 'Helps us personalize your goals and recommendations.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ActivityLevel?>(
                  key: const Key('profile-level'),
                  initialValue: _level,
                  decoration: _dec('Running experience'),
                  items: [
                    const DropdownMenuItem<ActivityLevel?>(value: null, child: Text('Not set')),
                    for (final l in ActivityLevel.values) DropdownMenuItem<ActivityLevel?>(value: l, child: Text(activityLevelLabel(l))),
                  ],
                  onChanged: (v) => setState(() => _level = v),
                ),
                if (_level != null) ...[const Gap(8), Text(activityLevelHelp(_level!), style: StrideText.caption)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitDropdown<T> extends StatelessWidget {
  const _UnitDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox(
      width: 112,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
        items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
}
