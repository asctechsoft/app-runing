import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../values/routes.dart';
import '../../controller/providers.dart';
import '../../values/tokens.dart';
import '../common_components/widgets.dart';
import '../../repository/notification_repository.dart';
import '../../utils/l10n.dart';

/// Inbox thông báo (J02). Chạm → đánh dấu đã đọc và mở deep link (router áp auth guard).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsListProvider);
    final owner = ref.watch(ownerProvider).ownerId;
    final hasUnread = async.value?.any((n) => !n.isRead) ?? false;
    return StrideScreen(
      title: 'notifications_title'.tr,
      scroll: false,
      actions: [
        if (hasUnread) TextButton(onPressed: () => ref.read(notificationsRepositoryProvider).markAllRead(owner), child: Text('notifications_mark_all_read'.tr)),
        TextButton(onPressed: () => context.go(Routes.reminders), child: Text('notifications_manage'.tr)),
      ],
      body: async.when(
        loading: () => const Column(children: [Gap(16), LoadingCard(height: 72), Gap(12), LoadingCard(height: 72)]),
        error: (e, _) => ErrorState(
          title: 'notifications_error_title'.tr,
          message: 'notifications_error_message'.tr,
          onRetry: () => ref.invalidate(notificationsListProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.notifications_none,
                  title: 'notifications_empty_title'.tr,
                  message: 'notifications_empty_message'.tr,
                  actionLabel: 'notifications_manage_reminders'.tr,
                  onAction: () => context.go(Routes.reminders),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: StrideSpace.s12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Gap(StrideSpace.s8),
              itemBuilder: (context, i) => _NotificationTile(
                item: items[i],
                onTap: () async {
                  final n = items[i];
                  await ref.read(notificationsRepositoryProvider).markRead(owner, n.id);
                  if (!context.mounted) return;
                  final link = n.deepLink;
                  if (link != null && link.startsWith('/')) context.go(link);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});
  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final when = sameDay ? DateFormat.jm().format(t) : DateFormat('MMM d').format(t);
    return StrideCard(
      onTap: onTap,
      semanticLabel: '${item.isRead ? '' : 'notifications_unread_prefix'.tr}${item.title}. ${item.body}. $when',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: item.kind.contains('run') ? Icons.directions_run : Icons.notifications_none),
          const SizedBox(width: StrideSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title, style: StrideText.body.copyWith(fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600)),
                    ),
                    Text(when, style: StrideText.caption),
                  ],
                ),
                const Gap(StrideSpace.s4),
                Text(item.body, style: StrideText.bodySecondary),
                if (!item.isRead) ...[const Gap(StrideSpace.s4), Text('notifications_new'.tr, style: StrideText.label.copyWith(color: StrideColors.primary))],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
