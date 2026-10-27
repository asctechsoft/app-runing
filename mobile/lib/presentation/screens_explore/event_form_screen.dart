import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../repository/explore_repository.dart';
import '../../services/application/reminder_scheduler.dart';
import '../../utils/clock.dart';
import '../../utils/date_locale.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/explore_widgets.dart';

/// TM05: tạo sự kiện chạy chung (owner/admin) hoặc sửa ([eventId], người tạo hoặc owner/admin, trước giờ bắt đầu).
/// Giờ theo múi giờ máy người tạo; người xem thấy theo `tzId` của sự kiện. Trả `true` qua `pop` khi đã lưu.
class EventFormScreen extends StatelessWidget {
  const EventFormScreen({super.key, required this.clubId, this.eventId});
  final String clubId;
  final String? eventId;

  @override
  Widget build(BuildContext context) => StrideScreen(
    title: eventId == null ? 'explore_event_create'.tr : 'explore_event_edit_title'.tr,
    body: ExploreGuestGate(
      icon: Icons.event_outlined,
      title: 'explore_clubs_guest_title'.tr,
      message: 'explore_clubs_guest_message'.tr,
      child: _Form(clubId: clubId, eventId: eventId),
    ),
  );
}

/// Thời lượng chọn nhanh; null = không đặt giờ kết thúc.
const _durations = <Duration?>[null, Duration(hours: 1), Duration(hours: 2), Duration(hours: 3)];

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.clubId, this.eventId});
  final String clubId;
  final String? eventId;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _capacity = TextEditingController();
  late DateTime _start;
  Duration? _duration = const Duration(hours: 1);
  bool _busy = false;
  bool _submitted = false;
  bool _loading = false;
  ExploreFailure? _loadError;

  bool get _editing => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    // Mặc định: 7:00 sáng mai.
    final now = ref.read(clockProvider).nowLocal();
    _start = DateTime(now.year, now.month, now.day + 1, 7);
    if (_editing) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final e = await ref.read(exploreRepositoryProvider).event(widget.eventId!);
      if (!mounted) return;
      _title.text = e.title;
      _description.text = e.description;
      _location.text = e.meetingPlace;
      _capacity.text = e.maxGoing?.toString() ?? '';
      setState(() {
        _start = DateTime.fromMillisecondsSinceEpoch(e.startAt);
        _duration = e.endAt == null ? null : Duration(milliseconds: e.endAt! - e.startAt);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = mapExploreError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _capacity.dispose();
    super.dispose();
  }

  int? get _maxGoing => _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()) ?? -1;
  DateTime? get _end => _duration == null ? null : _start.add(_duration!);

  Set<EventDraftError> get _errors => validateEventDraft(
    title: _title.text,
    description: _description.text,
    location: _location.text,
    startsAt: _start,
    endsAt: _end,
    maxGoing: _maxGoing,
    now: ref.read(clockProvider).nowLocal(),
  );

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).nowLocal();
    final d = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (d != null && mounted) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null && mounted) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_busy) return; // T04
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(exploreRepositoryProvider);
      final fields = eventFields(
        title: _title.text,
        description: _description.text,
        location: _location.text,
        startsAt: _start,
        endsAt: _end,
        maxGoing: _maxGoing,
        tzId: currentTzId(),
        nowMs: ref.read(clockProvider).nowMs(),
      );
      if (_editing) {
        await repo.updateEvent(widget.eventId!, fields);
        // Giờ có thể đã đổi → đặt lại nhắc của sự kiện đã đăng ký.
        await ref.read(remindersSyncProvider)();
      } else {
        await repo.createEvent(widget.clubId, fields);
      }
      if (!mounted) return;
      showStrideSnack(context, _editing ? 'explore_event_updated'.tr : 'explore_event_created'.tr);
      context.pop(true);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) return ExploreFailureView(failure: _loadError!, onRetry: _load);
    if (_loading) return const Column(children: [Gap(16), LoadingCard(height: 240)]);
    final e = _submitted ? _errors : const <EventDraftError>{};
    String? titleError;
    if (e.contains(EventDraftError.titleTooShort)) titleError = 'explore_club_name_too_short'.trArgs([eventTitleMin]);
    if (e.contains(EventDraftError.titleTooLong)) titleError = 'explore_club_name_too_long'.trArgs([eventTitleMax]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('event-title'),
          controller: _title,
          maxLength: eventTitleMax,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_event_title_label'.tr, errorText: titleError),
        ),
        TextField(
          key: const Key('event-location'),
          controller: _location,
          maxLength: eventLocationMax,
          decoration: InputDecoration(labelText: 'explore_event_location_label'.tr, hintText: 'explore_event_location_hint'.tr),
        ),
        TextField(
          key: const Key('event-description'),
          controller: _description,
          maxLength: eventDescriptionMax,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: 'explore_club_description'.tr),
        ),
        const Gap(StrideSpace.s8),
        Row(
          children: [
            Expanded(
              child: OutlineButton(key: const Key('event-date'), label: AppDates.shortWeekdayDateYear(_start), onPressed: _pickDate),
            ),
            const SizedBox(width: StrideSpace.s8),
            Expanded(
              child: OutlineButton(key: const Key('event-time'), label: AppDates.time(_start), onPressed: _pickTime),
            ),
          ],
        ),
        if (e.contains(EventDraftError.startInPast)) ...[
          const Gap(StrideSpace.s4),
          Text('explore_event_err_past'.tr, style: StrideText.caption.copyWith(color: StrideColors.error)),
        ],
        const Gap(StrideSpace.s12),
        Text('explore_event_duration'.tr, style: StrideText.label),
        const Gap(StrideSpace.s4),
        Wrap(
          spacing: StrideSpace.s8,
          children: [
            for (final d in _durations)
              ChoiceChip(
                label: Text(d == null ? 'explore_event_duration_none'.tr : 'explore_event_duration_hours'.trPlural(d.inHours, [d.inHours])),
                selected: _duration == d,
                onSelected: (_) => setState(() => _duration = d),
              ),
          ],
        ),
        const Gap(StrideSpace.s12),
        TextField(
          key: const Key('event-capacity'),
          controller: _capacity,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'explore_event_capacity_label'.tr,
            hintText: 'explore_event_capacity_hint'.tr,
            errorText: e.contains(EventDraftError.capacityInvalid) ? 'explore_event_err_capacity'.trArgs([eventMaxGoingMin, eventMaxGoingMax]) : null,
          ),
        ),
        const Gap(StrideSpace.s8),
        Text('explore_event_form_note'.tr, style: StrideText.caption),
        const Gap(StrideSpace.s16),
        PrimaryButton(
          key: const Key('event-save'),
          label: _editing ? 'explore_club_save'.tr : 'explore_event_create'.tr,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}
