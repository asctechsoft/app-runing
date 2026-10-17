import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";
import { liveOwnerScope, ownerScope } from "./owner-scope";

export const trackRepository = {
  findOwned(userId: string, activityId: string, db: Db = prisma) {
    return db.track.findFirst({ where: ownerScope(userId, { activityId }) });
  },
  findManyFinalizedOwned(userId: string, activityIds: string[], db: Db = prisma) {
    return db.track.findMany({ where: ownerScope(userId, { activityId: { in: activityIds }, status: "finalized" }) });
  },
  ensure(userId: string, activityId: string, db: Db = prisma) {
    return db.track.upsert({
      where: { activityId },
      create: { activityId, ownerId: userId },
      update: {},
    });
  },
  async finalize(userId: string, activityId: string, data: Prisma.TrackUncheckedUpdateManyInput, db: Db = prisma) {
    const r = await db.track.updateMany({ where: ownerScope(userId, { activityId, status: "uploading" }), data });
    return r.count;
  },
  deleteOwned(userId: string, activityId: string, db: Db = prisma) {
    return db.track.deleteMany({ where: ownerScope(userId, { activityId }) });
  },
  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.track.deleteMany({ where: ownerScope(userId) });
  },
};

export const trackChunkRepository = {
  find(userId: string, activityId: string, seq: number, db: Db = prisma) {
    return db.trackChunk.findFirst({ where: ownerScope(userId, { activityId, seq }) });
  },
  list(userId: string, activityId: string, db: Db = prisma) {
    return db.trackChunk.findMany({ where: ownerScope(userId, { activityId }), orderBy: { seq: "asc" } });
  },
  create(data: { activityId: string; ownerId: string; seq: number; sha256: string; bytes: number; storageKey: string }, db: Db = prisma) {
    return db.trackChunk.create({ data: { id: newId(), ...data } });
  },
  deleteForActivity(userId: string, activityId: string, db: Db = prisma) {
    return db.trackChunk.deleteMany({ where: ownerScope(userId, { activityId }) });
  },
  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.trackChunk.deleteMany({ where: ownerScope(userId) });
  },
};

export const attachmentRepository = {
  findOwned(userId: string, id: string, opts: { includeDeleted?: boolean } = {}, db: Db = prisma) {
    return db.attachment.findFirst({ where: opts.includeDeleted ? ownerScope(userId, { id }) : liveOwnerScope(userId, { id }) });
  },
  async ownerOf(id: string, db: Db = prisma) {
    const r = await db.attachment.findUnique({ where: { id }, select: { ownerId: true } });
    return r?.ownerId ?? null;
  },
  listForActivity(userId: string, activityId: string, db: Db = prisma) {
    return db.attachment.findMany({ where: liveOwnerScope(userId, { activityId }), orderBy: { createdAt: "asc" } });
  },
  countLiveForActivity(userId: string, activityId: string, db: Db = prisma) {
    return db.attachment.count({ where: liveOwnerScope(userId, { activityId }) });
  },
  findManyOwned(userId: string, ids: string[], db: Db = prisma) {
    return db.attachment.findMany({ where: ownerScope(userId, { id: { in: ids } }) });
  },
  create(data: Prisma.AttachmentUncheckedCreateInput, db: Db = prisma) {
    return db.attachment.create({ data });
  },
  update(userId: string, id: string, data: Prisma.AttachmentUncheckedUpdateManyInput, db: Db = prisma) {
    return db.attachment.updateMany({ where: ownerScope(userId, { id }), data });
  },
  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.attachment.deleteMany({ where: ownerScope(userId) });
  },
};
