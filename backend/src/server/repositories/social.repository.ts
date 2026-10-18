import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";

type Cursor = { t: number; id: string } | null;
const after = (cursor: Cursor, field: "createdAt" | "startAt" = "createdAt") =>
  cursor ? { OR: [{ [field]: { lt: new Date(cursor.t) } }, { [field]: new Date(cursor.t), id: { lt: cursor.id } }] } : {};

export const clubRepository = {
  search(
    q: { text?: string; region?: string; box?: { minLat: number; maxLat: number; minLon: number; maxLon: number } },
    cursor: Cursor,
    limit: number,
    db: Db = prisma,
  ) {
    const and: Prisma.ClubWhereInput[] = [];
    if (q.text) and.push({ searchText: { contains: q.text.toLowerCase() } });
    if (q.region) and.push({ searchText: { contains: q.region.toLowerCase() } });
    if (q.box) {
      and.push({ lat: { gte: q.box.minLat, lte: q.box.maxLat }, lon: { gte: q.box.minLon, lte: q.box.maxLon } });
    }
    if (cursor) and.push(after(cursor) as Prisma.ClubWhereInput);
    return db.club.findMany({ where: { AND: and }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: limit + 1 });
  },
  find(id: string, db: Db = prisma) {
    return db.club.findUnique({ where: { id } });
  },
  findMany(ids: string[], db: Db = prisma) {
    return db.club.findMany({ where: { id: { in: ids } } });
  },
  create(data: Prisma.ClubUncheckedCreateInput, db: Db = prisma) {
    return db.club.create({ data });
  },
  memberCounts(clubIds: string[], db: Db = prisma) {
    return db.membership.groupBy({ by: ["clubId"], where: { clubId: { in: clubIds }, status: "approved" }, _count: { _all: true } });
  },
  listOwnedBy(userId: string, db: Db = prisma) {
    return db.club.findMany({ where: { ownerId: userId }, select: { id: true } });
  },
  deleteMany(ids: string[], db: Db = prisma) {
    return db.club.deleteMany({ where: { id: { in: ids } } });
  },
};

export const membershipRepository = {
  find(clubId: string, userId: string, db: Db = prisma) {
    return db.membership.findUnique({ where: { clubId_userId: { clubId, userId } } });
  },
  findManyForUser(userId: string, clubIds: string[], db: Db = prisma) {
    return db.membership.findMany({ where: { userId, clubId: { in: clubIds } } });
  },
  listApprovedForUser(userId: string, db: Db = prisma) {
    return db.membership.findMany({ where: { userId, status: "approved" }, orderBy: { createdAt: "desc" } });
  },
  listPending(clubId: string, db: Db = prisma) {
    return db.membership.findMany({ where: { clubId, status: "pending" }, orderBy: { createdAt: "asc" }, take: 200 });
  },
  listModerators(clubId: string, db: Db = prisma) {
    return db.membership.findMany({ where: { clubId, status: "approved", role: { in: ["owner", "mod"] } } });
  },
  create(data: { clubId: string; userId: string; role: string; status: string }, db: Db = prisma) {
    return db.membership.create({ data: { id: newId(), ...data } });
  },
  update(clubId: string, userId: string, data: Prisma.MembershipUpdateInput, db: Db = prisma) {
    return db.membership.update({ where: { clubId_userId: { clubId, userId } }, data });
  },
  /** J04: hai người cùng là thành viên đã duyệt của ít nhất một club. */
  async shareApprovedClub(userA: string, userB: string, db: Db = prisma) {
    const m = await db.membership.findFirst({
      where: { userId: userA, status: "approved", club: { memberships: { some: { userId: userB, status: "approved" } } } },
      select: { id: true },
    });
    return m !== null;
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return db.membership.deleteMany({ where: { userId } });
  },
};

