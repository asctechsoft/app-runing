import { z } from "zod";
import { activityTypes, epochMs, latitude, localDateStr, longitude, tzId, uuid } from "./common";

// ---- Attachments (H05)
export const ALLOWED_IMAGE_MIME = ["image/jpeg", "image/png", "image/heic", "image/webp"] as const;
export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
export const requestAttachmentSchema = z.object({
  id: uuid,
  mime: z.enum(ALLOWED_IMAGE_MIME),
  bytes: z.number().int().min(1).max(MAX_ATTACHMENT_BYTES),
  sha256: z.string().regex(/^[a-f0-9]{64}$/).optional(),
});

// ---- Sync (H03/H04)
export const syncOperationSchema = z.object({
  idempotencyKey: z.string().regex(/^[A-Za-z0-9_\-:.]{8,128}$/),
  entity: z.enum(["activity", "profile", "goal"]),
  op: z.enum(["upsert", "delete"]),
  entityId: uuid,
  expectedRevision: z.number().int().min(1).optional(),
  payload: z.unknown().optional(),
});
export type SyncOperation = z.infer<typeof syncOperationSchema>;
export const syncPushSchema = z.object({ operations: z.array(syncOperationSchema).min(1).max(100) });
export const syncPullQuery = z.object({
  cursor: z.string().regex(/^\d{1,15}$/).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

// ---- Clubs / feed / events (M01–M03)
export const createClubSchema = z.object({
  name: z.string().trim().min(2).max(80),
  description: z.string().trim().max(1000).default(""),
  regionText: z.string().trim().min(2).max(120),
  lat: latitude.nullable().optional(),
  lon: longitude.nullable().optional(),
});
export const clubSearchQuery = z
  .object({
    q: z.string().trim().max(80).optional(),
    region: z.string().trim().max(120).optional(),
    minLat: z.coerce.number().min(-90).max(90).optional(),
    maxLat: z.coerce.number().min(-90).max(90).optional(),
    minLon: z.coerce.number().min(-180).max(180).optional(),
    maxLon: z.coerce.number().min(-180).max(180).optional(),
    cursor: z.string().max(500).optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
  })
  .refine(
    (q) => {
      const box = [q.minLat, q.maxLat, q.minLon, q.maxLon];
      const n = box.filter((v) => v !== undefined).length;
      return n === 0 || (n === 4 && q.minLat! <= q.maxLat! && q.minLon! <= q.maxLon!);
    },
    "Bounding box needs minLat<=maxLat and minLon<=maxLon",
  );
export const memberParams = z.object({ id: uuid, userId: uuid });
export const roleSchema = z.object({ role: z.enum(["mod", "member"]) });
export const createPostSchema = z
  .object({
    id: uuid.optional(),
    text: z.string().trim().max(2000).default(""),
    activityId: uuid.nullable().optional(),
  })
  .refine((p) => p.text.length > 0 || p.activityId, "Post needs text or activityId");
export const commentSchema = z.object({ text: z.string().trim().min(1).max(1000) });
export const reportSchema = z.object({
  targetType: z.enum(["post", "comment", "user"]),
  targetId: uuid,
  reason: z.string().trim().min(1).max(500),
});
export const blockSchema = z.object({ userId: uuid });
export const createEventSchema = z
  .object({
    title: z.string().trim().min(2).max(120),
    description: z.string().trim().max(2000).default(""),
    startAt: epochMs,
    endAt: epochMs.nullable().optional(),
    tzId,
    meetingPlace: z.string().trim().min(2).max(200),
  })
  .refine((e) => e.endAt == null || e.endAt >= e.startAt, { message: "endAt must be >= startAt", path: ["endAt"] });

// ---- Challenges (M04)
export const challengeJoinSchema = z.object({ leaderboardOptIn: z.boolean().default(false) });
export const optInSchema = z.object({ leaderboardOptIn: z.boolean() });
export const challengeRuleSchema = z.object({
  activityTypes: z.array(z.enum(activityTypes)).min(1),
  startDate: localDateStr,
  endDate: localDateStr,
  tzId,
  targetType: z.enum(["distance", "count", "time"]),
  targetValue: z.number().positive(),
});

// ---- Routes (M05)
export const routeSearchQuery = z.object({
  region: z.string().trim().max(120).optional(),
  minDistanceM: z.coerce.number().min(0).optional(),
  maxDistanceM: z.coerce.number().min(0).optional(),
  surface: z.enum(["road", "trail", "track", "mixed"]).optional(),
  cursor: z.string().max(500).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

// ---- Live sharing (M06/M07)
export const startLiveShareSchema = z.object({
  activityId: uuid,
  viewerIds: z
    .array(uuid)
    .min(1)
    .max(20)
    .refine((a) => new Set(a).size === a.length, "Duplicate viewers"),
  ttlMinutes: z.number().int().min(5).max(12 * 60).default(240),
});
export const livePointSchema = z.object({
  t: epochMs,
  lat: latitude,
  lon: longitude,
  accuracyM: z.number().min(0).max(10_000).nullable().optional(),
  distanceM: z.number().min(0).max(1_000_000).nullable().optional(),
  elapsedMs: z.number().int().min(0).nullable().optional(),
  status: z.enum(["active", "paused"]).optional(),
});

// ---- Users lookup / feedback
export const userLookupQuery = z.object({ email: z.string().trim().toLowerCase().email().max(254) });
export const feedbackSchema = z.object({
  message: z.string().trim().min(1).max(4000),
  diagnostics: z.string().max(8000).optional(),
  appVersion: z.string().trim().max(40).optional(),
});
