import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/explore/explore_logic.dart';
import '../../repository/explore_repository.dart';
import '../../utils/analytics.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/explore_widgets.dart';

/// TM01: tạo câu lạc bộ. Người tạo thành owner; club riêng tư thì người khác phải được duyệt mới vào.
/// TM04: có [clubId] → sửa thông tin + nội quy của club đó (chỉ owner/admin; rules chặn người khác).
class CreateClubScreen extends StatelessWidget {
  const CreateClubScreen({super.key, this.clubId});
  final String? clubId;

  @override
  Widget build(BuildContext context) => StrideScreen(
    title: clubId == null ? 'explore_club_create_title'.tr : 'explore_club_edit_title'.tr,
    body: ExploreGuestGate(
      title: 'explore_clubs_guest_title'.tr,
      message: 'explore_clubs_guest_message'.tr,
      child: _CreateClubForm(clubId: clubId),
    ),
  );
}

class _CreateClubForm extends ConsumerStatefulWidget {
  const _CreateClubForm({this.clubId});
  final String? clubId;

  @override
  ConsumerState<_CreateClubForm> createState() => _CreateClubFormState();
}

class _CreateClubFormState extends ConsumerState<_CreateClubForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _region = TextEditingController();
  final _rules = TextEditingController();
  bool _private = false;
  bool _busy = false;
  bool _submitted = false;

  bool get _editing => widget.clubId != null;

  /// Chế độ sửa: đang tải club (null = xong), lỗi tải.
  bool _loading = false;
  ExploreFailure? _loadError;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final c = await ref.read(exploreRepositoryProvider).club(widget.clubId!);
      if (!mounted) return;
      _name.text = c.name;
      _description.text = c.description;
      _region.text = c.regionText;
      _rules.text = c.rulesText;
      setState(() {
        _private = c.isPrivate;
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
    _name.dispose();
    _description.dispose();
    _region.dispose();
    _rules.dispose();
    super.dispose();
  }

  Set<ClubDraftError> get _errors => validateClubDraft(name: _name.text, description: _description.text, region: _region.text, rulesText: _rules.text);

  String? _nameError(Set<ClubDraftError> e) {
    if (!_submitted) return null;
    if (e.contains(ClubDraftError.nameTooShort)) return 'explore_club_name_too_short'.trArgs([clubNameMin]);
    if (e.contains(ClubDraftError.nameTooLong)) return 'explore_club_name_too_long'.trArgs([clubNameMax]);
    return null;
  }

  Future<void> _create() async {
    if (_busy) return; // T04
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      if (_editing) {
        await ref
            .read(exploreRepositoryProvider)
            .updateClub(widget.clubId!, name: _name.text, description: _description.text, region: _region.text, isPrivate: _private, rulesText: _rules.text);
        if (!mounted) return;
        showStrideSnack(context, 'explore_club_updated'.tr);
        context.pop(true);
        return;
      }
      final id = await ref
          .read(exploreRepositoryProvider)
          .createClub(name: _name.text, description: _description.text, region: _region.text, isPrivate: _private);
      Analytics.clubCreate(visibility: _private ? 'private' : 'public');
      if (!mounted) return;
      showStrideSnack(context, 'explore_club_created'.tr);
      context.pushReplacement(Routes.club(id));
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
    final errors = _errors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('club-name'),
          controller: _name,
          maxLength: clubNameMax,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_club_name'.tr, errorText: _nameError(errors)),
        ),
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('club-description'),
          controller: _description,
          maxLength: clubDescriptionMax,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_club_description'.tr),
        ),
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('club-region'),
          controller: _region,
          maxLength: clubRegionMax,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_club_region'.tr, hintText: 'explore_clubs_region_hint'.tr),
        ),
        const Gap(StrideSpace.s8),
        TextField(
          key: const Key('club-rules'),
          controller: _rules,
          maxLength: clubRulesMax,
          minLines: 2,
          maxLines: 8,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'explore_club_rules'.tr, hintText: 'explore_club_rules_hint'.tr),
        ),
        const Gap(StrideSpace.s8),
        SwitchListTile(
          key: const Key('club-private'),
          contentPadding: EdgeInsets.zero,
          value: _private,
          onChanged: (v) => setState(() => _private = v),
          title: Text('explore_club_private'.tr, style: StrideText.body),
          subtitle: Text(_private ? 'explore_club_private_on'.tr : 'explore_club_private_off'.tr, style: StrideText.caption),
        ),
        const Gap(StrideSpace.s16),
        PrimaryButton(
          key: const Key('club-create'),
          label: _editing ? 'explore_club_save'.tr : 'explore_club_create'.tr,
          loading: _busy,
          onPressed: _busy ? null : _create,
        ),
        if (!_editing) ...[
          const Gap(StrideSpace.s8),
          Text('explore_club_create_note'.trArgs([maxOwnedClubs]), style: StrideText.caption, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}
