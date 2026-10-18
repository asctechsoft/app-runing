import type { Challenge, ChallengeParticipant } from "@prisma/client";
import { conflict, notFound } from "@/lib/errors";
import { localDate } from "@/lib/time";
import { activityRepository } from "@/server/repositories/activity.repository";
import { challengeRepository } from "@/server/repositories/explore.repository";
import { blockRepository, publicUserRepository } from "@/server/repositories/social.repository";
import { notificationRepository } from "@/server/repositories/notification.repository";
import { challengeJoinSchema, optInSchema } from "@/server/validators/misc";

// M04: tiến độ challenge tính ở server từ hoạt động đủ điều kiện (loại + khoảng ngày theo tz của challenge).
// Luôn tính lại từ đầu => retry/sửa/xóa hoạt động không gây cộng trùng.

const DAY_MS = 86_400_000;

function types(c: Challenge): string[] {
  return JSON.parse(c.activityTypesJson) as string[];
}

export function toChallengeDto(c: Challenge, p?: ChallengeParticipant | null) {
  return {
    id: c.id,
    title: c.title,
    description: c.description,
    ruleVersion: c.ruleVersion,
    activityTypes: types(c),
    startDate: c.startDate,
    endDate: c.endDate,
    tzId: c.tzId,
    targetType: c.targetType,
    targetValue: c.targetValue,
    badgeKey: c.badgeKey,
    isDevFixture: c.isDevFixture,
    participation: p && !p.leftAt ? toParticipationDto(c, p) : null,
  };
}

function toParticipationDto(c: Challenge, p: ChallengeParticipant) {
  return {
    joinedAt: p.joinedAt.getTime(),
    progressValue: p.progressValue,
    targetValue: c.targetValue,
    percent: Math.min(100, Math.floor((p.progressValue / c.targetValue) * 100)),
    completedAt: p.completedAt?.getTime() ?? null,
    leaderboardOptIn: p.leaderboardOptIn,
  };
}

export async function computeProgress(userId: string, c: Challenge): Promise<number> {
  // Khoảng thô ±1 ngày quanh ngày bắt đầu/kết thúc (UTC) rồi lọc chính xác theo ngày địa phương của tz challenge.
  const from = new Date(Date.parse(`${c.startDate}T00:00:00Z`) - DAY_MS);
  const to = new Date(Date.parse(`${c.endDate}T00:00:00Z`) + 2 * DAY_MS);
  const rows = await activityRepository.listEligible(userId, types(c), from, to);
  let total = 0;
  for (const a of rows) {
    const d = localDate(a.startedAt, c.tzId);
    if (d < c.startDate || d > c.endDate) continue;
    if (c.targetType === "distance") total += a.distanceM ?? 0;
    else if (c.targetType === "time") total += a.movingMs;
    else total += 1;
  }
  return total;
}

async function applyProgress(userId: string, c: Challenge, p: ChallengeParticipant) {
  const value = await computeProgress(userId, c);
  const complete = value >= c.targetValue;
  let completedAt = p.completedAt;
  if (complete && !completedAt) {
    completedAt = new Date();
    await challengeRepository.upsertBadge(userId, c.id, c.badgeKey);
    await notificationRepository.create({
      ownerId: userId,
      kind: "challengeCompleted",
      title: "Challenge completed",
      body: c.title,
      deepLink: `stride://challenges/${c.id}`,
    });
  } else if (!complete && completedAt) {
    // Hoạt động bị xóa/sửa khiến không còn đạt: thu hồi hoàn thành và huy hiệu (không giữ dữ liệu không có thật).
    completedAt = null;
    await challengeRepository.deleteBadge(userId, c.id);
  }
  if (value !== p.progressValue || completedAt?.getTime() !== p.completedAt?.getTime()) {
    return challengeRepository.updateParticipant(c.id, userId, { progressValue: value, completedAt });
  }
  return p;
}

export const challengeService = {
  async list(userId: string) {
    const [challenges, parts] = await Promise.all([challengeRepository.list(), challengeRepository.listParticipationsForUser(userId)]);
    const byChallenge = new Map(parts.map((p) => [p.challengeId, p]));
    return { items: challenges.map((c) => toChallengeDto(c, byChallenge.get(c.id))), nextCursor: null };
  },

  async get(userId: string, id: string) {
    const c = await challengeRepository.find(id);
    if (!c) throw notFound("Challenge");
    return toChallengeDto(c, await challengeRepository.findParticipant(id, userId));
  },

  async join(userId: string, id: string, raw: unknown) {
    const input = challengeJoinSchema.parse(raw);
    const c = await challengeRepository.find(id);
    if (!c) throw notFound("Challenge");
    if (localDate(new Date(), c.tzId) > c.endDate) throw conflict("challenge_ended", "Challenge has ended");
    const p = await challengeRepository.upsertParticipant(id, userId, input.leaderboardOptIn);
    const updated = await applyProgress(userId, c, p);
    return toChallengeDto(c, updated);
  },

  async leave(userId: string, id: string) {
    const c = await challengeRepository.find(id);
    if (!c) throw notFound("Challenge");
    const p = await challengeRepository.findParticipant(id, userId);
    if (p && !p.leftAt) await challengeRepository.updateParticipant(id, userId, { leftAt: new Date(), leaderboardOptIn: false });
    return toChallengeDto(c, null);
  },

  async setLeaderboardOptIn(userId: string, id: string, raw: unknown) {
    const { leaderboardOptIn } = optInSchema.parse(raw);
    const c = await challengeRepository.find(id);
    const p = c ? await challengeRepository.findParticipant(id, userId) : null;
    if (!c || !p || p.leftAt) throw notFound("Participation");
    return toChallengeDto(c, await challengeRepository.updateParticipant(id, userId, { leaderboardOptIn }));
  },

  async progress(userId: string, id: string) {
    const c = await challengeRepository.find(id);
    const p = c ? await challengeRepository.findParticipant(id, userId) : null;
    if (!c || !p || p.leftAt) throw notFound("Participation");
    return toParticipationDto(c, p);
  },

  /** Chỉ người tham gia đã opt-in; loại người có quan hệ chặn với người xem. */
  async leaderboard(viewerId: string, id: string) {
    const c = await challengeRepository.find(id);
    if (!c) throw notFound("Challenge");
    const blocked = await blockRepository.relatedIds(viewerId);
    const rows = await challengeRepository.leaderboard(id, blocked);
    const names = await publicUserRepository.displayNames(rows.map((r) => r.userId));
    return {
      items: rows.map((r, i) => ({
        rank: i + 1,
        userId: r.userId,
        displayName: names.get(r.userId) ?? null,
        progressValue: r.progressValue,
        completedAt: r.completedAt?.getTime() ?? null,
      })),
      nextCursor: null,
    };
  },

  async badges(userId: string) {
    const rows = await challengeRepository.listBadges(userId);
    return { items: rows.map((b) => ({ id: b.id, challengeId: b.challengeId, badgeKey: b.badgeKey, awardedAt: b.awardedAt.getTime() })), nextCursor: null };
  },

  /** Gọi sau mỗi thay đổi hoạt động. */
  async recomputeForUser(userId: string) {
    const parts = await challengeRepository.listActiveParticipationsWithChallenge(userId);
    for (const { participant, challenge } of parts) await applyProgress(userId, challenge, participant);
  },
};
