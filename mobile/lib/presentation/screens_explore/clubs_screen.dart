import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../controller/explore/explore_logic.dart';
import '../../controller/providers.dart';
import '../../models/ui_models/explore_models.dart';
import '../../repository/explore_repository.dart';
import '../../services/application/reminder_scheduler.dart';
import '../../utils/analytics.dart';
import '../../utils/date_locale.dart';
import '../../utils/formatters.dart';
import '../../utils/l10n.dart';
import '../../values/routes.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import 'challenges_screen.dart';
import 'club_group_tab.dart';
import 'components/explore_widgets.dart';

enum _ClubsTab { nearby, mine }

/// Running clubs (M02): Nearby theo vùng người dùng nhập (không xin vị trí), My clubs, tìm kiếm debounce.
class ClubsScreen extends ConsumerWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'explore_clubs_title'.tr,
      scroll: false,
      body: !flags.exploreClubs
          ? EmptyState(icon: Icons.groups_outlined, title: 'explore_clubs_unavailable_title'.tr, message: 'explore_clubs_unavailable_message'.tr)
          : ExploreGuestGate(title: 'explore_clubs_guest_title'.tr, message: 'explore_clubs_guest_message'.tr, child: const _ClubsBody()),
    );
  }
}

class _ClubsBody extends ConsumerStatefulWidget {
  const _ClubsBody();

  @override
  ConsumerState<_ClubsBody> createState() => _ClubsBodyState();
}

class _ClubsBodyState extends ConsumerState<_ClubsBody> {
  final _search = TextEditingController();
  final _region = TextEditingController();
  final _debounce = Debouncer();
  _ClubsTab _tab = _ClubsTab.nearby;

  List<Club>? _items;
  String? _cursor;
  ExploreFailure? _error;
  bool _loading = false;
  bool _loadingMore = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    _search.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final id = ++_requestId;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    final repo = ref.read(exploreRepositoryProvider);
    try {
      if (_tab == _ClubsTab.mine) {
        final list = await repo.myClubs();
        final q = _search.text.trim().toLowerCase();
        if (id != _requestId || !mounted) return;
        setState(() {
          _items = q.isEmpty ? list : list.where((c) => c.name.toLowerCase().contains(q) || c.regionText.toLowerCase().contains(q)).toList();
          _cursor = null;
        });
      } else {
        final page = await repo.searchClubs(query: _search.text, region: _region.text, cursor: more ? _cursor : null);
        if (id != _requestId || !mounted) return;
        setState(() {
          _items = more ? [...?_items, ...page.items] : page.items;
          _cursor = page.nextCursor;
        });
      }
    } catch (e) {
      if (id != _requestId || !mounted) return;
      if (more) {
        showExploreError(context, e);
      } else {
        setState(() => _error = mapExploreError(e));
      }
    } finally {
      if (id == _requestId && mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  bool _joining = false;

  /// TM03: nhập mã mời → vào club (kể cả club riêng) → mở club.
  Future<void> _joinWithCode() async {
    if (_joining) return;
    final code = await showDialog<String>(context: context, builder: (_) => const _InviteCodeDialog());
    if (code == null || !mounted) return;
    setState(() => _joining = true);
    try {
      final id = await ref.read(exploreRepositoryProvider).joinWithCode(code);
      Analytics.clubJoin(via: 'invite_code');
      if (!mounted) return;
      showStrideSnack(context, 'explore_club_joined'.tr);
      await context.push(Routes.club(id));
      if (mounted) _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _onQueryChanged(String _) => _debounce(() {
    if (mounted) _load();
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExploreHeader(title: 'explore_clubs_title'.tr, subtitle: 'explore_clubs_subtitle'.tr),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('clubs-join-code'),
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text('explore_club_join_code'.tr),
              onPressed: _joinWithCode,
            ),
            TextButton.icon(
              key: const Key('clubs-create'),
              icon: const Icon(Icons.add),
              label: Text('explore_club_create'.tr),
              onPressed: () async {
                await context.push(Routes.clubCreate);
                if (mounted) _load();
              },
            ),
          ],
        ),
        TextField(
          key: const Key('clubs-search'),
          controller: _search,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'explore_clubs_search_hint'.tr),
        ),
        const Gap(8),
        StrideSegmented<_ClubsTab>(
          values: _ClubsTab.values,
          selected: _tab,
          labelOf: (t) => t == _ClubsTab.nearby ? 'explore_clubs_tab_nearby'.tr : 'explore_clubs_tab_mine'.tr,
          onChanged: (t) {
            if (t == _tab) return;
            setState(() {
              _tab = t;
              _items = null;
            });
            _load();
          },
        ),
        if (_tab == _ClubsTab.nearby) ...[
          const Gap(8),
          TextField(
            key: const Key('clubs-region'),
            controller: _region,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.location_city_outlined), hintText: 'explore_clubs_region_hint'.tr),
          ),
          const Gap(4),
          Text('explore_clubs_region_note'.tr, style: StrideText.caption),
        ],
        const Gap(8),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    if (_loading && _items == null) {
      return ListView(children: const [LoadingCard(height: 96), Gap(12), LoadingCard(height: 96), Gap(12), LoadingCard(height: 96)]);
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: ExploreFailureView(failure: _error!, onRetry: _load),
      );
    }
    final items = _items ?? const <Club>[];
    if (items.isEmpty) {
      return SingleChildScrollView(
        child: _tab == _ClubsTab.mine
            ? EmptyState(
                icon: Icons.groups_outlined,
                title: 'explore_clubs_mine_empty_title'.tr,
                message: 'explore_clubs_mine_empty_message'.tr,
                actionLabel: 'explore_clubs_find'.tr,
                onAction: () {
                  setState(() => _tab = _ClubsTab.nearby);
                  _load();
                },
              )
            : EmptyState(icon: Icons.search_off, title: 'explore_clubs_empty_title'.tr, message: 'explore_clubs_empty_message'.tr),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: items.length + (_cursor != null ? 1 : 0),
        separatorBuilder: (_, _) => const Gap(12),
        itemBuilder: (context, i) {
          if (i == items.length) return ExploreLoadMore(loading: _loadingMore, onPressed: () => _load(more: true));
          final c = items[i];
          return _ClubCard(
            club: c,
            onTap: () async {
              await context.push(Routes.club(c.id));
              if (mounted) _load();
            },
          );
        },
      ),
    );
  }
}

