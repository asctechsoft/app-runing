import { sha256Hex, stableStringify } from "@/lib/crypto";
import { AppError, conflict, notFound } from "@/lib/errors";
import { logger } from "@/lib/logger";
import { isUniqueViolation, runInTransaction } from "@/lib/prisma";
import { storage } from "@/lib/storage";
import { toMs } from "@/lib/time";
import {
  activityRepository,
  changeLogRepository,
  guestClaimRepository,
  type ActivityRow,
} from "@/server/repositories/activity.repository";
import { attachmentRepository, trackChunkRepository, trackRepository } from "@/server/repositories/media.repository";
import { decodeCursor, encodeCursor } from "@/server/http/pagination";
import {
  deleteQuery,
  listActivitiesQuery,
  patchActivitySchema,
  upsertActivitySchema,
  type ActivityBody,
} from "@/server/validators/activity";
import { challengeService } from "./challenge.service";
import { liveShareService } from "./live-share.service";

// H02: Hoạt động upsert theo id do client sinh; sửa metadata có expectedRevision; xóa => tombstone.

type NormalizedBody = ReturnType<typeof normalizeBody>;

function normalizeBody(a: ActivityBody) {
  return {
    type: a.type,
    status: a.status,
    startedAt: a.startedAt,
    endedAt: a.endedAt ?? null,
    tzId: a.tzId,
    tzOffsetMin: a.tzOffsetMin,
    distanceM: a.distanceM ?? null,
    movingMs: a.movingMs,
    elapsedMs: a.elapsedMs,
    avgPaceSecPerKm: a.avgPaceSecPerKm ?? null,
    steps: a.steps ?? null,
    caloriesKcal: a.caloriesKcal ?? null,
    calorieModel: a.calorieModel ?? null,
    weightKgUsed: a.weightKgUsed ?? null,
    title: a.title,
    feeling: a.feeling ?? null,
    notes: a.notes ?? null,
    privacy: a.privacy,
    shareRoute: a.shareRoute,
    goal: a.goal ? { type: a.goal.type, value: a.goal.value ?? null } : null,
    hasGps: a.hasGps,
    distanceSource: a.distanceSource,
    workoutExecutionId: a.workoutExecutionId ?? null,
  };
}

function bodyFromRow(r: ActivityRow): NormalizedBody {
  return {
    type: r.type as NormalizedBody["type"],
    status: r.status as NormalizedBody["status"],
    startedAt: r.startedAt.getTime(),
    endedAt: toMs(r.endedAt),
    tzId: r.tzId,
    tzOffsetMin: r.tzOffsetMin,
    distanceM: r.distanceM,
    movingMs: r.movingMs,
    elapsedMs: r.elapsedMs,
    avgPaceSecPerKm: r.avgPaceSecPerKm,
    steps: r.steps,
    caloriesKcal: r.caloriesKcal,
    calorieModel: r.calorieModel,
    weightKgUsed: r.weightKgUsed,
    title: r.title,
    feeling: r.feeling as NormalizedBody["feeling"],
    notes: r.notes,
    privacy: r.privacy as NormalizedBody["privacy"],
    shareRoute: r.shareRoute,
    goal: r.goalJson ? (JSON.parse(r.goalJson) as NormalizedBody["goal"]) : null,
    hasGps: r.hasGps,
    distanceSource: r.distanceSource as NormalizedBody["distanceSource"],
    workoutExecutionId: r.workoutExecutionId,
  };
}

const hashBody = (b: NormalizedBody) => sha256Hex(stableStringify(b));

function toColumns(b: NormalizedBody) {
  return {
    type: b.type,
    status: b.status,
    startedAt: new Date(b.startedAt),
    endedAt: b.endedAt === null ? null : new Date(b.endedAt),
    tzId: b.tzId,
    tzOffsetMin: b.tzOffsetMin,
    distanceM: b.distanceM,
    movingMs: b.movingMs,
    elapsedMs: b.elapsedMs,
    avgPaceSecPerKm: b.avgPaceSecPerKm,
    steps: b.steps,
    caloriesKcal: b.caloriesKcal,
    calorieModel: b.calorieModel,
    weightKgUsed: b.weightKgUsed,
    title: b.title,
    feeling: b.feeling,
    notes: b.notes,
    privacy: b.privacy,
    shareRoute: b.shareRoute,
    goalJson: b.goal ? JSON.stringify(b.goal) : null,
    hasGps: b.hasGps,
    distanceSource: b.distanceSource,
    workoutExecutionId: b.workoutExecutionId,
    contentHash: hashBody(b),
  };
}

