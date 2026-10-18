import type { Prisma } from "@prisma/client";
import { prisma, type Db } from "@/lib/prisma";
import { liveOwnerScope, ownerScope } from "./owner-scope";

export type ActivityRow = Prisma.ActivityGetPayload<object>;

export const activityRepository = {
  /** Luôn lọc theo owner (H01). Bản ghi của người khác => null => 404. */
  findOwned(userId: string, id: string, opts: { includeDeleted?: boolean } = {}, db: Db = prisma) {
    const where = opts.includeDeleted ? ownerScope(userId, { id }) : liveOwnerScope(userId, { id });
    return db.activity.findFirst({ where });
  },

  /**
   * Chỉ dùng để phát hiện va chạm ID do client sinh (upsert/claim). Trả về ownerId, không trả dữ liệu.
   */
  async ownerOf(id: string, db: Db = prisma): Promise<string | null> {
    const row = await db.activity.findUnique({ where: { id }, select: { ownerId: true } });
    return row?.ownerId ?? null;
  },

  create(data: Prisma.ActivityUncheckedCreateInput, db: Db = prisma) {
    return db.activity.create({ data });
  },

  /** Cập nhật có điều kiện revision (optimistic concurrency). Trả về số bản ghi được cập nhật. */
  async updateAtRevision(
    userId: string,
    id: string,
    revision: number,
    data: Prisma.ActivityUncheckedUpdateManyInput,
    db: Db = prisma,
  ) {
    const r = await db.activity.updateMany({ where: ownerScope(userId, { id, revision }), data });
    return r.count;
  },

  listOwned(
    userId: string,
    opts: { cursor: { t: number; id: string } | null; limit: number; includeDeleted: boolean },
    db: Db = prisma,
  ) {
    const base = opts.includeDeleted ? ownerScope(userId) : liveOwnerScope(userId);
    const cursorWhere: Prisma.ActivityWhereInput = opts.cursor
      ? {
          OR: [
            { startedAt: { lt: new Date(opts.cursor.t) } },
            { startedAt: new Date(opts.cursor.t), id: { lt: opts.cursor.id } },
          ],
        }
      : {};
    return db.activity.findMany({
      where: { ...base, ...cursorWhere },
      orderBy: [{ startedAt: "desc" }, { id: "desc" }],
      take: opts.limit + 1,
    });
  },

  findManyOwned(userId: string, ids: string[], db: Db = prisma) {
    return db.activity.findMany({ where: ownerScope(userId, { id: { in: ids } }) });
  },

  listAllLiveOwned(userId: string, db: Db = prisma) {
    return db.activity.findMany({ where: liveOwnerScope(userId), orderBy: { startedAt: "asc" } });
  },

  /** Hoạt động đủ điều kiện cho challenge: đã lưu, chưa xóa, đúng loại, trong khoảng thời gian thô. */
  listEligible(userId: string, types: string[], from: Date, to: Date, db: Db = prisma) {
    return db.activity.findMany({
      where: liveOwnerScope(userId, { status: "saved", type: { in: types }, startedAt: { gte: from, lt: to } }),
      select: { id: true, startedAt: true, distanceM: true, movingMs: true },
    });
  },

  /** Đọc hoạt động theo id cho người xem khác (J04) — service bắt buộc kiểm tra quyền riêng tư sau đó. */
  findLiveForPrivacyCheck(ids: string[], db: Db = prisma) {
    return db.activity.findMany({ where: { id: { in: ids }, deletedAt: null, status: "saved" } });
  },

  deleteAllOwned(userId: string, db: Db = prisma) {
    return db.activity.deleteMany({ where: ownerScope(userId) });
  },
};

export const guestClaimRepository = {
  find(activityId: string, db: Db = prisma) {
    return db.guestClaim.findUnique({ where: { activityId } });
  },
  create(data: { activityId: string; userId: string; guestId: string }, db: Db = prisma) {
    return db.guestClaim.create({ data });
  },
  deleteForUser(userId: string, db: Db = prisma) {
    return db.guestClaim.deleteMany({ where: { userId } });
  },
};

export const changeLogRepository = {
  record(ownerId: string, entity: string, entityId: string, op: "upsert" | "delete", db: Db = prisma) {
    return db.changeLog.create({ data: { ownerId, entity, entityId, op } });
  },
  listSince(ownerId: string, afterSeq: number, take: number, db: Db = prisma) {
    return db.changeLog.findMany({
      where: { ownerId, seq: { gt: afterSeq } },
      orderBy: { seq: "asc" },
      take,
    });
  },
  deleteForUser(ownerId: string, db: Db = prisma) {
    return db.changeLog.deleteMany({ where: { ownerId } });
  },
};
