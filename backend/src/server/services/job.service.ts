import type { Job } from "@prisma/client";
import { strToU8, zipSync } from "fflate";
import { AppError, conflict, forbidden, gone, notFound } from "@/lib/errors";
import { logger } from "@/lib/logger";
import { runInTransaction } from "@/lib/prisma";
import { storage } from "@/lib/storage";
import { activityRepository, changeLogRepository, guestClaimRepository } from "@/server/repositories/activity.repository";
import { emailTokenRepository, sessionRepository, userRepository } from "@/server/repositories/auth.repository";
import { challengeRepository, liveShareRepository, routeRepository } from "@/server/repositories/explore.repository";
import { idempotencyRepository } from "@/server/repositories/idempotency.repository";
import { jobRepository } from "@/server/repositories/job.repository";
import { attachmentRepository, trackChunkRepository, trackRepository } from "@/server/repositories/media.repository";
import { feedbackRepository } from "@/server/repositories/feedback.repository";
import { notificationRepository } from "@/server/repositories/notification.repository";
import { goalRepository, profileRepository } from "@/server/repositories/profile.repository";
import {
  blockRepository,
  clubRepository,
  eventRepository,
  membershipRepository,
  postRepository,
} from "@/server/repositories/social.repository";
import type { AuthUser } from "@/server/auth/context";
import { toActivityDto } from "./activity.service";
import { REAUTH_WINDOW_MS } from "./auth.service";
import { buildGpx, type MergedTrack } from "./gpx";
import { toGoalDto, toProfileDto } from "./me.service";

// H06: export dữ liệu (JSON + CSV + GPX trong zip, có hạn) và xóa tài khoản (cần reauth gần đây).
// Không bao giờ báo "đã xóa" trước khi job thực sự xong.

const EXPORT_TTL_MS = 7 * 24 * 3600 * 1000;

export function toJobDto(j: Job) {
  return {
    id: j.id,
    kind: j.kind,
    status: j.status,
    createdAt: j.createdAt.getTime(),
    finishedAt: j.finishedAt?.getTime() ?? null,
    expiresAt: j.expiresAt?.getTime() ?? null,
    error: j.status === "failed" ? "Job failed; please retry" : null,
  };
}

function schedule(jobId: string) {
  if ((process.env.JOB_RUNNER ?? "inline") !== "inline") return;
  setImmediate(() => {
    jobService.run(jobId).catch((err) => logger.error("job_run_failed", { jobId, err }));
  });
}

