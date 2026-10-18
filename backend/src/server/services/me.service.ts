import type { GoalVersion, Profile } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { conflict, notFound, unauthorized } from "@/lib/errors";
import { isUniqueViolation, runInTransaction } from "@/lib/prisma";
import { activityRepository, changeLogRepository, guestClaimRepository } from "@/server/repositories/activity.repository";
import { userRepository } from "@/server/repositories/auth.repository";
import { goalRepository, profileRepository } from "@/server/repositories/profile.repository";
import { localDateStr } from "@/server/validators/common";
import {
  claimGuestSchema,
  createGoalSchema,
  goalTypes,
  sourcePrioritySchema,
  updateProfileSchema,
} from "@/server/validators/me";
import { toUserDto } from "./auth.service";

export function toProfileDto(p: Profile) {
  return {
    ownerId: p.userId,
    displayName: p.displayName,
    heightCm: p.heightCm,
    weightKg: p.weightKg,
    activityLevel: p.activityLevel,
    runningExperience: p.runningExperience,
    distanceUnit: p.distanceUnit,
    weightUnit: p.weightUnit,
    heightUnit: p.heightUnit,
    weekStart: p.weekStart,
    locale: p.locale,
    audioCues: JSON.parse(p.audioCuesJson) as unknown,
    autoPause: p.autoPause,
    sourcePriority: JSON.parse(p.sourcePriorityJson) as string[],
    revision: p.revision,
    updatedAt: p.updatedAt.getTime(),
  };
}

export function toGoalDto(g: GoalVersion) {
  return {
    id: g.id,
    ownerId: g.ownerId,
    type: g.type,
    value: g.value,
    effectiveFrom: g.effectiveFrom,
    createdAt: g.createdAt.getTime(),
  };
}

const profileConflict = (p: Profile) =>
  conflict("revision_conflict", "Profile was modified on the server", { server: toProfileDto(p) });

export const meService = {
  async get(userId: string) {
    const user = await userRepository.findById(userId);
    if (!user) throw unauthorized();
    const profile = await profileRepository.ensure(userId);
    return { user: toUserDto(user), profile: toProfileDto(profile) };
  },

  async getProfile(userId: string) {
    return toProfileDto(await profileRepository.ensure(userId));
  },

  /** PUT profile/settings với expectedRevision; lệch revision => 409 kèm bản server. */
  async updateProfile(userId: string, raw: unknown) {
    const input = updateProfileSchema.parse(raw);
    const { expectedRevision, audioCues, ...fields } = input;
    return runInTransaction(async (tx) => {
      const current = await profileRepository.ensure(userId, tx);
      if (current.revision !== expectedRevision) throw profileConflict(current);
      const n = await profileRepository.updateAtRevision(
        userId,
        expectedRevision,
        { ...fields, ...(audioCues && { audioCuesJson: JSON.stringify(audioCues) }), revision: expectedRevision + 1 },
        tx,
      );
      if (n === 0) throw profileConflict((await profileRepository.find(userId, tx))!);
      if (fields.displayName !== undefined) await userRepository.update(userId, { displayName: fields.displayName }, tx);
      await changeLogRepository.record(userId, "profile", userId, "upsert", tx);
      return toProfileDto((await profileRepository.find(userId, tx))!);
    });
  },

  async getSourcePriorities(userId: string) {
    const p = await profileRepository.ensure(userId);
    return { priorities: JSON.parse(p.sourcePriorityJson) as string[], revision: p.revision };
  },

  async setSourcePriorities(userId: string, raw: unknown) {
    const input = sourcePrioritySchema.parse(raw);
    const profile = await runInTransaction(async (tx) => {
      const current = await profileRepository.ensure(userId, tx);
      if (current.revision !== input.expectedRevision) throw profileConflict(current);
      const n = await profileRepository.updateAtRevision(
        userId,
        input.expectedRevision,
        { sourcePriorityJson: JSON.stringify(input.priorities), revision: input.expectedRevision + 1 },
        tx,
      );
      if (n === 0) throw profileConflict((await profileRepository.find(userId, tx))!);
      await changeLogRepository.record(userId, "profile", userId, "upsert", tx);
      return (await profileRepository.find(userId, tx))!;
    });
    return { priorities: JSON.parse(profile.sourcePriorityJson) as string[], revision: profile.revision };
  },

  async listGoals(userId: string) {
    return { items: (await goalRepository.listOwned(userId)).map(toGoalDto), nextCursor: null };
  },

  /** GoalVersion append-only. Gửi lại cùng id + cùng nội dung => idempotent. */
  async createGoal(userId: string, raw: unknown) {
    const input = createGoalSchema.parse(raw);
    const id = input.id ?? newId();
    const same = (g: GoalVersion) => g.type === input.type && g.value === input.value && g.effectiveFrom === input.effectiveFrom;
    const owner = await goalRepository.ownerOf(id);
    if (owner && owner !== userId) throw notFound("Goal");
    if (owner) {
      const g = (await goalRepository.findOwned(userId, id))!;
      if (!same(g)) throw conflict("goal_immutable", "Goal versions are append-only", { server: toGoalDto(g) });
      return { goal: toGoalDto(g), created: false };
    }
    try {
      const g = await runInTransaction(async (tx) => {
        const created = await goalRepository.create({ id, ownerId: userId, type: input.type, value: input.value, effectiveFrom: input.effectiveFrom }, tx);
        await changeLogRepository.record(userId, "goal", id, "upsert", tx);
        return created;
      });
      return { goal: toGoalDto(g), created: true };
    } catch (err) {
      if (isUniqueViolation(err)) throw conflict("goal_conflict", "Goal id already exists");
      throw err;
    }
  },

  async currentGoals(userId: string, rawDate: unknown) {
    const date = localDateStr.parse(rawDate);
    const result: Record<string, ReturnType<typeof toGoalDto> | null> = {};
    for (const type of goalTypes) {
      const g = await goalRepository.findEffective(userId, type, date);
      result[type] = g ? toGoalDto(g) : null;
    }
    return { date, goals: result };
  },

  /**
   * E03: giữ chỗ các ID hoạt động guest cho tài khoản trước khi upload.
   * Idempotent theo activityId; không bao giờ gắn dữ liệu đã thuộc người khác.
   */
  async claimGuest(userId: string, raw: unknown) {
    const input = claimGuestSchema.parse(raw);
    const ids = [...new Set(input.activityIds)];
    const results: Array<{ activityId: string; status: "claimed" | "alreadyClaimed" | "alreadyOwned" | "rejected" }> = [];
    for (const activityId of ids) {
      const owner = await activityRepository.ownerOf(activityId);
      if (owner) {
        results.push({ activityId, status: owner === userId ? "alreadyOwned" : "rejected" });
        continue;
      }
      const claim = await guestClaimRepository.find(activityId);
      if (claim) {
        results.push({ activityId, status: claim.userId === userId ? "alreadyClaimed" : "rejected" });
        continue;
      }
      try {
        await guestClaimRepository.create({ activityId, userId, guestId: input.guestId });
        results.push({ activityId, status: "claimed" });
      } catch (err) {
        if (!isUniqueViolation(err)) throw err;
        const again = await guestClaimRepository.find(activityId);
        results.push({ activityId, status: again?.userId === userId ? "alreadyClaimed" : "rejected" });
      }
    }
    return { results };
  },
};
