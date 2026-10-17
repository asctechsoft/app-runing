import { z } from "zod";
import { activityType, epochMs, latitude, longitude, privacyLevel, tzId, uuid } from "./common";

export const activityStatus = z.enum(["recording", "paused", "awaitingSave", "saved", "discarded", "recoveryNeeded"]);
export const feeling = z.enum(["easy", "steady", "hard"]);
const MAX_MS = 7 * 24 * 3600 * 1000;

export const goalSchema = z.object({
  type: z.enum(["free", "distance", "time"]),
  value: z.number().positive().nullable().optional(),
});

export const activityBody = z
  .object({
    type: activityType,
    status: activityStatus,
    startedAt: epochMs,
    endedAt: epochMs.nullable().optional(),
    tzId,
    tzOffsetMin: z.number().int().min(-840).max(840),
    // Thiếu dữ liệu = null, không dùng 0 thay thế.
    distanceM: z.number().min(0).max(1_000_000).nullable().optional(),
    movingMs: z.number().int().min(0).max(MAX_MS),
    elapsedMs: z.number().int().min(0).max(MAX_MS),
    avgPaceSecPerKm: z.number().positive().max(100_000).nullable().optional(),
    steps: z.number().int().min(0).max(2_000_000).nullable().optional(),
    caloriesKcal: z.number().min(0).max(50_000).nullable().optional(),
    calorieModel: z.string().max(20).nullable().optional(),
    weightKgUsed: z.number().min(20).max(400).nullable().optional(),
    title: z.string().trim().min(1).max(120),
    feeling: feeling.nullable().optional(),
    notes: z.string().max(2000).nullable().optional(),
    privacy: privacyLevel.default("onlyMe"),
    shareRoute: z.boolean().default(false),
    goal: goalSchema.nullable().optional(),
    hasGps: z.boolean(),
    distanceSource: z.enum(["gps", "steps", "manual"]),
    workoutExecutionId: uuid.nullable().optional(),
  })
  .superRefine((a, ctx) => {
    if (a.endedAt != null && a.endedAt < a.startedAt) {
      ctx.addIssue({ code: "custom", path: ["endedAt"], message: "endedAt must be >= startedAt" });
    }
    if (a.status === "saved" && a.endedAt == null) {
      ctx.addIssue({ code: "custom", path: ["endedAt"], message: "Saved activity requires endedAt" });
    }
    if (a.movingMs > a.elapsedMs) {
      ctx.addIssue({ code: "custom", path: ["movingMs"], message: "movingMs must be <= elapsedMs" });
    }
    // Pace thiếu dữ liệu phải là null (hiển thị "—"), không suy diễn khi quãng đường < 10 m.
    if (a.avgPaceSecPerKm != null && (a.distanceM == null || a.distanceM < 10)) {
      ctx.addIssue({ code: "custom", path: ["avgPaceSecPerKm"], message: "Pace requires distanceM >= 10" });
    }
    if (a.type === "indoorRun" && a.hasGps) {
      ctx.addIssue({ code: "custom", path: ["hasGps"], message: "Indoor run has no GPS" });
    }
    if (a.caloriesKcal != null && (a.calorieModel == null || a.weightKgUsed == null)) {
      ctx.addIssue({ code: "custom", path: ["caloriesKcal"], message: "Calories require calorieModel and weightKgUsed" });
    }
  });
export type ActivityBody = z.infer<typeof activityBody>;

export const upsertActivitySchema = z.object({
  activity: activityBody,
  expectedRevision: z.number().int().min(1).optional(),
});

export const patchActivitySchema = z
  .object({
    expectedRevision: z.number().int().min(1),
    title: z.string().trim().min(1).max(120).optional(),
    feeling: feeling.nullable().optional(),
    notes: z.string().max(2000).nullable().optional(),
    privacy: privacyLevel.optional(),
    shareRoute: z.boolean().optional(),
    status: z.enum(["saved", "discarded"]).optional(),
    endedAt: epochMs.optional(),
  })
  .refine((p) => Object.keys(p).length > 1, "Nothing to update");
export type PatchActivityInput = z.infer<typeof patchActivitySchema>;

export const deleteQuery = z.object({ expectedRevision: z.coerce.number().int().min(1).optional() });

export const listActivitiesQuery = z.object({
  cursor: z.string().max(500).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  includeDeleted: z.enum(["true", "false"]).optional(),
});

// Track chunk (H02). Mỗi chunk chứa định nghĩa segment (nếu bắt đầu trong chunk) và các point.
export const segmentSchema = z.object({
  id: uuid,
  seq: z.number().int().min(0).max(100_000),
  startedAt: epochMs,
  endedAt: epochMs.nullable().optional(),
  reason: z.enum(["start", "resume", "gpsGap", "recovery"]),
});

export const trackPointSchema = z.object({
  segmentId: uuid,
  seq: z.number().int().min(0),
  t: epochMs,
  lat: latitude,
  lon: longitude,
  accuracyM: z.number().min(0).max(10_000).nullable().optional(),
  altitudeM: z.number().min(-1000).max(10_000).nullable().optional(),
  speedMps: z.number().min(0).max(200).nullable().optional(),
  accepted: z.boolean(),
  rejectReason: z.string().max(40).nullable().optional(),
});
export type TrackPoint = z.infer<typeof trackPointSchema>;
export type TrackSegment = z.infer<typeof segmentSchema>;

export const trackChunkSchema = z.object({
  segments: z.array(segmentSchema).max(1000).default([]),
  points: z.array(trackPointSchema).max(20_000),
});

export const chunkParams = z.object({ id: uuid, seq: z.coerce.number().int().min(0).max(9_999) });
export const finalizeTrackSchema = z.object({ totalChunks: z.number().int().min(1).max(10_000) });
export const MAX_CHUNK_BYTES = 2 * 1024 * 1024;
