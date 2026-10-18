import { z } from "zod";
import { isValidTimeZone } from "@/lib/time";

export const uuid = z.string().uuid();
/** UTC epoch ms (2000-01-01 .. 2100-01-01). */
export const epochMs = z.number().int().min(946_684_800_000).max(4_102_444_800_000);
export const tzId = z.string().min(1).max(64).refine(isValidTimeZone, "Invalid IANA time zone");
export const localDateStr = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Expected YYYY-MM-DD")
  .refine((s) => !Number.isNaN(Date.parse(`${s}T00:00:00Z`)), "Invalid date");
export const latitude = z.number().min(-90).max(90);
export const longitude = z.number().min(-180).max(180);
export const shortText = (max: number) => z.string().trim().max(max);

export const idParam = z.object({ id: uuid });

export const activityTypes = ["run", "walk", "indoorRun"] as const;
export const activityType = z.enum(activityTypes);
export const privacyLevel = z.enum(["onlyMe", "followers", "public"]);
