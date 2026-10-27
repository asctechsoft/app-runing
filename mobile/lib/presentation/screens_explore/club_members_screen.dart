import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../utils/l10n.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'components/explore_widgets.dart';

/// TM02: thành viên + yêu cầu chờ duyệt. Hành động hiển thị theo vai trò (`availableMemberActions`, khớp rules).
class ClubMembersScreen extends StatelessWidget {
  const ClubMembersScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context) => StrideScreen(
    title: 'explore_club_members_title'.tr,
    scroll: false,
    body: ExploreGuestGate(
      title: 'explore_clubs_guest_title'.tr,
      message: 'explore_clubs_guest_message'.tr,
      child: _MembersBody(clubId: clubId),
    ),
  );
}

class _MembersBody extends ConsumerStatefulWidget {
  const _MembersBody({required this.clubId});
  final String clubId;

  @override
  ConsumerState<_MembersBody> createState() => _MembersBodyState();
}

class _MembersBodyState extends ConsumerState<_MembersBody> {
  final _search = TextEditingController();
  Club? _club;
  List<ClubMember>? _pending;
  List<ClubMember>? _members;
  String? _cursor;
  ExploreFailure? _error;
  bool _loadingMore = false;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repo = ref.read(exploreRepositoryProvider);
    try {
      final club = await repo.club(widget.clubId);
      final members = await repo.clubMembers(widget.clubId);
      final pending = club.membership?.canManage == true ? (await repo.clubMembers(widget.clubId, pending: true)).items : const <ClubMember>[];
      if (!mounted) return;
      setState(() {
        _club = club;
        _members = members.items;
        _cursor = members.nextCursor;
        _pending = pending;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _more() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(exploreRepositoryProvider).clubMembers(widget.clubId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _members = [...?_members, ...page.items];
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _name(ClubMember m) => m.displayName.isEmpty ? 'explore_club_member_unnamed'.tr : m.displayName;

  Future<void> _act(ClubMember m, MemberAction a) async {
    if (_busy.contains(m.userId)) return; // T04
    final confirm = switch (a) {
      MemberAction.remove => ('explore_club_remove_title'.trArgs([_name(m)]), 'explore_club_remove_message'.tr, 'explore_club_remove'.tr),
      MemberAction.ban => ('explore_club_ban_title'.trArgs([_name(m)]), 'explore_club_ban_message'.tr, 'explore_club_ban'.tr),
      MemberAction.transferOwnership => ('explore_club_transfer_title'.trArgs([_name(m)]), 'explore_club_transfer_message'.tr, 'explore_club_transfer'.tr),
      _ => null,
    };
    if (confirm != null) {
      final ok = await confirmDialog(
        context,
        title: confirm.$1,
        message: confirm.$2,
        confirmLabel: confirm.$3,
        cancelLabel: 'explore_keep'.tr,
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(m.userId));
    final repo = ref.read(exploreRepositoryProvider);
    try {
      switch (a) {
        case MemberAction.approve:
          await repo.approveMember(widget.clubId, m.userId);
        case MemberAction.reject:
        case MemberAction.remove:
          await repo.removeMember(widget.clubId, m.userId);
        case MemberAction.ban:
          await repo.removeMember(widget.clubId, m.userId, ban: true);
        case MemberAction.makeAdmin:
          await repo.setMemberRole(widget.clubId, m.userId, 'admin');
        case MemberAction.makeMember:
          await repo.setMemberRole(widget.clubId, m.userId, 'member');
        case MemberAction.transferOwnership:
          await repo.transferOwnership(widget.clubId, m.userId);
      }
      if (!mounted) return;
      showStrideSnack(context, 'explore_club_member_updated'.tr);
      await _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(m.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SingleChildScrollView(
        child: ExploreFailureView(failure: _error!, onRetry: _load),
      );
    }
    final club = _club;
    final members = _members;
    if (club == null || members == null) return ListView(children: const [LoadingCard(height: 72), Gap(12), LoadingCard(height: 72)]);
    final myRole = club.membership?.isMember == true ? club.membership!.role : 'none';
    final myUid = ref.read(ownerProvider).ownerId;
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty ? members : members.where((m) => _name(m).toLowerCase().contains(q)).toList();
    final pending = _pending ?? const <ClubMember>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: StrideSpace.s24),
        children: [
          TextField(
            key: const Key('members-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'explore_club_members_search'.tr),
          ),
          if (pending.isNotEmpty) ...[
            const Gap(StrideSpace.s16),
            Text('explore_club_requests'.trArgs([pending.length]), style: StrideText.label),
            const Gap(StrideSpace.s8),
            for (final m in pending) _row(m, myRole, myUid),
          ],
          const Gap(StrideSpace.s16),
          Text('explore_club_members_count'.trArgs([club.memberCount]), style: StrideText.label),
          const Gap(StrideSpace.s8),
          if (shown.isEmpty) EmptyState(icon: Icons.search_off, title: 'explore_club_members_empty'.tr, message: 'explore_clubs_empty_message'.tr),
          for (final m in shown) _row(m, myRole, myUid),
          if (_cursor != null) ExploreLoadMore(loading: _loadingMore, onPressed: _more),
        ],
      ),
    );
  }

  Widget _row(ClubMember m, String myRole, String myUid) {
    final actions = availableMemberActions(myRole: myRole, myUid: myUid, target: m);
    final busy = _busy.contains(m.userId);
    return ListTile(
      key: Key('member-${m.userId}'),
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(_name(m), style: StrideText.body),
      subtitle: Text(_roleLabel(m), style: StrideText.caption),
      trailing: busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : m.isPending && actions.contains(MemberAction.approve)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => _act(m, MemberAction.reject), child: Text('explore_club_reject'.tr)),
                FilledButton(onPressed: () => _act(m, MemberAction.approve), child: Text('explore_club_approve'.tr)),
              ],
            )
          : actions.isEmpty
          ? null
          : PopupMenuButton<MemberAction>(
              key: Key('member-menu-${m.userId}'),
              tooltip: 'explore_club_member_actions'.tr,
              onSelected: (a) => _act(m, a),
              itemBuilder: (_) => [for (final a in actions) PopupMenuItem(value: a, child: Text(_actionLabel(a)))],
            ),
    );
  }

  String _roleLabel(ClubMember m) => m.isPending
      ? 'explore_club_request_pending'.tr
      : switch (m.role) {
          'owner' => 'explore_club_owner'.tr,
          'admin' => 'explore_club_admin'.tr,
          _ => 'explore_club_member'.tr,
        };

  String _actionLabel(MemberAction a) => switch (a) {
    MemberAction.approve => 'explore_club_approve'.tr,
    MemberAction.reject => 'explore_club_reject'.tr,
    MemberAction.makeAdmin => 'explore_club_make_admin'.tr,
    MemberAction.makeMember => 'explore_club_make_member'.tr,
    MemberAction.remove => 'explore_club_remove'.tr,
    MemberAction.ban => 'explore_club_ban'.tr,
    MemberAction.transferOwnership => 'explore_club_transfer'.tr,
  };
}
