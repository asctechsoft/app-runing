import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";

// Challenge, route, live share. Các truy vấn dữ liệu của người dùng luôn kèm userId/ownerId.

export const challengeRepository = {
  list(db: Db = prisma) {
    return db.challenge.findMany({ orderBy: [{ startDate: "desc" }, { id: "asc" }], take: 200 });
  },
  find(id: string, db: Db = prisma) {
    return db.challenge.findUnique({ where: { id } });
  },
  findParticipant(challengeId: string, userId: string, db: Db = prisma) {
    return db.challengeParticipant.findUnique({ where: { challengeId_userId: { challengeId, userId } } });
  },
  listParticipationsForUser(userId: string, db: Db = prisma) {
    return db.challengeParticipant.findMany({ where: { userId } });
  },
  listActiveParticipationsWithChallenge(userId: string, db: Db = prisma) {
    return db.challengeParticipant.findMany({ where: { userId, leftAt: null } }).then(async (parts) => {
      const challenges = await db.challenge.findMany({ where: { id: { in: parts.map((p) => p.challengeId) } } });
      const byId = new Map(challenges.map((c) => [c.id, c]));
      return parts.flatMap((p) => {
        const c = byId.get(p.challengeId);
        return c ? [{ participant: p, challenge: c }] : [];
      });
    });
  },
  upsertParticipant(challengeId: string, userId: string, leaderboardOptIn: boolean, db: Db = prisma) {
    return db.challengeParticipant.upsert({
      where: { challengeId_userId: { challengeId, userId } },
      create: { id: newId(), challengeId, userId, leaderboardOptIn },
      update: { leftAt: null, leaderboardOptIn },
    });
  },
  updateParticipant(challengeId: string, userId: string, data: Prisma.ChallengeParticipantUpdateInput, db: Db = prisma) {
    return db.challengeParticipant.update({ where: { challengeId_userId: { challengeId, userId } }, data });
  },
  leaderboard(challengeId: string, excludeUserIds: string[], db: Db = prisma) {
    return db.challengeParticipant.findMany({
      where: { challengeId, leftAt: null, leaderboardOptIn: true, userId: { notIn: excludeUserIds } },
      orderBy: [{ progressValue: "desc" }, { completedAt: "asc" }, { joinedAt: "asc" }],
      take: 50,
    });
  },
  upsertBadge(userId: string, challengeId: string, badgeKey: string | null, db: Db = prisma) {
    return db.badge.upsert({
      where: { userId_challengeId: { userId, challengeId } },
      create: { id: newId(), userId, challengeId, badgeKey },
      update: {},
    });
  },
  deleteBadge(userId: string, challengeId: string, db: Db = prisma) {
    return db.badge.deleteMany({ where: { userId, challengeId } });
  },
  listBadges(userId: string, db: Db = prisma) {
    return db.badge.findMany({ where: { userId }, orderBy: { awardedAt: "desc" } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return Promise.all([
      db.challengeParticipant.deleteMany({ where: { userId } }),
      db.badge.deleteMany({ where: { userId } }),
    ]);
  },
};

export const routeRepository = {
  search(
    q: { region?: string; minDistanceM?: number; maxDistanceM?: number; surface?: string },
    cursor: { t: number; id: string } | null,
    limit: number,
    db: Db = prisma,
  ) {
    const where: Prisma.RouteWhereInput = {
      ...(q.region && { regionLower: { contains: q.region.toLowerCase() } }),
      ...(q.surface && { surface: q.surface }),
      ...((q.minDistanceM !== undefined || q.maxDistanceM !== undefined) && {
        distanceM: { ...(q.minDistanceM !== undefined && { gte: q.minDistanceM }), ...(q.maxDistanceM !== undefined && { lte: q.maxDistanceM }) },
      }),
      ...(cursor && {
        OR: [{ createdAt: { lt: new Date(cursor.t) } }, { createdAt: new Date(cursor.t), id: { lt: cursor.id } }],
      }),
    };
    return db.route.findMany({ where, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: limit + 1 });
  },
  find(id: string, db: Db = prisma) {
    return db.route.findUnique({ where: { id } });
  },
  findMany(ids: string[], db: Db = prisma) {
    return db.route.findMany({ where: { id: { in: ids } } });
  },
  savedIds(userId: string, routeIds: string[], db: Db = prisma) {
    return db.savedRoute.findMany({ where: { userId, routeId: { in: routeIds } }, select: { routeId: true } });
  },
  save(userId: string, routeId: string, db: Db = prisma) {
    return db.savedRoute.upsert({ where: { userId_routeId: { userId, routeId } }, create: { userId, routeId }, update: {} });
  },
  unsave(userId: string, routeId: string, db: Db = prisma) {
    return db.savedRoute.deleteMany({ where: { userId, routeId } });
  },
  listSaved(userId: string, db: Db = prisma) {
    return db.savedRoute.findMany({ where: { userId }, orderBy: { createdAt: "desc" }, take: 200 });
  },
  deleteSavedForUser(userId: string, db: Db = prisma) {
    return db.savedRoute.deleteMany({ where: { userId } });
  },
};

export const liveShareRepository = {
  create(data: { id: string; activityId: string; ownerId: string; expiresAt: Date; viewerIds: string[] }, db: Db = prisma) {
    return db.liveShare.create({
      data: {
        id: data.id,
        activityId: data.activityId,
        ownerId: data.ownerId,
        expiresAt: data.expiresAt,
        viewers: { create: data.viewerIds.map((userId) => ({ userId })) },
      },
      include: { viewers: true },
    });
  },
  findOwned(ownerId: string, id: string, db: Db = prisma) {
    return db.liveShare.findFirst({ where: { id, ownerId }, include: { viewers: true } });
  },
  /** Chỉ trả về nếu userId nằm trong danh sách người xem. */
  findForViewer(viewerId: string, id: string, db: Db = prisma) {
    return db.liveShare.findFirst({ where: { id, viewers: { some: { userId: viewerId } } }, include: { viewers: true } });
  },
  findActiveForActivity(ownerId: string, activityId: string, now: Date, db: Db = prisma) {
    return db.liveShare.findFirst({ where: { ownerId, activityId, stoppedAt: null, expiresAt: { gt: now } } });
  },
  listActiveForViewer(viewerId: string, now: Date, db: Db = prisma) {
    return db.liveShare.findMany({
      where: { stoppedAt: null, expiresAt: { gt: now }, viewers: { some: { userId: viewerId } } },
      orderBy: { startedAt: "desc" },
      take: 50,
    });
  },
  update(id: string, data: Prisma.LiveShareUpdateInput, db: Db = prisma) {
    return db.liveShare.update({ where: { id }, data, include: { viewers: true } });
  },
  stopAllForActivity(activityId: string, reason: string, db: Db = prisma) {
    return db.liveShare.updateMany({ where: { activityId, stoppedAt: null }, data: { stoppedAt: new Date(), stopReason: reason } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return Promise.all([
      db.liveShareViewer.deleteMany({ where: { userId } }),
      db.liveShare.deleteMany({ where: { ownerId: userId } }),
    ]);
  },
};
