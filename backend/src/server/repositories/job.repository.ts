import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";
import { ownerScope } from "./owner-scope";

export const jobRepository = {
  create(ownerId: string, kind: string, db: Db = prisma) {
    return db.job.create({ data: { id: newId(), ownerId, kind } });
  },
  findOwned(userId: string, id: string, kind: string, db: Db = prisma) {
    return db.job.findFirst({ where: ownerScope(userId, { id, kind }) });
  },
  findOpen(userId: string, kind: string, db: Db = prisma) {
    return db.job.findFirst({ where: ownerScope(userId, { kind, status: { in: ["queued", "running"] } }) });
  },
  latest(userId: string, kind: string, db: Db = prisma) {
    return db.job.findFirst({ where: ownerScope(userId, { kind }), orderBy: { createdAt: "desc" } });
  },
  listQueued(db: Db = prisma) {
    return db.job.findMany({ where: { status: "queued" }, orderBy: { createdAt: "asc" }, take: 20 });
  },
  findById(id: string, db: Db = prisma) {
    return db.job.findUnique({ where: { id } });
  },
  /** Chuyển queued -> running có điều kiện, tránh hai worker chạy cùng job. */
  async claim(id: string, db: Db = prisma) {
    const r = await db.job.updateMany({ where: { id, status: "queued" }, data: { status: "running", startedAt: new Date() } });
    return r.count === 1;
  },
  finish(id: string, data: Prisma.JobUpdateInput, db: Db = prisma) {
    return db.job.update({ where: { id }, data: { ...data, finishedAt: new Date() } });
  },
  deleteOthersForUser(userId: string, keepId: string, db: Db = prisma) {
    return db.job.deleteMany({ where: ownerScope(userId, { id: { not: keepId } }) });
  },
};
