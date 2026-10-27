import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../controller/profile/profile_logic.dart' show loadDefaultPrivacy;
import '../../controller/profile/review_prompt.dart';
import '../../controller/providers.dart';
import '../../controller/run/engine/run_session_controller.dart';
import '../../models/data_models/activity.dart';
import '../../models/data_models/session_state.dart';
import '../../utils/formatters.dart';
import '../../utils/haptics.dart';
import '../../utils/l10n.dart';
import '../../utils/logger.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/run_widgets.dart';

String privacyLabel(Privacy p) => switch (p) {
  Privacy.onlyMe => 'run_privacy_only_me'.tr,
  Privacy.followers => 'run_privacy_followers'.tr,
  Privacy.public => 'run_privacy_public'.tr,
};

String privacyHint(Privacy p) => switch (p) {
  Privacy.onlyMe => 'run_privacy_hint_only_me'.tr,
  Privacy.followers => 'run_privacy_hint_followers'.tr,
  Privacy.public => 'run_privacy_hint_public'.tr,
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
      if (mounted) showStrideSnack(context, 'run_save_photos_error'.tr, isError: true);
    }
  }

  Future<void> _pickPrivacy() async {
    final r = await showStrideSheet<Privacy>(
      context,
      title: 'run_save_privacy_sheet'.tr,
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
      StrideHaptics.light();
      // X23: chỉ hỏi đánh giá sau khi đã lưu xong, không chặn điều hướng.
      unawaited(ref.read(reviewPromptProvider).onRunSaved());
      if (!mounted) return;
      context.go('${Routes.saved}?id=${saved.id}');
    } catch (e, st) {
      StrideLog.e('run.save', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      StrideHaptics.heavy();
      showStrideSnack(context, 'run_save_failed'.tr, actionLabel: 'action_retry'.tr, onAction: _save, isError: true);
    }
  });

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(runSessionProvider);
    final fmt = ref.watch(formatProvider);
    final a = st.activity;
    if (a == null) {
      return StrideScreen(title: 'run_save_activity'.tr, body: const LoadingCard());
    }
    final indoor = a.type == ActivityType.indoorRun;
    return StrideScreen(
      title: 'run_save_activity'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SageCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'run_label_distance'.tr,
                    value: fmt.distanceValue(a.distanceM),
                    unit: fmt.distanceUnitLabel,
                    center: true,
                    estimated: indoor,
                  ),
                ),
                Expanded(
                  child: MetricTile(label: 'run_label_moving_time'.tr, value: formatDuration(a.movingMs), center: true),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'run_label_avg_pace'.tr,
                    value: fmt.paceValue(a.avgPaceSecPerKm),
                    unit: a.avgPaceSecPerKm == null ? null : fmt.paceUnitLabel,
                    center: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('run_save_title_label'.tr, style: StrideText.label),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'run_save_title_hint'.tr,
              counterText: '',
              suffixIcon: IconButton(tooltip: 'run_save_clear_title'.tr, icon: const Icon(Icons.close), onPressed: () => _title.clear()),
            ),
          ),
          const SizedBox(height: 16),
          Text('run_save_date'.tr, style: StrideText.label),
          const SizedBox(height: 6),
          Semantics(
            label: 'run_save_date_semantic'.trArgs([longDate(a.startedAt)]),
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
          Text('run_save_feeling'.tr, style: StrideText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final f in Feeling.values)
                StrideChip(
                  label: switch (f) {
                    Feeling.easy => 'run_feeling_easy'.tr,
                    Feeling.steady => 'run_feeling_steady'.tr,
                    Feeling.hard => 'run_feeling_hard'.tr,
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
          Text('run_save_notes'.tr, style: StrideText.label),
          const SizedBox(height: 6),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'run_save_notes_hint'.tr),
          ),
          const SizedBox(height: 8),
          Text('run_save_add_photos'.tr, style: StrideText.label),
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
                        semanticLabel: 'run_save_selected_photo'.tr,
                        errorBuilder: (_, _, _) => Container(width: 88, height: 88, color: StrideColors.subtle, child: const Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        tooltip: 'run_save_remove_photo'.tr,
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
                  label: 'run_save_add_photos'.tr,
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined, color: StrideColors.primary),
                          Text('run_save_add_photo'.tr, style: StrideText.caption),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('run_save_privacy'.tr, style: StrideText.label),
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
          PrimaryButton(label: 'run_save_activity'.tr, loading: _saving, onPressed: _save),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_android, size: 14, color: StrideColors.textMuted),
              const SizedBox(width: 4),
              Text('run_save_local_first'.tr, style: StrideText.caption),
            ],
          ),
        ],
      ),
    );
  }
}
