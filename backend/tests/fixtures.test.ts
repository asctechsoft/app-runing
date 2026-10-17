import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { ZodTypeAny } from "zod";
import { patchActivitySchema, trackChunkSchema, finalizeTrackSchema, upsertActivitySchema } from "@/server/validators/activity";
import { registerSchema } from "@/server/validators/auth";
import { claimGuestSchema, createGoalSchema, updateProfileSchema } from "@/server/validators/me";
import { feedbackSchema, livePointSchema, requestAttachmentSchema, startLiveShareSchema, syncPushSchema } from "@/server/validators/misc";

// C06: fixture dùng chung với mobile phải luôn hợp lệ theo schema server.
const load = (name: string): unknown => JSON.parse(readFileSync(path.resolve(__dirname, "../fixtures", name), "utf8"));

const requestFixtures: Array<[string, ZodTypeAny]> = [
  ["activity-upsert.request.json", upsertActivitySchema],
  ["activity-update.request.json", upsertActivitySchema],
  ["activity-patch.request.json", patchActivitySchema],
  ["track-chunk.json", trackChunkSchema],
  ["track-finalize.request.json", finalizeTrackSchema],
  ["auth-register.request.json", registerSchema],
  ["profile-update.request.json", updateProfileSchema],
  ["goal-create.request.json", createGoalSchema],
  ["claim-guest.request.json", claimGuestSchema],
  ["sync-push.request.json", syncPushSchema],
  ["attachment-request.request.json", requestAttachmentSchema],
  ["live-share-start.request.json", startLiveShareSchema],
  ["live-point.request.json", livePointSchema],
  ["feedback.request.json", feedbackSchema],
];

describe("C06 shared fixtures", () => {
  it.each(requestFixtures)("%s matches the server schema", (name, schema) => {
    const r = schema.safeParse(load(name));
    expect(r.success, JSON.stringify(r.error?.issues)).toBe(true);
  });

  it("error fixtures follow the error envelope", () => {
    for (const name of ["error-envelope.json", "conflict.response.json", "track-incomplete.response.json", "user-not-found.response.json"]) {
      const body = load(name) as { error: { code: string; message: string } };
      expect(typeof body.error.code).toBe("string");
      expect(typeof body.error.message).toBe("string");
    }
  });
});
