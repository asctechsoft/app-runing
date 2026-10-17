import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";
import { ownerScope } from "./owner-scope";

export const notificationRepository = {
  create(data: { ownerId: string; kind: string; title: string; body: string; deepLink?: string | null }, db: Db = prisma) {
    return db.notificationItem.create({ data: { id: newId(), ...data } });
  },
  createMany(rows: Array<{ ownerId: string; kind: string; title: string; body: string; deepLink?: string | null }>, db: Db = prisma) {
    return db.notificationItem.createMany({ data: rows.map((r) => ({ id: newId(), ...r })) });
  },
  list(userId: string, cursor: { t: number; id: string } | null, limit: number, db: Db = prisma) {
    const at = cursor ? new Date(cursor.t) : null;
    return db.notificationItem.findMany({
      where: {
        ...ownerScope(userId),
        ...(at && cursor ? { OR: [{ createdAt: { lt: at } }, { createdAt: at, id: { lt: cursor.id } }] } : {}),
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });
  },
  countUnread(userId: string, db: Db = prisma) {
    return db.notificationItem.count({ where: ownerScope(userId, { readAt: null }) });
  },
  async markRead(userId: string, id: string, db: Db = prisma) {
    const row = await db.notificationItem.findFirst({ where: ownerScope(userId, { id }) });
    if (!row) return null;
    if (row.readAt) return row;
    return db.notificationItem.update({ where: { id: row.id }, data: { readAt: new Date() } });
  },
  markAllRead(userId: string, db: Db = prisma) {
    return db.notificationItem.updateMany({ where: ownerScope(userId, { readAt: null }), data: { readAt: new Date() } });
  },
  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.notificationItem.deleteMany({ where: ownerScope(userId) });
  },
};
