import { ZodError } from "zod";
import { stableStringify } from "@/lib/crypto";
import { AppError } from "@/lib/errors";
import { activityRepository, changeLogRepository } from "@/server/repositories/activity.repository";
import { attachmentRepository } from "@/server/repositories/media.repository";
import { goalRepository, profileRepository } from "@/server/repositories/profile.repository";
import { syncPullQuery, syncPushSchema, type SyncOperation } from "@/server/validators/misc";
import { activityService, toActivityDto } from "./activity.service";
import { toAttachmentDto } from "./attachment.service";
import { idempotencyService } from "./idempotency.service";
import { meService, toGoalDto, toProfileDto } from "./me.service";

// H03/H04: push từng operation có idempotencyKey (ack/reject/conflict riêng lẻ); pull theo chuỗi seq đơn điệu.

export type OpResult =
  | { idempotencyKey: string; entity: string; entityId: string; status: "acked"; revision: number | null; data: unknown }
  | { idempotencyKey: string; entity: string; entityId: string; status: "conflict"; error: { code: string; message: string }; server: unknown }
  | { idempotencyKey: string; entity: string; entityId: string; status: "rejected"; error: { code: string; message: string; details?: unknown } };

type ExecResult = { status: "acked"; revision: number | null; data: unknown };

async function execute(userId: string, op: SyncOperation): Promise<ExecResult> {
  if (op.entity === "activity") {
    if (op.op === "upsert") {
      const r = await activityService.upsert(userId, op.entityId, { activity: op.payload, expectedRevision: op.expectedRevision });
      return { status: "acked", revision: r.activity.revision, data: r.activity };
    }
    const r = await activityService.remove(userId, op.entityId, { expectedRevision: op.expectedRevision });
    return { status: "acked", revision: r.revision, data: r };
  }
  if (op.entity === "profile") {
    if (op.op === "delete") throw new AppError(422, "unsupported_operation", "Profile cannot be deleted via sync");
    const payload = (op.payload && typeof op.payload === "object" ? op.payload : {}) as Record<string, unknown>;
    const p = await meService.updateProfile(userId, { ...payload, expectedRevision: op.expectedRevision });
    return { status: "acked", revision: p.revision, data: p };
  }
  if (op.op === "delete") throw new AppError(422, "append_only", "Goal versions are append-only");
  const payload = (op.payload && typeof op.payload === "object" ? op.payload : {}) as Record<string, unknown>;
  const g = await meService.createGoal(userId, { ...payload, id: op.entityId });
  return { status: "acked", revision: null, data: g.goal };
}

export const syncService = {
  async push(userId: string, raw: unknown) {
    const { operations } = syncPushSchema.parse(raw);
    const results: OpResult[] = [];
    for (const op of operations) {
      const base = { idempotencyKey: op.idempotencyKey, entity: op.entity, entityId: op.entityId };
      const key = `sync:${op.idempotencyKey}`;
      const { idempotencyKey: _k, ...rest } = op;
      const requestHash = idempotencyService.requestHash("SYNC", "/sync/push", stableStringify(rest));
      try {
        const stored = await idempotencyService.lookup(userId, key, requestHash);
        if (stored) {
          results.push(JSON.parse(stored.responseBody) as OpResult);
          continue;
        }
      } catch (err) {
        if (err instanceof AppError) {
          results.push({ ...base, status: "rejected", error: { code: err.code, message: err.message } });
          continue;
        }
        throw err;
      }

      let result: OpResult;
      try {
        result = { ...base, ...(await execute(userId, op)) } as OpResult;
      } catch (err) {
        if (err instanceof AppError && err.status === 409) {
          const server = (err.details as { server?: unknown } | undefined)?.server ?? null;
          result = { ...base, status: "conflict", error: { code: err.code, message: err.message }, server };
        } else if (err instanceof AppError && err.status < 500 && err.status !== 429) {
          result = { ...base, status: "rejected", error: { code: err.code, message: err.message, details: err.details } };
        } else if (err instanceof ZodError) {
          result = {
            ...base,
            status: "rejected",
            error: { code: "validation_error", message: "Invalid payload", details: err.issues.slice(0, 20).map((i) => ({ path: i.path.join("."), message: i.message })) },
          };
        } else {
          // Lỗi tạm thời: không lưu idempotency để client gửi lại.
          results.push({ ...base, status: "rejected", error: { code: "retry_later", message: "Temporary failure, retry" } });
          continue;
        }
      }
      await idempotencyService.store({ userId, key, method: "SYNC", path: "/sync/push", requestHash }, 200, JSON.stringify(result));
      results.push(result);
    }
    return { results };
  },

  /** Trả thay đổi sau cursor (gồm tombstone). nextCursor = seq cuối đã đọc, client lưu lại cho lần sau. */
  async pull(userId: string, rawQuery: unknown) {
    const q = syncPullQuery.parse(rawQuery);
    const after = q.cursor ? Number(q.cursor) : 0;
    const rows = await changeLogRepository.listSince(userId, after, q.limit + 1);
    const hasMore = rows.length > q.limit;
    const page = hasMore ? rows.slice(0, q.limit) : rows;

    // Mỗi entity chỉ trả trạng thái hiện tại một lần, tại seq lớn nhất trong trang.
    const latest = new Map<string, (typeof page)[number]>();
    for (const r of page) latest.set(`${r.entity}:${r.entityId}`, r);
    const ids = (entity: string) => [...latest.values()].filter((r) => r.entity === entity).map((r) => r.entityId);

    const [activities, attachments, goals, profile] = await Promise.all([
      activityRepository.findManyOwned(userId, ids("activity")),
      attachmentRepository.findManyOwned(userId, ids("attachment")),
      goalRepository.findManyOwned(userId, ids("goal")),
      ids("profile").length ? profileRepository.find(userId) : Promise.resolve(null),
    ]);
    const byId = new Map<string, { data: unknown; revision: number | null; deleted: boolean }>();
    for (const a of activities) byId.set(`activity:${a.id}`, { data: toActivityDto(a), revision: a.revision, deleted: !!a.deletedAt });
    for (const a of attachments) byId.set(`attachment:${a.id}`, { data: toAttachmentDto(a), revision: a.revision, deleted: !!a.deletedAt });
    for (const g of goals) byId.set(`goal:${g.id}`, { data: toGoalDto(g), revision: null, deleted: false });
    if (profile) byId.set(`profile:${userId}`, { data: toProfileDto(profile), revision: profile.revision, deleted: false });

    const items = [...latest.values()]
      .sort((a, b) => a.seq - b.seq)
      .flatMap((r) => {
        const e = byId.get(`${r.entity}:${r.entityId}`);
        if (!e) return [];
        return [{ seq: r.seq, entity: r.entity, entityId: r.entityId, op: e.deleted ? "delete" : "upsert", revision: e.revision, data: e.data }];
      });
    const last = page[page.length - 1];
    return { items, nextCursor: String(last ? last.seq : after), hasMore };
  },
};
