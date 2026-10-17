import { z } from "zod";

export const emailSchema = z.string().trim().toLowerCase().email().max(254);

// Quy tắc mật khẩu (E02): >= 8 ký tự, có chữ cái và chữ số; tối đa 72 byte (giới hạn bcrypt).
export const passwordSchema = z
  .string()
  .min(8, "Password must be at least 8 characters")
  .refine((p) => new TextEncoder().encode(p).length <= 72, "Password is too long")
  .refine((p) => /\p{L}/u.test(p), "Password must contain a letter")
  .refine((p) => /\p{N}/u.test(p), "Password must contain a number");

export const registerSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
  displayName: z.string().trim().min(1).max(60).optional(),
});

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(200),
});

export const refreshSchema = z.object({ refreshToken: z.string().min(16).max(200) });
export const tokenSchema = z.object({ token: z.string().min(16).max(200) });
export const forgotSchema = z.object({ email: emailSchema });
export const resetSchema = z.object({ token: z.string().min(16).max(200), newPassword: passwordSchema });
export const reauthSchema = z.object({ password: z.string().min(1).max(200) });
