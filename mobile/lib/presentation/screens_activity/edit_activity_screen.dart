import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../utils/formatters.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../controller/activity/activity_actions.dart';
import '../../utils/activity_format.dart';
import '../../controller/activity/activity_providers.dart';

const int maxActivityPhotos = 10;
const int maxNotesLength = 500;

/// Sửa metadata (I03, F15): tên, cảm nhận, ghi chú, quyền riêng tư, ảnh. Tuyến/quãng đường chỉ đọc.
class EditActivityScreen extends ConsumerStatefulWidget {
  const EditActivityScreen({super.key, required this.activityId});
  final String activityId;

  @override
  ConsumerState<EditActivityScreen> createState() => _EditActivityScreenState();
}

class _EditActivityScreenState extends ConsumerState<EditActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _guard = OnceGuard();
  Activity? _initial;
  Feeling? _feeling;
  Privacy _privacy = Privacy.onlyMe;
  List<ActivityPhoto> _photos = const [];
  final Set<String> _removed = {};
  final List<XFile> _added = [];
  bool _saving = false;
  bool _done = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _init(ActivityDetailData d) {
    if (_initial != null) return;
    final a = d.activity;
    _initial = a;
    _title.text = a.title.trim().isEmpty ? activityDisplayTitle(a) : a.title;
    _notes.text = a.notes ?? '';
    _feeling = a.feeling;
    _privacy = a.privacy;
    _photos = d.photos;
  }

  bool get _dirty {
    final a = _initial;
    if (a == null || _done) return false;
    final origTitle = a.title.trim().isEmpty ? activityDisplayTitle(a) : a.title;
    return _title.text != origTitle ||
        _notes.text != (a.notes ?? '') ||
        _feeling != a.feeling ||
        _privacy != a.privacy ||
        _removed.isNotEmpty ||
        _added.isNotEmpty;
  }

  int get _photoCount => _photos.where((p) => !_removed.contains(p.id)).length + _added.length;

  Future<void> _addPhoto() async {
    if (_photoCount >= maxActivityPhotos) {
      showStrideSnack(context, 'You can add up to $maxActivityPhotos photos.');
      return;
    }
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 85);
      if (x != null && mounted) setState(() => _added.add(x));
    } on PlatformException {
      if (mounted) {
        showStrideSnack(context, 'STRIDE can\'t open your photos. Allow photo access in phone settings.', isError: true);
      }
    }
  }

  /// Sao chép ảnh vào thư mục riêng của app (file gốc trong thư viện không bị đụng tới).
  Future<(String, int, String)> _persist(XFile x) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}attachments');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final lower = x.name.toLowerCase();
    final ext = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.heic')
        ? 'heic'
        : 'jpg';
    final path = '${folder.path}${Platform.pathSeparator}${const Uuid().v4()}.$ext';
    await x.saveTo(path);
    final mime = switch (ext) {
      'png' => 'image/png',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    return (path, await File(path).length(), mime);
  }

  Future<void> _save() async {
    final a = _initial;
    if (a == null || !(_formKey.currentState?.validate() ?? false)) return;
    await _guard.run(() async {
      setState(() => _saving = true);
      final repo = ref.read(activityRepositoryProvider);
      try {
        await repo.updateMetadata(
          a,
          title: _title.text.trim(),
          feeling: _feeling,
          clearFeeling: _feeling == null,
          notes: _notes.text.trim(),
          privacy: _privacy,
        );
        for (final id in _removed) {
          await repo.removeAttachment(a.ownerId, id);
        }
        for (final x in _added) {
          final (path, bytes, mime) = await _persist(x);
          await repo.addAttachment(activityId: a.id, ownerId: a.ownerId, localPath: path, mime: mime, bytes: bytes);
        }
        if (!mounted) return;
        _done = true; // không hỏi "discard" khi pop
        showStrideSnack(context, 'Changes saved');
        context.pop('saved');
      } catch (_) {
        if (mounted) showStrideSnack(context, 'Couldn\'t save your changes. Please try again.', isError: true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    });
  }

  Future<void> _delete() async {
    final a = _initial;
    if (a == null) return;
    final deleted = await confirmAndDeleteActivity(context, ref, a);
    if (deleted && mounted) {
      _done = true;
      showStrideSnack(context, 'Activity deleted');
      context.pop('deleted');
    }
  }

  Future<bool> _confirmDiscard() => confirmDialog(
    context,
    title: 'Discard changes?',
    message: 'Your edits to this activity haven\'t been saved.',
    confirmLabel: 'Discard',
    cancelLabel: 'Keep editing',
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityDetailProvider(widget.activityId));
    final f = ref.watch(formatProvider);
    final d = async.value;
    if (d != null) _init(d);
    if (async.isLoading && _initial == null) {
      return const StrideScreen(title: 'Edit activity', body: LoadingCard(height: 240));
    }
    if (_initial == null) {
      return StrideScreen(
        title: 'Edit activity',
        body: async.hasError
            ? ErrorState(
                title: 'Couldn\'t open this activity',
                message: 'Reading it from this device failed.',
                onRetry: () => ref.invalidate(activityDetailProvider(widget.activityId)),
              )
            : const EmptyState(icon: Icons.search_off, title: 'Activity not found', message: 'This activity may have been deleted.'),
      );
    }
    final a = _initial!;
    final kept = _photos.where((p) => !_removed.contains(p.id)).toList();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _done = true);
          Navigator.of(context).pop();
        }
      },
      child: StrideScreen(
        title: 'Edit activity',
        bottom: PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _save),
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Activity title'),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a run title' : null,
              ),
              const SizedBox(height: 8),
              Text('How did it feel?', style: StrideText.label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final fe in Feeling.values) StrideChip(label: feelingLabel(fe), selected: _feeling == fe, onTap: () => setState(() => _feeling = fe)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
                minLines: 3,
                maxLines: 6,
                maxLength: maxNotesLength,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SectionHeader(title: 'Photos', subtitle: '$_photoCount of $maxActivityPhotos'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in kept)
                    _PhotoTile(image: p.fileExists ? FileImage(File(p.localPath!)) : null, label: 'Photo', onRemove: () => setState(() => _removed.add(p.id))),
                  for (final x in _added) _PhotoTile(image: FileImage(File(x.path)), label: 'New photo', onRemove: () => setState(() => _added.remove(x))),
                  if (_photoCount < maxActivityPhotos)
                    Semantics(
                      button: true,
                      label: 'Add photo',
                      child: InkWell(
                        onTap: _addPhoto,
                        borderRadius: BorderRadius.circular(StrideRadius.control),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: StrideColors.subtle,
                            borderRadius: BorderRadius.circular(StrideRadius.control),
                            border: Border.all(color: StrideColors.borderSubtle),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, color: StrideColors.primary),
                              SizedBox(height: 4),
                              Text('Add photo', style: StrideText.caption),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const SectionHeader(title: 'Privacy'),
              SettingsGroup(
                children: [
                  for (final p in Privacy.values)
                    SettingsRow(
                      title: privacyLabel(p),
                      subtitle: privacyDescription(p),
                      showChevron: false,
                      trailing: Icon(
                        _privacy == p ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _privacy == p ? StrideColors.primary : StrideColors.borderControl,
                      ),
                      onTap: () => setState(() => _privacy = p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const SectionHeader(title: 'Recorded data'),
              StrideCard(
                color: StrideColors.subtle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: 'Distance',
                            value: f.distanceValue(a.distanceM),
                            unit: f.distanceUnitLabel,
                            estimated: a.distanceSource != DistanceSource.gps,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Route, distance and time come from your recording and can\'t be edited.', style: StrideText.caption),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: StrideColors.error, minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete activity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.label, required this.onRemove});
  final ImageProvider? image;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(StrideRadius.control),
              child: image == null
                  ? const ColoredBox(
                      color: StrideColors.subtle,
                      child: Icon(Icons.broken_image_outlined, color: StrideColors.textMuted),
                    )
                  : Image(image: image!, fit: BoxFit.cover, semanticLabel: label),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              tooltip: 'Remove photo',
              onPressed: onRemove,
              icon: const CircleAvatar(
                radius: 12,
                backgroundColor: StrideColors.textPrimary,
                child: Icon(Icons.close, size: 14, color: StrideColors.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
