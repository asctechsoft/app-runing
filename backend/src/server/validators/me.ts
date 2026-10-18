import { z } from "zod";
import { localDateStr, uuid } from "./common";

export const stepSource = z
  .string()
  .regex(/^(phoneSensor|healthConnect|healthKit|device:[A-Za-z0-9_\-:]{1,64})$/, "Invalid step source");

export const audioCuesSchema = z.object({
  enabled: z.boolean(),
  everyKm: z.number().positive().max(10),
  voice: z.string().max(64).nullable(),
});

export const profileFields = z.object({
  displayName: z.string().trim().min(1).max(60).nullable(),
  heightCm: z.number().min(50).max(272).nullable(),
  weightKg: z.number().min(20).max(400).nullable(),
  activityLevel: z.enum(["new", "occasional", "regular", "active"]).nullable(),
  runningExperience: z.string().max(40).nullable(),
  distanceUnit: z.enum(["km", "mi"]),
  weightUnit: z.enum(["kg", "lb"]),
  heightUnit: z.enum(["cm", "ftin"]),
  weekStart: z.number().int().min(1).max(7),
  locale: z.string().min(2).max(20),
  audioCues: audioCuesSchema,
  autoPause: z.boolean(),
});

export const updateProfileSchema = profileFields.partial().extend({
  expectedRevision: z.number().int().min(1),
});
export type UpdateProfileInput = z.infer<typeof updateProfileSchema>;

export const sourcePrioritySchema = z.object({
  expectedRevision: z.number().int().min(1),
  priorities: z
    .array(stepSource)
    .min(1)
    .max(10)
    .refine((a) => new Set(a).size === a.length, "Duplicate sources"),
});

export const goalTypes = ["dailySteps", "weeklyRuns", "weeklyDistanceM"] as const;
export const createGoalSchema = z
  .object({
    id: uuid.optional(),
    type: z.enum(goalTypes),
    value: z.number().positive(),
    effectiveFrom: localDateStr,
  })
  .superRefine((g, ctx) => {
    const max = g.type === "dailySteps" ? 200_000 : g.type === "weeklyRuns" ? 50 : 1_000_000;
    if (g.value > max) ctx.addIssue({ code: "custom", path: ["value"], message: `Must be <= ${max}` });
    if (g.type !== "weeklyDistanceM" && !Number.isInteger(g.value)) {
      ctx.addIssue({ code: "custom", path: ["value"], message: "Must be an integer" });
    }
  });
export type CreateGoalInput = z.infer<typeof createGoalSchema>;

export const claimGuestSchema = z.object({
  guestId: z.string().regex(/^guest:[0-9a-fA-F-]{36}$/, "Expected guest:<uuid>"),
  activityIds: z.array(uuid).min(1).max(500),
});