export const postRepository = {
  find(id: string, db: Db = prisma) {
    return db.clubPost.findFirst({ where: { id, deletedAt: null } });
  },
  findAny(id: string, db: Db = prisma) {
    return db.clubPost.findUnique({ where: { id } });
  },
  list(clubId: string, excludeAuthors: string[], cursor: Cursor, limit: number, db: Db = prisma) {
    return db.clubPost.findMany({
      where: { clubId, deletedAt: null, authorId: { notIn: excludeAuthors }, ...after(cursor) },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });
  },
  create(data: { id: string; clubId: string; authorId: string; activityId: string | null; text: string }, db: Db = prisma) {
    return db.clubPost.create({ data });
  },
  softDelete(id: string, db: Db = prisma) {
    return db.clubPost.update({ where: { id }, data: { deletedAt: new Date() } });
  },
  commentCounts(postIds: string[], db: Db = prisma) {
    return db.comment.groupBy({ by: ["postId"], where: { postId: { in: postIds }, deletedAt: null }, _count: { _all: true } });
  },
  cheerCounts(postIds: string[], db: Db = prisma) {
    return db.cheer.groupBy({ by: ["postId"], where: { postId: { in: postIds } }, _count: { _all: true } });
  },
  cheeredBy(userId: string, postIds: string[], db: Db = prisma) {
    return db.cheer.findMany({ where: { userId, postId: { in: postIds } }, select: { postId: true } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return Promise.all([
      db.clubPost.deleteMany({ where: { authorId: userId } }),
      db.comment.deleteMany({ where: { authorId: userId } }),
      db.cheer.deleteMany({ where: { userId } }),
      db.report.deleteMany({ where: { reporterId: userId } }),
    ]);
  },
};

export const commentRepository = {
  find(id: string, db: Db = prisma) {
    return db.comment.findFirst({ where: { id, deletedAt: null } });
  },
  list(postId: string, excludeAuthors: string[], cursor: Cursor, limit: number, db: Db = prisma) {
    return db.comment.findMany({
      where: { postId, deletedAt: null, authorId: { notIn: excludeAuthors }, ...after(cursor) },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });
  },
  create(data: { postId: string; authorId: string; text: string }, db: Db = prisma) {
    return db.comment.create({ data: { id: newId(), ...data } });
  },
  softDelete(id: string, db: Db = prisma) {
    return db.comment.update({ where: { id }, data: { deletedAt: new Date() } });
  },
};

export const cheerRepository = {
  add(postId: string, userId: string, db: Db = prisma) {
    return db.cheer.upsert({ where: { postId_userId: { postId, userId } }, create: { postId, userId }, update: {} });
  },
  remove(postId: string, userId: string, db: Db = prisma) {
    return db.cheer.deleteMany({ where: { postId, userId } });
  },
};

export const reportRepository = {
  find(reporterId: string, targetType: string, targetId: string, db: Db = prisma) {
    return db.report.findUnique({ where: { reporterId_targetType_targetId: { reporterId, targetType, targetId } } });
  },
  create(data: { reporterId: string; targetType: string; targetId: string; reason: string }, db: Db = prisma) {
    return db.report.create({ data: { id: newId(), ...data } });
  },
};

export const blockRepository = {
  /** Người dùng có quan hệ chặn với userId theo cả hai chiều. */
  async relatedIds(userId: string, db: Db = prisma): Promise<string[]> {
    const rows = await db.block.findMany({ where: { OR: [{ blockerId: userId }, { blockedId: userId }] } });
    return [...new Set(rows.map((r) => (r.blockerId === userId ? r.blockedId : r.blockerId)))];
  },
  async isBlockedEitherWay(a: string, b: string, db: Db = prisma) {
    const r = await db.block.findFirst({
      where: { OR: [{ blockerId: a, blockedId: b }, { blockerId: b, blockedId: a }] },
      select: { blockerId: true },
    });
    return r !== null;
  },
  add(blockerId: string, blockedId: string, db: Db = prisma) {
    return db.block.upsert({ where: { blockerId_blockedId: { blockerId, blockedId } }, create: { blockerId, blockedId }, update: {} });
  },
  remove(blockerId: string, blockedId: string, db: Db = prisma) {
    return db.block.deleteMany({ where: { blockerId, blockedId } });
  },
  listByBlocker(blockerId: string, db: Db = prisma) {
    return db.block.findMany({ where: { blockerId }, orderBy: { createdAt: "desc" } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return db.block.deleteMany({ where: { OR: [{ blockerId: userId }, { blockedId: userId }] } });
  },
};

export const eventRepository = {
  find(id: string, db: Db = prisma) {
    return db.clubEvent.findUnique({ where: { id } });
  },
  list(clubId: string, cursor: Cursor, limit: number, db: Db = prisma) {
    return db.clubEvent.findMany({
      where: { clubId, ...after(cursor, "startAt") },
      orderBy: [{ startAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });
  },
  create(data: Prisma.ClubEventUncheckedCreateInput, db: Db = prisma) {
    return db.clubEvent.create({ data });
  },
  cancel(id: string, db: Db = prisma) {
    return db.clubEvent.update({ where: { id }, data: { cancelledAt: new Date() } });
  },
  goingCounts(eventIds: string[], db: Db = prisma) {
    return db.rsvp.groupBy({ by: ["eventId"], where: { eventId: { in: eventIds }, status: "going" }, _count: { _all: true } });
  },
  myRsvps(userId: string, eventIds: string[], db: Db = prisma) {
    return db.rsvp.findMany({ where: { userId, eventId: { in: eventIds } } });
  },
  setRsvp(eventId: string, userId: string, status: "going" | "cancelled", db: Db = prisma) {
    return db.rsvp.upsert({ where: { eventId_userId: { eventId, userId } }, create: { eventId, userId, status }, update: { status } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return Promise.all([db.rsvp.deleteMany({ where: { userId } }), db.clubEvent.deleteMany({ where: { creatorId: userId } })]);
  },
};

export const publicUserRepository = {
  /** Chỉ trả displayName công khai (không email). */
  async displayNames(ids: string[], db: Db = prisma): Promise<Map<string, string | null>> {
    if (ids.length === 0) return new Map();
    const rows = await db.user.findMany({ where: { id: { in: ids } }, select: { id: true, displayName: true } });
    return new Map(rows.map((r) => [r.id, r.displayName]));
  },
};
