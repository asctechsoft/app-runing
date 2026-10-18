import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { assertUserId, ownerScope } from "./owner-scope";

export const profileRepository = {
  find(userId: string, db: Db = prisma) {
    return db.profile.findUnique({ where: { userId: assertUserId(userId) } });
  },
  ensure(userId: string, db: Db = prisma) {
    return db.profile.upsert({ where: { userId: assertUserId(userId) }, create: { userId }, update: {} });
  },
  async updateAtRevision(userId: string, revision: number, data: Prisma.ProfileUncheckedUpdateManyInput, db: Db = prisma) {
    const r = await db.profile.updateMany({ where: { userId: assertUserId(userId), revision }, data });
    return r.count;
  },
  delete(userId: string, db: Db = prisma) {
    return db.profile.deleteMany({ where: { userId: assertUserId(userId) } });
  },
};

export const goalRepository = {
  findOwned(userId: string, id: string, db: Db = prisma) {
    return db.goalVersion.findFirst({ where: ownerScope(userId, { id }) });
  },
  async ownerOf(id: string, db: Db = prisma) {
    const r = await db.goalVersion.findUnique({ where: { id }, select: { ownerId: true } });
    return r?.ownerId ?? null;
  },
  listOwned(userId: string, db: Db = prisma) {
    return db.goalVersion.findMany({
      where: ownerScope(userId),
      orderBy: [{ type: "asc" }, { effectiveFrom: "asc" }, { createdAt: "asc" }],
    });
  },
  findManyOwned(userId: string, ids: string[], db: Db = prisma) {
    return db.goalVersion.findMany({ where: ownerScope(userId, { id: { in: ids } }) });
  },
  /** Version hiệu lực cho ngày D: effectiveFrom <= D, mới nhất (tie-break theo createdAt). */
  findEffective(userId: string, type: string, date: string, db: Db = prisma) {
    return db.goalVersion.findFirst({
      where: ownerScope(userId, { type, effectiveFrom: { lte: date } }),
      orderBy: [{ effectiveFrom: "desc" }, { createdAt: "desc" }],
    });
  },
  create(data: { id: string; ownerId: string; type: string; value: number; effectiveFrom: string }, db: Db = prisma) {
    return db.goalVersion.create({ data });
  },
  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.goalVersion.deleteMany({ where: ownerScope(userId) });
  },
};