class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog();

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final c = normalizeInviteCode(_ctl.text);
    if (c == null) {
      setState(() => _error = 'explore_err_invite_invalid'.tr);
      return;
    }
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('explore_club_join_code'.tr),
    content: TextField(
      key: const Key('invite-code-input'),
      controller: _ctl,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(labelText: 'explore_club_invite_code'.tr, errorText: _error),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('action_cancel'.tr)),
      FilledButton(key: const Key('invite-code-submit'), onPressed: _submit, child: Text('explore_club_join'.tr)),
    ],
  );
}

String _membersLabel(int n) => 'explore_member'.trPlural(n, [NumberFormat.decimalPattern().format(n)]);

class _MembershipChip extends StatelessWidget {
  const _MembershipChip(this.m);
  final ClubMembership? m;

  @override
  Widget build(BuildContext context) {
    if (m == null || !(m!.isMember || m!.isPending)) return const SizedBox.shrink();
    final member = m!.isMember;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: member ? StrideColors.subtle : StrideColors.warningBg, borderRadius: BorderRadius.circular(StrideRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(member ? Icons.check : Icons.schedule, size: 14, color: member ? StrideColors.primary : StrideColors.warning),
          const SizedBox(width: 4),
          Text(
            member ? (m!.role == 'owner' ? 'explore_club_owner'.tr : 'explore_club_member'.tr) : 'explore_club_request_pending'.tr,
            style: StrideText.caption.copyWith(color: member ? StrideColors.primary : StrideColors.warning, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.onTap});
  final Club club;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => StrideCard(
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IconBadge(icon: Icons.groups_outlined, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(club.name, style: StrideText.subheading),
              Text(
                [if (club.regionText.isNotEmpty) club.regionText, _membersLabel(club.memberCount)].join(' · '),
                style: StrideText.caption.copyWith(fontSize: 13, color: StrideColors.textSecondary),
              ),
              if (club.description.isNotEmpty) ...[
                const Gap(4),
                Text(
                  club.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: StrideText.bodySecondary.copyWith(fontSize: 14, height: 20 / 14),
                ),
              ],
              const Gap(6),
              _MembershipChip(club.membership),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: StrideColors.textMuted),
      ],
    ),
  );
}

// =============================================================================
// Club detail (M02–M04)
// =============================================================================

enum _DetailTab { feed, events, challenges, group }

class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'explore_club_title'.tr,
      body: !flags.exploreClubs
          ? EmptyState(icon: Icons.groups_outlined, title: 'explore_clubs_unavailable_title'.tr, message: 'explore_clubs_unavailable_message'.tr)
          : ExploreGuestGate(
              title: 'explore_clubs_guest_title'.tr,
              message: 'explore_clubs_guest_detail_message'.tr,
              child: _ClubDetailBody(clubId: clubId),
            ),
    );
  }
}

class _ClubDetailBody extends ConsumerStatefulWidget {
  const _ClubDetailBody({required this.clubId});
  final String clubId;

  @override
  ConsumerState<_ClubDetailBody> createState() => _ClubDetailBodyState();
}

