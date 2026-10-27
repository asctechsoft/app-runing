import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/explore_widgets.dart';

/// TM31: owner/admin tạo thử thách cho club. Chỉ run/walk có GPS thật được tính (ADR 0003). Trả id mới qua `pop`.
class CreateChallengeScreen extends StatelessWidget {
  const CreateChallengeScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context) => StrideScreen(
    title: 'explore_challenge_create'.tr,
    body: ExploreGuestGate(
      icon: Icons.emoji_events_outlined,
      title: 'explore_challenges_guest_title'.tr,
      message: 'explore_challenges_guest_message'.tr,
      child: _Form(clubId: clubId),
    ),
  );
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.clubId});
  final String clubId;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();
  ChallengeTarget _metric = ChallengeTarget.distance;
  late DateTime _start;
  late DateTime _end;
  bool _busy = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final today = ref.read(clockProvider).nowLocal();
    final (s, e) = ChallengeTemplate.distanceMonth.period(today);
    _start = s;
    _end = e;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  StrideFormat get _fmt => ref.read(formatProvider);

  /// Mục tiêu theo đơn vị gốc từ ô nhập (km/mi, buổi, giờ). Chấp nhận cả dấu phẩy thập phân.
  double? get _targetBase {
    final v = double.tryParse(_target.text.trim().replaceAll(',', '.'));
    if (v == null) return null;
    return switch (_metric) {
      ChallengeTarget.distance => _fmt.unitToMeters(v),
      ChallengeTarget.count => v,
      ChallengeTarget.time => v * 3600 * 1000,
    };
  }

  String _formatInput(ChallengeTemplate t) {
    final v = switch (t.metric) {
      ChallengeTarget.distance => _fmt.metersToUnit(t.target),
      ChallengeTarget.count => t.target,
      ChallengeTarget.time => t.target / 3600 / 1000,
    };
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  void _apply(ChallengeTemplate t) {
    final (s, e) = t.period(ref.read(clockProvider).nowLocal());
    setState(() {
      _metric = t.metric;
      _title.text = t.titleKey.tr;
      _target.text = _formatInput(t);
      _start = s;
      _end = e;
    });
  }

  Set<ChallengeDraftError> get _errors => validateChallengeDraft(
    title: _title.text,
    description: _description.text,
    metric: _metric,
    target: _targetBase,
    start: _start,
    end: _end,
    today: ref.read(clockProvider).nowLocal(),
  );

  String get _unitLabel => switch (_metric) {
    ChallengeTarget.distance => _fmt.distanceUnitLabel,
    ChallengeTarget.count => 'explore_challenge_unit_runs'.tr,
    ChallengeTarget.time => 'explore_challenge_unit_hours'.tr,
  };

  Future<void> _pickDate({required bool start}) async {
    final today = ref.read(clockProvider).nowLocal();
    final first = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? first : _start,
      lastDate: DateTime(first.year + 1, first.month, first.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _create() async {
    if (_busy) return; // T04
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(exploreRepositoryProvider)
          .createChallenge(widget.clubId, title: _title.text, description: _description.text, metric: _metric, target: _targetBase!, start: _start, end: _end);
      if (!mounted) return;
      showStrideSnack(context, 'explore_challenge_created'.tr);
      context.pop(id);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _submitted ? _errors : const <ChallengeDraftError>{};
    String? titleError;
    if (e.contains(ChallengeDraftError.titleTooShort)) titleError = 'explore_club_name_too_short'.trArgs([challengeTitleMin]);
    if (e.contains(ChallengeDraftError.titleTooLong)) titleError = 'explore_club_name_too_long'.trArgs([challengeTitleMax]);
    final dateError = e.contains(ChallengeDraftError.startInPast)
        ? 'explore_challenge_err_start_past'.tr
        : e.contains(ChallengeDraftError.endBeforeStart)
        ? 'explore_challenge_err_end_before_start'.tr
        : e.contains(ChallengeDraftError.tooLong)
        ? 'explore_challenge_err_too_long'.trArgs([challengeMaxDays])
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(StrideSpace.s8),
        Text('explore_challenge_templates'.tr, style: StrideText.label),
        const Gap(StrideSpace.s8),
        Wrap(
          spacing: StrideSpace.s8,
          runSpacing: StrideSpace.s8,
          children: [
            for (final t in ChallengeTemplate.values) ActionChip(key: Key('template-${t.name}'), label: Text(t.titleKey.tr), onPressed: () => _apply(t)),
          ],
        ),
        const Gap(StrideSpace.s16),
        TextField(
          key: const Key('challenge-title'),
          controller: _title,
          maxLength: challengeTitleMax,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_challenge_title_label'.tr, errorText: titleError),
        ),
        TextField(
          key: const Key('challenge-description'),
          controller: _description,
          maxLength: challengeDescriptionMax,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: 'explore_club_description'.tr),
        ),
        const Gap(StrideSpace.s8),
        StrideSegmented<ChallengeTarget>(
          values: ChallengeTarget.values,
          selected: _metric,
          labelOf: (m) => switch (m) {
            ChallengeTarget.distance => 'explore_challenge_metric_distance'.tr,
            ChallengeTarget.count => 'explore_challenge_metric_count'.tr,
            ChallengeTarget.time => 'explore_challenge_metric_time'.tr,
          },
          onChanged: (m) => setState(() {
            _metric = m;
            _target.clear();
          }),
        ),
        const Gap(StrideSpace.s12),
        TextField(
          key: const Key('challenge-target'),
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'explore_challenge_target_label'.tr,
            suffixText: _unitLabel,
            errorText: e.contains(ChallengeDraftError.targetInvalid) ? 'explore_challenge_err_target'.tr : null,
          ),
        ),
        const Gap(StrideSpace.s12),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                key: const Key('challenge-start'),
                label: 'explore_challenge_starts'.trArgs([AppDates.monthDayYear(_start)]),
                onPressed: () => _pickDate(start: true),
              ),
            ),
            const SizedBox(width: StrideSpace.s8),
            Expanded(
              child: OutlineButton(
                key: const Key('challenge-end'),
                label: 'explore_challenge_ends'.trArgs([AppDates.monthDayYear(_end)]),
                onPressed: () => _pickDate(start: false),
              ),
            ),
          ],
        ),
        if (dateError != null) ...[const Gap(StrideSpace.s4), Text(dateError, style: StrideText.caption.copyWith(color: StrideColors.error))],
        const Gap(StrideSpace.s12),
        Text('explore_challenge_create_note'.tr, style: StrideText.caption),
        const Gap(StrideSpace.s16),
        PrimaryButton(key: const Key('challenge-submit'), label: 'explore_challenge_create'.tr, loading: _busy, onPressed: _busy ? null : _create),
      ],
    );
  }
}