export function toActivityDto(r: ActivityRow) {
  if (r.deletedAt) {
    return { id: r.id, ownerId: r.ownerId, revision: r.revision, deletedAt: r.deletedAt.getTime(), updatedAt: r.updatedAt.getTime() };
  }
  return {
    id: r.id,
    ownerId: r.ownerId,
    ...bodyFromRow(r),
    revision: r.revision,
    createdAt: r.createdAt.getTime(),
    updatedAt: r.updatedAt.getTime(),
    deletedAt: null,
  };
}

function revisionConflict(row: ActivityRow, code = "revision_conflict", message = "Activity was modified on the server") {
  return conflict(code, message, { server: toActivityDto(row) });
}

const FINISHED = new Set(["saved", "discarded"]);

async function afterChange(userId: string, row: ActivityRow) {
  // Tính lại challenge (từ đầu => không cộng trùng khi retry) và dừng live share khi hoạt động kết thúc.
  try {
    await challengeService.recomputeForUser(userId);
  } catch (err) {
    logger.error("challenge_recompute_failed", { userId, err });
  }
  if (row.deletedAt || FINISHED.has(row.status)) {
    await liveShareService.stopForActivity(row.id, row.deletedAt ? "activityDeleted" : "activityFinished");
  }
}

export const activityService = {
  async upsert(userId: string, id: string, raw: unknown): Promise<{ activity: ReturnType<typeof toActivityDto>; created: boolean }> {
    const input = upsertActivitySchema.parse(raw);
    const body = normalizeBody(input.activity);
    const attempt = async () =>
      runInTransaction(async (tx) => {
        const owner = await activityRepository.ownerOf(id, tx);
        if (owner && owner !== userId) throw notFound("Activity");
        const claim = await guestClaimRepository.find(id, tx);
        if (claim && claim.userId !== userId) throw notFound("Activity");

        if (!owner) {
          const row = await activityRepository.create({ id, ownerId: userId, ...toColumns(body), revision: 1 }, tx);
          await changeLogRepository.record(userId, "activity", id, "upsert", tx);
          return { row, created: true, changed: true };
        }
        const existing = (await activityRepository.findOwned(userId, id, { includeDeleted: true }, tx))!;
        if (existing.deletedAt) throw revisionConflict(existing, "activity_deleted", "Activity was deleted");
        const sameContent = existing.contentHash === hashBody(body);
        if (input.expectedRevision === undefined) {
          // Retry của lần tạo đầu tiên (cùng nội dung) => idempotent, không tăng revision.
          if (sameContent) return { row: existing, created: false, changed: false };
          throw revisionConflict(existing, "revision_required", "expectedRevision is required to update an existing activity");
        }
        if (input.expectedRevision !== existing.revision) throw revisionConflict(existing);
        if (sameContent) return { row: existing, created: false, changed: false };
        const n = await activityRepository.updateAtRevision(
          userId,
          id,
          existing.revision,
          { ...toColumns(body), revision: existing.revision + 1 },
          tx,
        );
        if (n === 0) throw revisionConflict(existing);
        await changeLogRepository.record(userId, "activity", id, "upsert", tx);
        return { row: (await activityRepository.findOwned(userId, id, {}, tx))!, created: false, changed: true };
      });

    let result;
    try {
      result = await attempt();
    } catch (err) {
      // Hai request tạo song song cùng id: lần sau đi vào nhánh cập nhật/idempotent.
      if (!isUniqueViolation(err)) throw err;
      result = await attempt();
    }
    if (result.changed) await afterChange(userId, result.row);
    return { activity: toActivityDto(result.row), created: result.created };
  },

  async get(userId: string, id: string) {
    const row = await activityRepository.findOwned(userId, id);
    if (!row) throw notFound("Activity");
    return toActivityDto(row);
  },

  async list(userId: string, rawQuery: unknown) {
    const q = listActivitiesQuery.parse(rawQuery);
    const rows = await activityRepository.listOwned(userId, {
      cursor: decodeCursor(q.cursor),
      limit: q.limit,
      includeDeleted: q.includeDeleted === "true",
    });
    const hasMore = rows.length > q.limit;
    const items = hasMore ? rows.slice(0, q.limit) : rows;
    const last = items[items.length - 1];
    return {
      items: items.map(toActivityDto),
      nextCursor: hasMore && last ? encodeCursor({ t: last.startedAt.getTime(), id: last.id }) : null,
    };
  },

  async patch(userId: string, id: string, raw: unknown) {
    const input = patchActivitySchema.parse(raw);
    const row = await runInTransaction(async (tx) => {
      const existing = await activityRepository.findOwned(userId, id, { includeDeleted: true }, tx);
      if (!existing) throw notFound("Activity");
      if (existing.deletedAt) throw revisionConflict(existing, "activity_deleted", "Activity was deleted");
      if (existing.revision !== input.expectedRevision) throw revisionConflict(existing);
      const merged: NormalizedBody = {
        ...bodyFromRow(existing),
        ...(input.title !== undefined && { title: input.title }),
        ...(input.feeling !== undefined && { feeling: input.feeling }),
        ...(input.notes !== undefined && { notes: input.notes }),
        ...(input.privacy !== undefined && { privacy: input.privacy }),
        ...(input.shareRoute !== undefined && { shareRoute: input.shareRoute }),
        ...(input.status !== undefined && { status: input.status }),
        ...(input.endedAt !== undefined && { endedAt: input.endedAt }),
      };
      if (merged.status === "saved" && merged.endedAt === null) {
        throw new AppError(422, "validation_error", "Saved activity requires endedAt");
      }
      if (merged.endedAt !== null && merged.endedAt < merged.startedAt) {
        throw new AppError(422, "validation_error", "endedAt must be >= startedAt");
      }
      const n = await activityRepository.updateAtRevision(
        userId,
        id,
        existing.revision,
        { ...toColumns(merged), revision: existing.revision + 1 },
        tx,
      );
      if (n === 0) throw revisionConflict(existing);
      await changeLogRepository.record(userId, "activity", id, "upsert", tx);
      return (await activityRepository.findOwned(userId, id, {}, tx))!;
    });
    await afterChange(userId, row);
    return toActivityDto(row);
  },

  /** Xóa => tombstone (giữ vĩnh viễn để sync), xóa track + ảnh khỏi storage. */
  async remove(userId: string, id: string, rawQuery: unknown) {
    const q = deleteQuery.parse(rawQuery);
    const result = await runInTransaction(async (tx) => {
      const existing = await activityRepository.findOwned(userId, id, { includeDeleted: true }, tx);
      if (!existing) throw notFound("Activity");
      if (existing.deletedAt) return { row: existing, changed: false, attachmentKeys: [] as string[] };
      if (q.expectedRevision !== undefined && q.expectedRevision !== existing.revision) throw revisionConflict(existing);
      const now = new Date();
      const n = await activityRepository.updateAtRevision(
        userId,
        id,
        existing.revision,
        { deletedAt: now, revision: existing.revision + 1 },
        tx,
      );
      if (n === 0) throw revisionConflict(existing);
      await changeLogRepository.record(userId, "activity", id, "delete", tx);
      const atts = await attachmentRepository.listForActivity(userId, id, tx);
      for (const a of atts) {
        await attachmentRepository.update(userId, a.id, { deletedAt: now, revision: a.revision + 1 }, tx);
        await changeLogRepository.record(userId, "attachment", a.id, "delete", tx);
      }
      await trackChunkRepository.deleteForActivity(userId, id, tx);
      await trackRepository.deleteOwned(userId, id, tx);
      return {
        row: (await activityRepository.findOwned(userId, id, { includeDeleted: true }, tx))!,
        changed: true,
        attachmentKeys: atts.map((a) => a.storageKey),
      };
    });
    if (result.changed) {
      const s = storage();
      await s.deletePrefix(`tracks/${userId}/${id}`);
      for (const key of result.attachmentKeys) await s.delete(key);
      await afterChange(userId, result.row);
    }
    return toActivityDto(result.row);
  },
};
