import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/format/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'explore_models.dart';
import 'explore_repository.dart';
import 'explore_widgets.dart';

enum _ClubsTab { nearby, mine }

/// Running clubs (M02): Nearby theo vùng người dùng nhập (không xin vị trí), My clubs, tìm kiếm debounce.
class ClubsScreen extends ConsumerWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'Running clubs',
      scroll: false,
      body: !flags.exploreClubs
          ? const EmptyState(icon: Icons.groups_outlined, title: 'Clubs aren’t available', message: 'Running clubs aren’t turned on in this version.')
          : const ExploreGuestGate(
              title: 'Sign in to join clubs',
              message: 'Create an account or sign in to find clubs and run together.',
              child: _ClubsBody(),
            ),
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

  void _onQueryChanged(String _) => _debounce(() {
    if (mounted) _load();
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExploreHeader(title: 'Running clubs', subtitle: 'Find your people. Run further together.'),
        TextField(
          key: const Key('clubs-search'),
          controller: _search,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search clubs or interests'),
        ),
        const Gap(8),
        StrideSegmented<_ClubsTab>(
          values: _ClubsTab.values,
          selected: _tab,
          labelOf: (t) => t == _ClubsTab.nearby ? 'Nearby' : 'My clubs',
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
            decoration: const InputDecoration(prefixIcon: Icon(Icons.location_city_outlined), hintText: 'City or region, e.g. Hanoi'),
          ),
          const Gap(4),
          Text('We use the area you type. STRIDE doesn’t use your location to find clubs.', style: StrideText.caption),
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
                title: 'No clubs yet',
                message: 'Clubs you join will show here.',
                actionLabel: 'Find clubs',
                onAction: () {
                  setState(() => _tab = _ClubsTab.nearby);
                  _load();
                },
              )
            : const EmptyState(icon: Icons.search_off, title: 'No clubs found', message: 'Try another name or area.'),
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

String _membersLabel(int n) => n == 1 ? '1 member' : '${NumberFormat.decimalPattern().format(n)} members';

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
            member ? (m!.role == 'owner' ? 'Owner' : 'Member') : 'Request pending',
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

enum _DetailTab { feed, events }

class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    return StrideScreen(
      title: 'Club',
      body: !flags.exploreClubs
          ? const EmptyState(icon: Icons.groups_outlined, title: 'Clubs aren’t available', message: 'Running clubs aren’t turned on in this version.')
          : ExploreGuestGate(
              title: 'Sign in to join clubs',
              message: 'Create an account or sign in to see this club.',
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
    setState(() => _busy = true);
    try {
      final m = await ref.read(exploreRepositoryProvider).requestJoin(widget.clubId);
      if (!mounted) return;
      setState(() => _club = _club!.withMembership(m));
      showStrideSnack(context, m?.isMember == true ? 'You joined the club' : 'Request sent. A club admin will review it.');
    } catch (e) {
      if (mounted) showExploreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave({required bool pending}) async {
    final ok = await confirmDialog(
      context,
      title: pending ? 'Cancel join request?' : 'Leave ${_club!.name}?',
      message: pending ? 'You can request to join again later.' : 'You’ll stop seeing posts and events from this club.',
      confirmLabel: pending ? 'Cancel request' : 'Leave club',
      cancelLabel: 'Keep',
      destructive: !pending,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final m = await ref.read(exploreRepositoryProvider).leaveClub(widget.clubId);
      if (!mounted) return;
      setState(() => _club = _club!.withMembership(m));
      showStrideSnack(context, pending ? 'Request cancelled' : 'You left the club');
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
        if (c.description.isNotEmpty) ...[const Gap(12), Text(c.description, style: StrideText.body)],
        const Gap(16),
        if (member) ...[
          Row(
            children: [
              _MembershipChip(m),
              const Spacer(),
              if (!m!.isOwner) TextButton(onPressed: _busy ? null : () => _leave(pending: false), child: const Text('Leave club')),
            ],
          ),
          const Gap(8),
          StrideSegmented<_DetailTab>(
            values: _DetailTab.values,
            selected: _tab,
            labelOf: (t) => t == _DetailTab.feed ? 'Feed' : 'Events',
            onChanged: (t) => setState(() => _tab = t),
          ),
          const Gap(12),
          if (_tab == _DetailTab.feed) _ClubFeed(key: ValueKey('feed-${c.id}'), clubId: c.id) else _ClubEvents(key: ValueKey('events-${c.id}'), clubId: c.id),
        ] else if (pending) ...[
          const StatusBanner(
            tone: BannerTone.warning,
            title: 'Request pending',
            message: 'A club admin will review your request. You’ll be notified when it’s approved.',
          ),
          const Gap(12),
          SecondaryButton(label: 'Cancel request', onPressed: _busy ? null : () => _leave(pending: true)),
        ] else ...[
          PrimaryButton(label: 'Request to join', loading: _busy, onPressed: _busy ? null : _join),
          const Gap(8),
          Text('Posts and events are visible to approved members.', style: StrideText.caption, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feed (M03)
// ---------------------------------------------------------------------------

class _ClubFeed extends ConsumerStatefulWidget {
  const _ClubFeed({super.key, required this.clubId});
  final String clubId;

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
      if (!mounted) return;
      setState(() {
        _posts = more ? [...?_posts, ...page.items] : page.items;
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
        StrideCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Share something with the club', counterText: ''),
                ),
              ),
              IconButton(
                tooltip: 'Post',
                onPressed: _posting ? null : _post,
                icon: _posting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              ),
            ],
          ),
        ),
        const Gap(12),
        if (posts == null) ...[const LoadingCard(height: 160), const Gap(12), const LoadingCard(height: 160)],
        if (posts != null && posts.isEmpty)
          const EmptyState(icon: Icons.forum_outlined, title: 'No posts yet', message: 'Be the first to share a run or say hello.'),
        if (posts != null)
          for (final p in posts) ...[
            _PostCard(post: p, onChanged: _replace, onDeleted: () => _remove(p.id), onBlocked: () => _removeAuthor(p.authorId)),
            const Gap(12),
          ],
        if (_cursor != null) ExploreLoadMore(loading: _loadingMore, onPressed: () => _load(more: true)),
      ],
    );
  }
}

enum _PostAction { delete, reportPost, reportUser, block }

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({required this.post, required this.onChanged, required this.onDeleted, required this.onBlocked});
  final ClubPost post;
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
    final name = p.authorName ?? 'this runner';
    try {
      switch (a) {
        case _PostAction.delete:
          final ok = await confirmDialog(
            context,
            title: 'Delete post?',
            message: 'This removes the post and its comments for everyone.',
            confirmLabel: 'Delete',
            cancelLabel: 'Cancel',
            destructive: true,
          );
          if (!ok) return;
          await repo.deletePost(p.id);
          widget.onDeleted();
          if (mounted) showStrideSnack(context, 'Post deleted');
        case _PostAction.reportPost:
        case _PostAction.reportUser:
          final isUser = a == _PostAction.reportUser;
          final reason = await _askReason(context, isUser ? 'Report $name' : 'Report post');
          if (reason == null) return;
          await repo.report(targetType: isUser ? 'user' : 'post', targetId: isUser ? p.authorId : p.id, reason: reason);
          if (mounted) showStrideSnack(context, 'Report sent. Thanks for helping keep clubs safe.');
        case _PostAction.block:
          final ok = await confirmDialog(
            context,
            title: 'Block $name?',
            message: 'You won’t see each other’s posts, comments or activities in clubs.',
            confirmLabel: 'Block',
            cancelLabel: 'Cancel',
            destructive: true,
          );
          if (!ok) return;
          await repo.blockUser(p.authorId);
          widget.onBlocked();
          if (mounted) showStrideSnack(context, '$name is blocked');
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
                    Text(p.authorName ?? 'Runner', style: StrideText.label),
                    if (p.createdAt > 0) Text(DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(p.createdAt)), style: StrideText.caption),
                  ],
                ),
              ),
              PopupMenuButton<_PostAction>(
                tooltip: 'Post options',
                onSelected: _action,
                itemBuilder: (_) => [
                  if (mine) const PopupMenuItem(value: _PostAction.delete, child: Text('Delete post')),
                  if (!mine) ...[
                    const PopupMenuItem(value: _PostAction.reportPost, child: Text('Report post')),
                    const PopupMenuItem(value: _PostAction.reportUser, child: Text('Report user')),
                    const PopupMenuItem(value: _PostAction.block, child: Text('Block user')),
                  ],
                ],
              ),
            ],
          ),
          if (p.text.isNotEmpty) ...[const Gap(8), Text(p.text, style: StrideText.body)],
          if (p.activity != null) ...[const Gap(10), _ActivitySummary(a: p.activity!, fmt: fmt)],
          if (p.activityHidden) ...[const Gap(8), Text('This activity is no longer shared.', style: StrideText.caption)],
          const Gap(8),
          Row(
            children: [
              Semantics(
                button: true,
                label: p.cheeredByMe ? 'Remove cheer, ${p.cheerCount} cheers' : 'Cheer, ${p.cheerCount} cheers',
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: _cheering ? null : _cheer,
                  icon: Icon(p.cheeredByMe ? Icons.favorite : Icons.favorite_border, color: StrideColors.primary),
                  label: Text('${p.cheerCount}'),
                ),
              ),
              Semantics(
                button: true,
                label: 'Comments, ${p.commentCount}',
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
              if (!p.cheeredByMe) StrideChip(label: 'Cheer', icon: Icons.waving_hand_outlined, selected: false, onTap: _cheering ? null : _cheer),
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
          Text('Tell us what’s wrong. Reports are reviewed by the STRIDE team.', style: StrideText.bodySecondary),
          const Gap(12),
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reason'),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(8),
          PrimaryButton(label: 'Send report', onPressed: c.text.trim().isEmpty ? null : () => Navigator.of(ctx).pop(c.text.trim())),
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
              child: MetricTile(label: 'Distance', value: fmt.distanceValue(a.distanceM), unit: fmt.distanceUnitLabel, estimated: a.distanceEstimated),
            ),
            Expanded(
              child: MetricTile(label: 'Moving time', value: formatDuration(a.movingMs)),
            ),
            Expanded(
              child: MetricTile(
                label: 'Avg. pace',
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
      title: 'Delete comment?',
      message: 'This can’t be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
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
                const Expanded(child: Text('Comments', style: StrideText.heading)),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close)),
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
                  ? const Center(child: Text('No comments yet.', style: StrideText.bodySecondary))
                  : ListView(
                      children: [
                        for (final c in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.authorName ?? 'Runner', style: StrideText.label),
                            subtitle: Text(c.text, style: StrideText.body),
                            trailing: c.authorId == me
                                ? IconButton(tooltip: 'Delete comment', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c))
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
                    decoration: const InputDecoration(hintText: 'Add a comment', counterText: ''),
                  ),
                ),
                IconButton(tooltip: 'Send comment', onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
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
  const _ClubEvents({super.key, required this.clubId});
  final String clubId;

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
    setState(() => _busy.add(e.id));
    try {
      final updated = await ref.read(exploreRepositoryProvider).rsvp(e.id, going);
      if (!mounted) return;
      setState(() => _items = [for (final x in _items ?? const <ClubEvent>[]) x.id == e.id ? updated : x]);
      showStrideSnack(context, going ? 'You’re going' : 'RSVP cancelled');
    } catch (err) {
      if (mounted) showExploreError(context, err);
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ExploreFailureView(failure: _error!, onRetry: _load);
    final items = _items;
    if (items == null) return const Column(children: [LoadingCard(), Gap(12), LoadingCard()]);
    if (items.isEmpty) return const EmptyState(icon: Icons.event_outlined, title: 'No events yet', message: 'Club admins can schedule group runs here.');
    final now = ref.watch(clockProvider).nowMs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in items) ...[
          StrideCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: StrideText.subheading),
                const Gap(4),
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
                    Text(e.goingCount == 1 ? '1 going' : '${e.goingCount} going', style: StrideText.caption),
                    const Spacer(),
                    if (e.isCancelled)
                      Text('Cancelled', style: StrideText.label.copyWith(color: StrideColors.error))
                    else if (e.isPast(now))
                      Text('Ended', style: StrideText.label.copyWith(color: StrideColors.textMuted))
                    else if (e.going)
                      TextButton(onPressed: _busy.contains(e.id) ? null : () => _rsvp(e, false), child: const Text('Cancel RSVP'))
                    else
                      PrimaryButton(label: 'RSVP', expand: false, loading: _busy.contains(e.id), onPressed: _busy.contains(e.id) ? null : () => _rsvp(e, true)),
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