function csvCell(v: unknown): string {
  if (v === null || v === undefined) return "";
  const s = String(v);
  // Chặn CSV/formula injection khi mở bằng bảng tính.
  const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

async function buildExport(userId: string): Promise<Uint8Array> {
  const activities = await activityRepository.listAllLiveOwned(userId);
  const profile = await profileRepository.find(userId);
  const goals = await goalRepository.listOwned(userId);
  const tracks = await trackRepository.findManyFinalizedOwned(userId, activities.map((a) => a.id));
  const files: Record<string, Uint8Array> = {};

  const dtos = activities.map(toActivityDto);
  files["activities.json"] = strToU8(JSON.stringify(dtos, null, 2));
  const cols = ["id", "type", "status", "startedAt", "endedAt", "tzId", "distanceM", "distanceSource", "movingMs", "elapsedMs", "avgPaceSecPerKm", "steps", "caloriesKcal", "calorieModel", "title", "feeling", "privacy"] as const;
  const lines = [cols.join(",")];
  for (const a of activities) {
    const row: Record<(typeof cols)[number], unknown> = {
      id: a.id,
      type: a.type,
      status: a.status,
      startedAt: a.startedAt.toISOString(),
      endedAt: a.endedAt?.toISOString() ?? null,
      tzId: a.tzId,
      distanceM: a.distanceM,
      distanceSource: a.distanceSource,
      movingMs: a.movingMs,
      elapsedMs: a.elapsedMs,
      avgPaceSecPerKm: a.avgPaceSecPerKm,
      steps: a.steps,
      caloriesKcal: a.caloriesKcal,
      calorieModel: a.calorieModel,
      title: a.title,
      feeling: a.feeling,
      privacy: a.privacy,
    };
    lines.push(cols.map((c) => csvCell(row[c])).join(","));
  }
  files["activities.csv"] = strToU8(lines.join("\n") + "\n");
  files["profile.json"] = strToU8(JSON.stringify(profile ? toProfileDto(profile) : null, null, 2));
  files["goals.json"] = strToU8(JSON.stringify(goals.map(toGoalDto), null, 2));

  const byId = new Map(activities.map((a) => [a.id, a]));
  for (const t of tracks) {
    if (!t.storageKey) continue;
    const bytes = await storage().get(t.storageKey);
    const a = byId.get(t.activityId);
    if (!bytes || !a) continue;
    const merged = JSON.parse(new TextDecoder().decode(bytes)) as MergedTrack;
    const gpx = buildGpx(merged, { name: a.title, type: a.type, startedAt: a.startedAt.getTime() });
    if (gpx) files[`gpx/${a.id}.gpx`] = strToU8(gpx);
  }
  files["README.txt"] = strToU8(
    "STRIDE data export.\nUnits: distance in meters, durations in milliseconds, timestamps UTC.\nGPX files contain only recorded GPS segments (no gap filling).\n",
  );
  return zipSync(files, { level: 6 });
}

async function deleteAccountData(userId: string, jobId: string) {
  const s = storage();
  await s.deletePrefix(`tracks/${userId}`);
  await s.deletePrefix(`attachments/${userId}`);
  await s.deletePrefix(`exports/${userId}`);
  const ownedClubs = (await clubRepository.listOwnedBy(userId)).map((c) => c.id);
  await runInTransaction(async (tx) => {
    await trackChunkRepository.deleteAllOwned(userId, tx);
    await trackRepository.deleteAllOwned(userId, tx);
    await attachmentRepository.deleteAllOwned(userId, tx);
    await activityRepository.deleteAllOwned(userId, tx);
    await goalRepository.deleteAllOwned(userId, tx);
    await guestClaimRepository.deleteForUser(userId, tx);
    await changeLogRepository.deleteForUser(userId, tx);
    await idempotencyRepository.deleteForUser(userId, tx);
    await notificationRepository.deleteAllOwned(userId, tx);
    await feedbackRepository.deleteAllOwned(userId, tx);
    await postRepository.deleteAllForUser(userId, tx);
    await eventRepository.deleteAllForUser(userId, tx);
    await membershipRepository.deleteAllForUser(userId, tx);
    await clubRepository.deleteMany(ownedClubs, tx);
    await blockRepository.deleteAllForUser(userId, tx);
    await challengeRepository.deleteAllForUser(userId, tx);
    await routeRepository.deleteSavedForUser(userId, tx);
    await liveShareRepository.deleteAllForUser(userId, tx);
    await jobRepository.deleteOthersForUser(userId, jobId, tx);
    await profileRepository.delete(userId, tx);
    await emailTokenRepository.invalidateAll(userId, "verifyEmail", tx);
    await emailTokenRepository.invalidateAll(userId, "resetPassword", tx);
    await sessionRepository.revokeAllForUser(userId, "accountDeleted", tx);
    // Ẩn danh hóa định danh, giải phóng email để có thể đăng ký lại.
    await userRepository.update(
      userId,
      { status: "deleted", email: `deleted+${userId}@deleted.invalid`, passwordHash: "!", displayName: null },
      tx,
    );
  });
}

export const jobService = {
  async createExport(userId: string) {
    const open = await jobRepository.findOpen(userId, "export");
    if (open) return toJobDto(open);
    const job = await jobRepository.create(userId, "export");
    schedule(job.id);
    return toJobDto(job);
  },

  async getExport(userId: string, id: string) {
    const job = await jobRepository.findOwned(userId, id, "export");
    if (!job) throw notFound("Export");
    return toJobDto(job);
  },

  async downloadExport(userId: string, id: string) {
    const job = await jobRepository.findOwned(userId, id, "export");
    if (!job) throw notFound("Export");
    if (job.status !== "succeeded" || !job.resultKey) throw conflict("export_not_ready", "Export is not ready");
    if (job.expiresAt && job.expiresAt.getTime() <= Date.now()) throw gone("export_expired", "Export has expired");
    const bytes = await storage().get(job.resultKey);
    if (!bytes) throw gone("export_expired", "Export is no longer available");
    return bytes;
  },

  async requestDeletion(auth: AuthUser) {
    const open = await jobRepository.findOpen(auth.userId, "deleteAccount");
    if (open) return toJobDto(open);
    if (!auth.reauthAt || Date.now() - auth.reauthAt.getTime() > REAUTH_WINDOW_MS) {
      throw forbidden("reauth_required", "Please confirm your password before deleting the account");
    }
    const job = await runInTransaction(async (tx) => {
      await userRepository.update(auth.userId, { status: "deleting", deletionRequestedAt: new Date() }, tx);
      return jobRepository.create(auth.userId, "deleteAccount", tx);
    });
    schedule(job.id);
    return toJobDto(job);
  },

  async deletionStatus(userId: string) {
    const job = await jobRepository.latest(userId, "deleteAccount");
    if (!job) throw notFound("Deletion request");
    return toJobDto(job);
  },

  async run(jobId: string) {
    if (!(await jobRepository.claim(jobId))) return;
    const job = (await jobRepository.findById(jobId))!;
    try {
      if (job.kind === "export") {
        const zip = await buildExport(job.ownerId);
        const key = `exports/${job.ownerId}/${job.id}.zip`;
        await storage().put(key, zip);
        await jobRepository.finish(job.id, { status: "succeeded", resultKey: key, expiresAt: new Date(Date.now() + EXPORT_TTL_MS) });
        await notificationRepository.create({
          ownerId: job.ownerId,
          kind: "exportReady",
          title: "Your data export is ready",
          body: "Download it within 7 days.",
          deepLink: `stride://exports/${job.id}`,
        });
      } else if (job.kind === "deleteAccount") {
        await deleteAccountData(job.ownerId, job.id);
        await jobRepository.finish(job.id, { status: "succeeded" });
      } else {
        throw new AppError(500, "unknown_job", `Unknown job kind ${job.kind}`);
      }
    } catch (err) {
      logger.error("job_failed", { jobId, kind: job.kind, err });
      await jobRepository.finish(job.id, { status: "failed", error: err instanceof Error ? err.message.slice(0, 500) : "error" });
    }
  },

  async processPending() {
    let processed = 0;
    for (const j of await jobRepository.listQueued()) {
      await this.run(j.id);
      processed++;
    }
    return processed;
  },
};