class _ClubDetailBodyState extends ConsumerState<_ClubDetailBody> {
  Club? _club;
  ExploreFailure? _error;
  bool _busy = false;
  _DetailTab _tab = _DetailTab.feed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await ref.read(exploreRepositoryProvider).club(widget.clubId);
      if (mounted) setState(() => _club = c);
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _join() async {
    if (_busy) return; // T04: hai lần chạm trong cùng frame
    setState(() => _busy = true);
    try {
      final m = await ref.read(exploreRepositoryProvider).requestJoin(widget.clubId);
      Analytics.clubJoin(via: m?.isMember == true ? 'public' : 'request');
      if (!mounted) return;
      setState(() => _club = _club!.withMembership(m));
      showStrideSnack(context, m?.isMember == true ? 'explore_club_joined'.tr : 'explore_club_request_sent'.tr);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// TM04: owner giải tán club (lưu trữ). Một chiều — hỏi xác nhận.
  Future<void> _archive() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'explore_club_archive_title'.trArgs([_club!.name]),
      message: 'explore_club_archive_message'.tr,
      confirmLabel: 'explore_club_archive'.tr,
      cancelLabel: 'explore_keep'.tr,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(exploreRepositoryProvider).archiveClub(widget.clubId);
      if (!mounted) return;
      showStrideSnack(context, 'explore_club_archived'.tr);
      _load();
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// TM03: tạo mã mời rồi mở bảng chia sẻ. Club riêng: chỉ owner/admin (rules chặn thành viên thường).
  Future<void> _invite() async {
    if (_busy) return;
    final c = _club!;
    if (c.isPrivate && c.membership?.canManage != true) {
      showStrideSnack(context, 'explore_club_invite_admin_only'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      final inv = await ref.read(exploreRepositoryProvider).createInvite(c.id);
      if (!mounted) return;
      final days = inviteDefaultTtl.inDays;
      final text = 'explore_club_invite_share'.trArgs([c.name, inv.code, days]);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('explore_club_invite_title'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(inv.code, key: const Key('invite-code'), style: StrideText.metricSmall.copyWith(letterSpacing: 2)),
              const Gap(8),
              Text('explore_club_invite_note'.trArgs([days, inviteDefaultMaxUses]), style: StrideText.caption),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common_close'.tr)),
            FilledButton(
              onPressed: () async {
                Analytics.clubInviteShare();
                await SharePlus.instance.share(ShareParams(text: text, subject: c.name));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('explore_club_invite_send'.tr),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave({required bool pending}) async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: pending ? 'explore_club_cancel_request_title'.tr : 'explore_club_leave_title'.trArgs([_club!.name]),
      message: pending ? 'explore_club_cancel_request_message'.tr : 'explore_club_leave_message'.tr,
      confirmLabel: pending ? 'explore_club_cancel_request'.tr : 'explore_club_leave'.tr,
      cancelLabel: 'explore_keep'.tr,
      destructive: !pending,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final m = await ref.read(exploreRepositoryProvider).leaveClub(widget.clubId);
      if (!mounted) return;
      setState(() => _club = _club!.withMembership(m));
      showStrideSnack(context, pending ? 'explore_club_request_cancelled'.tr : 'explore_club_left'.tr);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final c = _club;
    if (c == null) return const Column(children: [Gap(16), LoadingCard(height: 160), Gap(12), LoadingCard()]);
    final m = c.membership;
    final member = m?.isMember ?? false;
    final pending = m?.isPending ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(8),
        Row(
          children: [
            const IconBadge(icon: Icons.groups_outlined, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: StrideText.heading),
                  Text(
                    [if (c.regionText.isNotEmpty) c.regionText, _membersLabel(c.memberCount)].join(' · '),
                    style: StrideText.bodySecondary.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (c.archived) ...[const Gap(12), StatusBanner(key: const Key('club-archived'), tone: BannerTone.warning, message: 'explore_club_archived_banner'.tr)],
        if (c.description.isNotEmpty) ...[const Gap(12), Text(c.description, style: StrideText.body)],
        if (c.rulesText.isNotEmpty) ...[
          const Gap(12),
          StrideCard(
            key: const Key('club-rules-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('explore_club_rules'.tr, style: StrideText.label),
                const Gap(4),
                Text(c.rulesText, style: StrideText.body),
              ],
            ),
          ),
        ],
        const Gap(16),
        if (member) ...[
          // Wrap: chữ dài (vi) hoặc cỡ chữ lớn thì nút xuống dòng thay vì tràn.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              _MembershipChip(m),
              TextButton(
                key: const Key('club-members'),
                onPressed: () async {
                  await context.push(Routes.clubMembers(c.id));
                  if (mounted) _load();
                },
                child: Text(m!.canManage ? 'explore_club_manage_members'.tr : 'explore_club_members_title'.tr),
              ),
              if (!c.archived) TextButton(key: const Key('club-invite'), onPressed: _busy ? null : _invite, child: Text('explore_club_invite'.tr)),
              if (m.canManage && !c.archived)
                TextButton(
                  key: const Key('club-edit'),
                  onPressed: () async {
                    final changed = await context.push<bool>(Routes.clubEdit(c.id));
                    if (changed == true && mounted) _load();
                  },
                  child: Text('explore_club_edit'.tr),
                ),
              if (!m.isOwner) TextButton(onPressed: _busy ? null : () => _leave(pending: false), child: Text('explore_club_leave'.tr)),
              if (m.isOwner && !c.archived)
                TextButton(
                  key: const Key('club-archive'),
                  onPressed: _busy ? null : _archive,
                  child: Text('explore_club_archive'.tr, style: StrideText.label.copyWith(color: StrideColors.error)),
                ),
            ],
          ),
          const Gap(8),
          StrideSegmented<_DetailTab>(
            values: [_DetailTab.feed, _DetailTab.events, if (ref.watch(flagsProvider).exploreChallenges) _DetailTab.challenges, _DetailTab.group],
            selected: _tab,
            labelOf: (t) => switch (t) {
              _DetailTab.feed => 'explore_club_tab_feed'.tr,
              _DetailTab.events => 'explore_club_tab_events'.tr,
              _DetailTab.challenges => 'explore_club_tab_challenges'.tr,
              _DetailTab.group => 'explore_club_tab_group'.tr,
            },
            onChanged: (t) => setState(() => _tab = t),
          ),
          const Gap(12),
          switch (_tab) {
            _DetailTab.feed => _ClubFeed(
              key: ValueKey('feed-${c.id}-${c.pinnedPostId}'),
              clubId: c.id,
              archived: c.archived,
              pinnedPostId: c.pinnedPostId,
              canManage: m.canManage && !c.archived,
              onPinChanged: _load,
            ),
            _DetailTab.events => _ClubEvents(key: ValueKey('events-${c.id}'), clubId: c.id, myRole: c.archived ? 'member' : m.role),
            _DetailTab.challenges => ChallengeList(key: ValueKey('challenges-${c.id}'), clubId: c.id, canCreate: m.canManage),
            _DetailTab.group => ClubGroupTab(key: ValueKey('group-${c.id}-${c.groupGoal?.toMap()}'), club: c, canManage: m.canManage, onGoalChanged: _load),
          },
        ] else if (pending) ...[
          StatusBanner(tone: BannerTone.warning, title: 'explore_club_request_pending'.tr, message: 'explore_club_request_pending_message'.tr),
          const Gap(12),
          SecondaryButton(label: 'explore_club_cancel_request'.tr, onPressed: _busy ? null : () => _leave(pending: true)),
        ] else ...[
          PrimaryButton(label: 'explore_club_request_join'.tr, loading: _busy, onPressed: _busy ? null : _join),
          const Gap(8),
          Text('explore_club_members_only_note'.tr, style: StrideText.caption, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feed (M03)
// ---------------------------------------------------------------------------

class _ClubFeed extends ConsumerStatefulWidget {
  const _ClubFeed({super.key, required this.clubId, this.archived = false, this.pinnedPostId, this.canManage = false, this.onPinChanged});
  final String clubId;

  /// TM04: bài ghim (hiện đầu feed) và quyền ghim (owner/admin).
  final String? pinnedPostId;
  final bool canManage;
  final VoidCallback? onPinChanged;

  /// TM04: club đã giải tán → chỉ xem, không đăng bài.
  final bool archived;

  @override
  ConsumerState<_ClubFeed> createState() => _ClubFeedState();
}

class _ClubFeedState extends ConsumerState<_ClubFeed> {
  List<ClubPost>? _posts;
  String? _cursor;
  ExploreFailure? _error;
  bool _loadingMore = false;
  final _composer = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) setState(() => _loadingMore = true);
    if (!more) setState(() => _error = null);
    try {
      final page = await ref.read(exploreRepositoryProvider).posts(widget.clubId, cursor: more ? _cursor : null);
      // TM04: bài ghim ở đầu trang đầu; các trang sau bỏ bản trùng.
      final items = more
          ? [
              ...?_posts,
              for (final x in page.items)
                if (x.id != widget.pinnedPostId) x,
            ]
          : await _withPinned(page.items);
      if (!mounted) return;
      setState(() {
        _posts = items;
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (!mounted) return;
      if (more) {
        showExploreError(context, e);
      } else {
        setState(() => _error = mapExploreError(e));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _pin(String? postId) async {
    await ref.read(exploreRepositoryProvider).setPinnedPost(widget.clubId, postId);
    if (!mounted) return;
    showStrideSnack(context, postId == null ? 'explore_post_unpinned'.tr : 'explore_post_pinned_snack'.tr);
    widget.onPinChanged?.call();
  }

  /// Bài ghim lên đầu (lấy riêng nếu không có trong trang đầu; đã xóa thì bỏ qua).
  Future<List<ClubPost>> _withPinned(List<ClubPost> page) async {
    final id = widget.pinnedPostId;
    if (id == null) return page;
    final inPage = page.where((x) => x.id == id).firstOrNull;
    final pinned = inPage ?? await ref.read(exploreRepositoryProvider).post(id).catchError((_) => null);
    if (pinned == null) return page;
    return [
      pinned,
      for (final x in page)
        if (x.id != id) x,
    ];
  }

  void _replace(ClubPost p) => setState(() => _posts = [for (final x in _posts ?? const <ClubPost>[]) x.id == p.id ? p : x]);
  void _remove(String id) => setState(
    () => _posts = [
      for (final x in _posts ?? const <ClubPost>[])
        if (x.id != id) x,
    ],
  );
  void _removeAuthor(String authorId) => setState(
    () => _posts = [
      for (final x in _posts ?? const <ClubPost>[])
        if (x.authorId != authorId) x,
    ],
  );

  Future<void> _post() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final p = await ref.read(exploreRepositoryProvider).createPost(widget.clubId, text: text);
      if (!mounted) return;
      _composer.clear();
      setState(() => _posts = [p, ...?_posts]);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final posts = _posts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.archived)
          StrideCard(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(hintText: 'explore_feed_composer_hint'.tr, counterText: ''),
                  ),
                ),
                IconButton(
                  tooltip: 'explore_feed_post'.tr,
                  onPressed: _posting ? null : _post,
                  icon: _posting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        const Gap(12),
        if (posts == null) ...[const LoadingCard(height: 160), const Gap(12), const LoadingCard(height: 160)],
        if (posts != null && posts.isEmpty)
          EmptyState(icon: Icons.forum_outlined, title: 'explore_feed_empty_title'.tr, message: 'explore_feed_empty_message'.tr),
        if (posts != null)
          for (final p in posts) ...[
            _PostCard(
              key: ValueKey('post-${p.id}'),
              post: p,
              pinned: p.id == widget.pinnedPostId,
              onPin: widget.canManage ? (pin) => _pin(pin ? p.id : null) : null,
              onChanged: _replace,
              onDeleted: () => _remove(p.id),
              onBlocked: () => _removeAuthor(p.authorId),
            ),
            const Gap(12),
          ],
        if (_cursor != null) ExploreLoadMore(loading: _loadingMore, onPressed: () => _load(more: true)),
      ],
    );
  }
}

enum _PostAction { delete, reportPost, reportUser, block, pin, unpin }

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({super.key, required this.post, required this.onChanged, required this.onDeleted, required this.onBlocked, this.pinned = false, this.onPin});
  final ClubPost post;

  /// TM04: bài đang ghim; [onPin] khác null = tôi ghim/bỏ ghim được.
  final bool pinned;
  final Future<void> Function(bool pin)? onPin;
  final ValueChanged<ClubPost> onChanged;
  final VoidCallback onDeleted;
  final VoidCallback onBlocked;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  bool _cheering = false;

  Future<void> _cheer() async {
    if (_cheering) return;
    setState(() => _cheering = true);
    try {
      final p = await ref.read(exploreRepositoryProvider).cheer(widget.post.id, !widget.post.cheeredByMe);
      widget.onChanged(p);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _cheering = false);
    }
  }

  Future<void> _action(_PostAction a) async {
    final repo = ref.read(exploreRepositoryProvider);
    final p = widget.post;
    final name = p.authorName ?? 'explore_this_runner'.tr;
    try {
      switch (a) {
        case _PostAction.pin || _PostAction.unpin:
          await widget.onPin?.call(a == _PostAction.pin);
        case _PostAction.delete:
          final ok = await confirmDialog(
            context,
            title: 'explore_post_delete_title'.tr,
            message: 'explore_post_delete_message'.tr,
            confirmLabel: 'explore_delete'.tr,
            cancelLabel: 'action_cancel'.tr,
            destructive: true,
          );
          if (!ok) return;
          await repo.deletePost(p.id);
          widget.onDeleted();
          if (mounted) showStrideSnack(context, 'explore_post_deleted'.tr);
        case _PostAction.reportPost:
        case _PostAction.reportUser:
          final isUser = a == _PostAction.reportUser;
          final reason = await _askReason(context, isUser ? 'explore_report_user_title'.trArgs([name]) : 'explore_report_post'.tr);
          if (reason == null) return;
          await repo.report(targetType: isUser ? 'user' : 'post', targetId: isUser ? p.authorId : p.id, reason: reason);
          if (mounted) showStrideSnack(context, 'explore_report_sent'.tr);
        case _PostAction.block:
          final ok = await confirmDialog(
            context,
            title: 'explore_block_title'.trArgs([name]),
            message: 'explore_block_message'.tr,
            confirmLabel: 'explore_block'.tr,
            cancelLabel: 'action_cancel'.tr,
            destructive: true,
          );
          if (!ok) return;
          await repo.blockUser(p.authorId);
          widget.onBlocked();
          if (mounted) showStrideSnack(context, 'explore_blocked'.trArgs([name]));
      }
    } catch (e) {
      if (mounted) showExploreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final me = ref.watch(ownerProvider).ownerId;
    final mine = p.authorId == me;
    final fmt = ref.watch(formatProvider);
    return StrideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: StrideColors.subtle,
                child: Text(
                  (p.authorName?.trim().isNotEmpty ?? false) ? p.authorName!.trim()[0].toUpperCase() : '?',
                  style: StrideText.label.copyWith(color: StrideColors.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.authorName ?? 'explore_runner'.tr, style: StrideText.label),
                    if (p.createdAt > 0) Text(AppDates.monthDayTime(DateTime.fromMillisecondsSinceEpoch(p.createdAt)), style: StrideText.caption),
                  ],
                ),
              ),
              PopupMenuButton<_PostAction>(
                tooltip: 'explore_post_options'.tr,
                onSelected: _action,
                itemBuilder: (_) => [
                  if (widget.onPin != null)
                    PopupMenuItem(
                      value: widget.pinned ? _PostAction.unpin : _PostAction.pin,
                      child: Text(widget.pinned ? 'explore_post_unpin'.tr : 'explore_post_pin'.tr),
                    ),
                  if (mine) PopupMenuItem(value: _PostAction.delete, child: Text('explore_post_delete'.tr)),
                  if (!mine) ...[
                    PopupMenuItem(value: _PostAction.reportPost, child: Text('explore_report_post'.tr)),
                    PopupMenuItem(value: _PostAction.reportUser, child: Text('explore_report_user'.tr)),
                    PopupMenuItem(value: _PostAction.block, child: Text('explore_block_user'.tr)),
                  ],
                ],
              ),
            ],
          ),
          if (widget.pinned) ...[
            const Gap(6),
            Row(
              key: const Key('post-pinned'),
              children: [
                const Icon(Icons.push_pin_outlined, size: 16, color: StrideColors.primary),
                const SizedBox(width: 4),
                Text('explore_post_pinned'.tr, style: StrideText.caption.copyWith(color: StrideColors.primary)),
              ],
            ),
          ],
          if (p.text.isNotEmpty) ...[const Gap(8), Text(p.text, style: StrideText.body)],
          if (p.activity != null) ...[const Gap(10), _ActivitySummary(a: p.activity!, fmt: fmt)],
          if (p.activityHidden) ...[const Gap(8), Text('explore_post_activity_hidden'.tr, style: StrideText.caption)],
          const Gap(8),
          Row(
            children: [
              Semantics(
                button: true,
                label: p.cheeredByMe ? 'explore_cheer_remove_label'.trArgs([p.cheerCount]) : 'explore_cheer_label'.trArgs([p.cheerCount]),
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: _cheering ? null : _cheer,
                  icon: Icon(p.cheeredByMe ? Icons.favorite : Icons.favorite_border, color: StrideColors.primary),
                  label: Text('${p.cheerCount}'),
                ),
              ),
              Semantics(
                button: true,
                label: 'explore_comments_label'.trArgs([p.commentCount]),
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () async {
                    var delta = 0;
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => _CommentsSheet(postId: p.id, onDelta: (d) => delta += d),
                    );
                    if (delta != 0) {
                      widget.onChanged(
                        ClubPost(
                          id: p.id,
                          clubId: p.clubId,
                          authorId: p.authorId,
                          authorName: p.authorName,
                          text: p.text,
                          activity: p.activity,
                          activityHidden: p.activityHidden,
                          commentCount: (p.commentCount + delta).clamp(0, 1 << 30),
                          cheerCount: p.cheerCount,
                          cheeredByMe: p.cheeredByMe,
                          createdAt: p.createdAt,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.chat_bubble_outline, color: StrideColors.primary),
                  label: Text('${p.commentCount}'),
                ),
              ),
              const Spacer(),
              if (!p.cheeredByMe) StrideChip(label: 'explore_cheer'.tr, icon: Icons.waving_hand_outlined, selected: false, onTap: _cheering ? null : _cheer),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String title) {
  final c = TextEditingController();
  return showStrideSheet<String>(
    context,
    title: title,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('explore_report_prompt'.tr, style: StrideText.bodySecondary),
          const Gap(12),
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: 'explore_report_reason'.tr),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(8),
          PrimaryButton(label: 'explore_report_send'.tr, onPressed: c.text.trim().isEmpty ? null : () => Navigator.of(ctx).pop(c.text.trim())),
        ],
      ),
    ),
  );
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.a, required this.fmt});
  final PostActivity a;
  final StrideFormat fmt;

  @override
  Widget build(BuildContext context) => SageCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.title != null && a.title!.isNotEmpty) ...[Text(a.title!, style: StrideText.label), const Gap(8)],
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'explore_distance'.tr,
                value: fmt.distanceValue(a.distanceM),
                unit: fmt.distanceUnitLabel,
                estimated: a.distanceEstimated,
              ),
            ),
            Expanded(
              child: MetricTile(label: 'explore_moving_time'.tr, value: formatDuration(a.movingMs)),
            ),
            Expanded(
              child: MetricTile(
                label: 'explore_avg_pace'.tr,
                // Pace từ quãng đường ước tính theo bước không đáng tin → —.
                value: a.distanceEstimated ? missingValue : fmt.paceValue(a.avgPaceSecPerKm),
                unit: a.distanceEstimated ? null : fmt.paceUnitLabel,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId, required this.onDelta});
  final String postId;
  final ValueChanged<int> onDelta;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  List<PostComment>? _items;
  String? _cursor;
  ExploreFailure? _error;
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final page = await ref.read(exploreRepositoryProvider).comments(widget.postId, cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...page.items] : page.items;
        _cursor = page.nextCursor;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await ref.read(exploreRepositoryProvider).addComment(widget.postId, t);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _items = [...?_items, c];
      });
      widget.onDelta(1);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(PostComment c) async {
    final ok = await confirmDialog(
      context,
      title: 'explore_comment_delete_title'.tr,
      message: 'explore_comment_delete_message'.tr,
      confirmLabel: 'explore_delete'.tr,
      cancelLabel: 'action_cancel'.tr,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(exploreRepositoryProvider).deleteComment(c.id, postId: c.postId);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final x in _items ?? const <PostComment>[])
            if (x.id != c.id) x,
        ];
      });
      widget.onDelta(-1);
    } catch (e) {
      if (mounted) showExploreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(ownerProvider).ownerId;
    final items = _items;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.viewInsetsOf(context).bottom + 12),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('explore_comments'.tr, style: StrideText.heading)),
                IconButton(tooltip: 'explore_close'.tr, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close)),
              ],
            ),
            Expanded(
              child: _error != null
                  ? SingleChildScrollView(
                      child: ExploreFailureView(failure: _error!, onRetry: _load),
                    )
                  : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? Center(child: Text('explore_comments_empty'.tr, style: StrideText.bodySecondary))
                  : ListView(
                      children: [
                        for (final c in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.authorName ?? 'explore_runner'.tr, style: StrideText.label),
                            subtitle: Text(c.text, style: StrideText.body),
                            trailing: c.authorId == me
                                ? IconButton(tooltip: 'explore_comment_delete'.tr, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c))
                                : null,
                          ),
                        if (_cursor != null) ExploreLoadMore(loading: false, onPressed: () => _load(more: true)),
                      ],
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 1000,
                    decoration: InputDecoration(hintText: 'explore_comment_hint'.tr, counterText: ''),
                  ),
                ),
                IconButton(tooltip: 'explore_comment_send'.tr, onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Events (M04)
// ---------------------------------------------------------------------------

class _ClubEvents extends ConsumerStatefulWidget {
  const _ClubEvents({super.key, required this.clubId, required this.myRole});
  final String clubId;

  /// Vai trò của tôi trong club (TM05: owner/admin tạo sự kiện).
  final String myRole;

  @override
  ConsumerState<_ClubEvents> createState() => _ClubEventsState();
}

class _ClubEventsState extends ConsumerState<_ClubEvents> {
  List<ClubEvent>? _items;
  String? _cursor;
  ExploreFailure? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final page = await ref.read(exploreRepositoryProvider).events(widget.clubId, cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...page.items] : page.items;
        _cursor = page.nextCursor;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  Future<void> _rsvp(ClubEvent e, bool going) async {
    if (_busy.contains(e.id)) return; // T04
    setState(() => _busy.add(e.id));
    try {
      final updated = await ref.read(exploreRepositoryProvider).rsvp(e.id, going);
      if (!mounted) return;
      setState(() => _items = [for (final x in _items ?? const <ClubEvent>[]) x.id == e.id ? updated : x]);
      showStrideSnack(context, going ? 'explore_event_going_snack'.tr : 'explore_event_rsvp_cancelled'.tr);
      // TM05: đặt lại nhắc 1 ngày / 1 giờ trước sự kiện đã đăng ký.
      unawaited(ref.read(remindersSyncProvider)().catchError((_) {}));
    } catch (err) {
      if (mounted) showExploreError(context, err);
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
  }

  Future<void> _open(String route) async {
    final changed = await context.push<bool>(route);
    if (changed == true && mounted) _load();
  }

  Future<void> _cancel(ClubEvent e) async {
    final ok = await confirmDialog(
      context,
      title: 'explore_event_cancel_title'.tr,
      message: 'explore_event_cancel_message'.tr,
      confirmLabel: 'explore_event_cancel'.tr,
      cancelLabel: 'explore_keep'.tr,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(exploreRepositoryProvider).cancelEvent(e.id);
      if (!mounted) return;
      showStrideSnack(context, 'explore_event_cancelled_snack'.tr);
      _load();
      unawaited(ref.read(remindersSyncProvider)().catchError((_) {}));
    } catch (err) {
      if (mounted) showExploreError(context, err);
    }
  }

  Future<void> _attendees(ClubEvent e) => showStrideSheet<void>(
    context,
    title: 'explore_event_attendees_title'.tr,
    builder: (_) => _EventAttendees(eventId: e.id),
  );

  /// TM05: thêm vào lịch qua tệp `.ics` (ứng dụng lịch của máy mở được) — không cần quyền lịch.
  Future<void> _addToCalendar(ClubEvent e) async {
    final ics = eventIcs(
      id: e.id,
      title: e.title,
      description: e.description,
      location: e.meetingPlace,
      startsAt: e.startAt,
      endsAt: e.endAt,
      nowMs: ref.read(clockProvider).nowMs(),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(utf8.encode(ics), mimeType: 'text/calendar', name: 'event.ics')],
        subject: e.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Column(children: [LoadingCard(), Gap(12), LoadingCard()]);
    final isManager = widget.myRole == 'owner' || widget.myRole == 'admin';
    final createButton = isManager
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlineButton(
              key: const Key('event-create'),
              label: 'explore_event_create'.tr,
              icon: Icons.add,
              onPressed: () => _open(Routes.clubEventCreate(widget.clubId)),
            ),
          )
        : null;
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?createButton,
          EmptyState(icon: Icons.event_outlined, title: 'explore_events_empty_title'.tr, message: 'explore_events_empty_message'.tr),
        ],
      );
    }
    final now = ref.watch(clockProvider).nowMs();
    final myUid = ref.watch(ownerProvider).ownerId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?createButton,
        for (final e in items) ...[
          StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.title, style: StrideText.subheading)),
                    PopupMenuButton<String>(
                      key: Key('event-menu-${e.id}'),
                      tooltip: 'activity_more_options'.tr,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) => switch (v) {
                        'edit' => _open(Routes.clubEventEdit(widget.clubId, e.id)),
                        'cancel' => _cancel(e),
                        'attendees' => _attendees(e),
                        _ => _addToCalendar(e),
                      },
                      itemBuilder: (_) {
                        final manage = canManageEvent(createdBy: e.createdBy, myUid: myUid, myRole: widget.myRole);
                        final upcoming = !e.isCancelled && e.startAt > now;
                        return [
                          PopupMenuItem(value: 'attendees', child: Text('explore_event_attendees_title'.tr)),
                          if (upcoming) PopupMenuItem(value: 'calendar', child: Text('explore_event_add_calendar'.tr)),
                          if (manage && upcoming) PopupMenuItem(value: 'edit', child: Text('explore_club_edit'.tr)),
                          if (manage && !e.isCancelled) PopupMenuItem(value: 'cancel', child: Text('explore_event_cancel'.tr)),
                        ];
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: StrideColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(formatInZone(e.startAt, e.tzId), style: StrideText.bodySecondary.copyWith(fontSize: 14))),
                  ],
                ),
                if (e.meetingPlace.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: StrideColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.meetingPlace, style: StrideText.bodySecondary.copyWith(fontSize: 14))),
                    ],
                  ),
                if (e.description.isNotEmpty) ...[const Gap(6), Text(e.description, style: StrideText.body)],
                const Gap(8),
                Row(
                  children: [
                    Text(
                      e.maxGoing == null ? 'explore_going'.trPlural(e.goingCount, [e.goingCount]) : 'explore_event_going_of'.trArgs([e.goingCount, e.maxGoing]),
                      style: StrideText.caption,
                    ),
                    const Spacer(),
                    if (e.isCancelled)
                      Text('explore_event_cancelled'.tr, style: StrideText.label.copyWith(color: StrideColors.error))
                    else if (e.isPast(now))
                      Text('explore_event_ended'.tr, style: StrideText.label.copyWith(color: StrideColors.textMuted))
                    else if (e.going)
                      TextButton(onPressed: _busy.contains(e.id) ? null : () => _rsvp(e, false), child: Text('explore_event_cancel_rsvp'.tr))
                    else if (eventFull(goingCount: e.goingCount, maxGoing: e.maxGoing))
                      Text('explore_err_event_full'.tr, style: StrideText.label.copyWith(color: StrideColors.textMuted))
                    else
                      PrimaryButton(
                        label: 'explore_event_rsvp'.tr,
                        expand: false,
                        loading: _busy.contains(e.id),
                        onPressed: _busy.contains(e.id) ? null : () => _rsvp(e, true),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(12),
        ],
        if (_cursor != null) ExploreLoadMore(loading: false, onPressed: () => _load(more: true)),
      ],
    );
  }
}

/// TM05: danh sách người đã đăng ký (tên hiển thị lúc đăng ký; người tôi chặn bị ẩn).
class _EventAttendees extends ConsumerStatefulWidget {
  const _EventAttendees({required this.eventId});
  final String eventId;

  @override
  ConsumerState<_EventAttendees> createState() => _EventAttendeesState();
}

class _EventAttendeesState extends ConsumerState<_EventAttendees> {
  List<EventAttendee>? _items;
  ExploreFailure? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await ref.read(exploreRepositoryProvider).eventAttendees(widget.eventId);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = mapExploreError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const LoadingCard(height: 120);
    if (items.isEmpty) {
      return EmptyState(icon: Icons.people_outline, title: 'explore_event_attendees_empty'.tr, message: 'explore_event_attendees_empty_message'.tr);
    }
    return Column(
      children: [
        for (final a in items)
          ListTile(
            key: Key('attendee-${a.userId}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(a.displayName.trim().isEmpty ? 'explore_event_attendee_unnamed'.tr : a.displayName, style: StrideText.body),
          ),
      ],
    );
  }
}
