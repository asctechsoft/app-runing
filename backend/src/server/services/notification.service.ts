import type { NotificationItem } from "@prisma/client";
import { notFound } from "@/lib/errors";
import { notificationRepository } from "@/server/repositories/notification.repository";
import { decodeCursor, pageQuery, toPage } from "@/server/http/pagination";

export function toNotificationDto(n: NotificationItem) {
  return {
    id: n.id,
    kind: n.kind,
    title: n.title,
    body: n.body,
    deepLink: n.deepLink,
    createdAt: n.createdAt.getTime(),
    readAt: n.readAt?.getTime() ?? null,
  };
}

export const notificationService = {
  notify(ownerId: string, kind: string, title: string, body: string, deepLink?: string) {
    return notificationRepository.create({ ownerId, kind, title, body, deepLink: deepLink ?? null });
  },

  async list(userId: string, rawQuery: unknown) {
    const q = pageQuery.parse(rawQuery);
    const rows = await notificationRepository.list(userId, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (r) => r.createdAt);
    return {
      items: page.items.map(toNotificationDto),
      nextCursor: page.nextCursor,
      unreadCount: await notificationRepository.countUnread(userId),
    };
  },

  async markRead(userId: string, id: string) {
    const row = await notificationRepository.markRead(userId, id);
    if (!row) throw notFound("Notification");
    return toNotificationDto(row);
  },

  async markAllRead(userId: string) {
    const r = await notificationRepository.markAllRead(userId);
    return { updated: r.count };
  },
};
