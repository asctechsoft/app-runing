import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../values/routes.dart';
import '../../utils/formatters.dart';
import '../../utils/logger.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../controller/profile/profile_logic.dart' show loadDefaultPrivacy;
import '../../controller/run/engine/run_session_controller.dart';
import 'components/run_widgets.dart';

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only me',
  Privacy.followers => 'Followers',
  Privacy.public => 'Public',
};

String privacyHint(Privacy p) => switch (p) {
  Privacy.onlyMe => 'Only you can see this activity.',
  Privacy.followers => 'People who follow you can see it.',
  Privacy.public => 'Anyone on STRIDE can see it.',
};

/// Lưu hoạt động (G10): title/feeling/notes/photos/privacy → lưu local trước (offline OK).
class SaveActivityScreen extends ConsumerStatefulWidget {
  const SaveActivityScreen({super.key});

  @override
  ConsumerState<SaveActivityScreen> createState() => _SaveActivityScreenState();
}

class _SaveActivityScreenState extends ConsumerState<SaveActivityScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  Feeling? _feeling;
  Privacy _privacy = Privacy.onlyMe;
  bool _privacyTouched = false;
  final List<String> _photos = [];
  bool _saving = false;
  final _guard = OnceGuard();
  static const _maxPhotos = 10;

  @override
  void initState() {
    super.initState();
    final a = ref.read(runSessionProvider).activity;
    if (a != null) {
      _title.text = a.title;
      _privacy = a.privacy;
      _feeling = a.feeling;
      _notes.text = a.notes ?? '';
    }
    _loadDefaultPrivacy();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(runSessionProvider).phase != SessionPhase.awaitingSave) context.go(Routes.results);
    });
  }

  /// Mặc định hiển thị theo Privacy settings (fallback Only me).
  Future<void> _loadDefaultPrivacy() async {
    try {
      final p = await loadDefaultPrivacy(ref.read(settingsRepositoryProvider), ref.read(ownerProvider).ownerId);
      if (mounted && !_privacyTouched) setState(() => _privacy = p);
    } catch (e, st) {
      StrideLog.e('run.privacy', e, st);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(limit: _maxPhotos - _photos.length, imageQuality: 85, maxWidth: 2400);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        for (final x in picked) {
          if (_photos.length < _maxPhotos && !_photos.contains(x.path)) _photos.add(x.path);
        }
      });
    } catch (e, st) {
      StrideLog.e('run.photos', e, st);
      if (mounted) showStrideSnack(context, 'Couldn\'t open your photos. Check photo access in Settings.', isError: true);
    }
  }

  Future<void> _pickPrivacy() async {
    final r = await showStrideSheet<Privacy>(
      context,
      title: 'Who can see this?',
      builder: (ctx) => Column(
        children: [
          for (final p in Privacy.values)
            SettingsRow(
              title: privacyLabel(p),
              subtitle: privacyHint(p),
              icon: p == Privacy.onlyMe
                  ? Icons.lock_outline
                  : p == Privacy.followers
                  ? Icons.group_outlined
                  : Icons.public,
              showChevron: false,
              trailing: Icon(p == _privacy ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: StrideColors.primary),
              onTap: () => Navigator.of(ctx).pop(p),
            ),
        ],
      ),
    );
    if (r != null) {
      setState(() {
        _privacy = r;
        _privacyTouched = true;
      });
    }
  }

  Future<void> _save() => _guard.run(() async {
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(runSessionProvider.notifier)
          .save(title: _title.text, feeling: _feeling, notes: _notes.text, privacy: _privacy, photoPaths: List.of(_photos));
      if (!mounted) return;
      context.go('${Routes.saved}?id=${saved.id}');
    } catch (e, st) {
      StrideLog.e('run.save', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      showStrideSnack(context, 'Couldn\'t save activity. Your draft is still available.', actionLabel: 'Retry', onAction: _save, isError: true);
    }
  });

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(runSessionProvider);
    final fmt = ref.watch(formatProvider);
    final a = st.activity;
    if (a == null) {
      return const StrideScreen(title: 'Save activity', body: LoadingCard());
    }
    final indoor = a.type == ActivityType.indoorRun;
    return StrideScreen(
      title: 'Save activity',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SageCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: MetricTile(label: 'Distance', value: fmt.distanceValue(a.distanceM), unit: fmt.distanceUnitLabel, center: true, estimated: indoor),
                ),
                Expanded(
                  child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs), center: true),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'Avg. pace',
                    value: fmt.paceValue(a.avgPaceSecPerKm),
                    unit: a.avgPaceSecPerKm == null ? null : fmt.paceUnitLabel,
                    center: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Activity title', style: StrideText.label),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Name your activity',
              counterText: '',
              suffixIcon: IconButton(tooltip: 'Clear title', icon: const Icon(Icons.close), onPressed: () => _title.clear()),
            ),
          ),
          const SizedBox(height: 16),
          Text('Date', style: StrideText.label),
          const SizedBox(height: 6),
          Semantics(
            label: 'Date, ${longDate(a.startedAt)}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: StrideColors.surface,
                borderRadius: BorderRadius.circular(StrideRadius.control),
                border: Border.all(color: StrideColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20, color: StrideColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${longDate(a.startedAt)} · ${clockTime(a.startedAt)}', style: StrideText.body)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('How did it feel?', style: StrideText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final f in Feeling.values)
                StrideChip(
                  label: switch (f) {
                    Feeling.easy => 'Easy',
                    Feeling.steady => 'Steady',
                    Feeling.hard => 'Hard',
                  },
                  icon: switch (f) {
                    Feeling.easy => Icons.sentiment_satisfied,
                    Feeling.steady => Icons.sentiment_neutral,
                    Feeling.hard => Icons.sentiment_dissatisfied,
                  },
                  selected: _feeling == f,
                  onTap: () => setState(() => _feeling = _feeling == f ? null : f),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Notes', style: StrideText.label),
          const SizedBox(height: 6),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'How was your activity?'),
          ),
          const SizedBox(height: 8),
          Text('Add photos', style: StrideText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _photos)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(StrideRadius.small),
                      child: Image.file(
                        File(p),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        semanticLabel: 'Selected photo',
                        errorBuilder: (_, _, _) => Container(width: 88, height: 88, color: StrideColors.subtle, child: const Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        tooltip: 'Remove photo',
                        style: IconButton.styleFrom(backgroundColor: StrideColors.surface),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _photos.remove(p)),
                      ),
                    ),
                  ],
                ),
              if (_photos.length < _maxPhotos)
                Semantics(
                  button: true,
                  label: 'Add photos',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: _addPhotos,
                    borderRadius: BorderRadius.circular(StrideRadius.small),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: StrideColors.subtle,
                        borderRadius: BorderRadius.circular(StrideRadius.small),
                        border: Border.all(color: StrideColors.borderSubtle),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: StrideColors.primary),
                          Text('Add photo', style: StrideText.caption),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Privacy', style: StrideText.label),
          const SizedBox(height: 6),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: _privacy == Privacy.onlyMe ? Icons.lock_outline : (_privacy == Privacy.followers ? Icons.group_outlined : Icons.public),
                title: privacyLabel(_privacy),
                subtitle: privacyHint(_privacy),
                onTap: _pickPrivacy,
              ),
            ],
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: 'Save activity', loading: _saving, onPressed: _save),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_android, size: 14, color: StrideColors.textMuted),
              const SizedBox(width: 4),
              Text('Saved on this device first', style: StrideText.caption),
            ],
          ),
        ],
      ),
    );
  }
}
