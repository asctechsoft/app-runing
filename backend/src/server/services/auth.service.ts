import bcrypt from "bcryptjs";
import type { User } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { appLinkBase, intEnv } from "@/lib/env";
import { AppError, conflict, unauthorized } from "@/lib/errors";
import { logger } from "@/lib/logger";
import { mailer } from "@/lib/mailer";
import { isUniqueViolation, runInTransaction } from "@/lib/prisma";
import { limitAuth } from "@/lib/rate-limit";
import { maskEmail } from "@/lib/redact";
import {
  emailTokenRepository,
  refreshTokenRepository,
  sessionRepository,
  userRepository,
} from "@/server/repositories/auth.repository";
import { ACCESS_TTL_SEC, REFRESH_TTL_MS, hashOpaqueToken, newOpaqueToken, signAccessToken } from "@/server/auth/tokens";
import {
  forgotSchema,
  loginSchema,
  reauthSchema,
  refreshSchema,
  registerSchema,
  resetSchema,
  tokenSchema,
} from "@/server/validators/auth";

const VERIFY_TTL_MS = 24 * 3600 * 1000;
const RESET_TTL_MS = 30 * 60 * 1000;
export const REAUTH_WINDOW_MS = 5 * 60 * 1000;

const rounds = () => intEnv("BCRYPT_ROUNDS", 12);
// Hash giả để so sánh khi email không tồn tại -> thời gian phản hồi tương đương (không lộ tài khoản).
let dummyHash: string | null = null;
const getDummyHash = () => (dummyHash ??= bcrypt.hashSync("dummy-password-1", rounds()));

export function toUserDto(u: User) {
  return {
    id: u.id,
    email: u.email,
    emailVerified: u.emailVerifiedAt !== null,
    displayName: u.displayName,
    createdAt: u.createdAt.getTime(),
  };
}

async function issueTokens(userId: string, sessionId: string) {
  const access = await signAccessToken({ userId, sessionId });
  const refresh = newOpaqueToken();
  await refreshTokenRepository.create({
    sessionId,
    userId,
    tokenHash: refresh.hash,
    expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
  });
  return {
    accessToken: access.token,
    accessTokenExpiresAt: access.expiresAt,
    expiresIn: ACCESS_TTL_SEC,
    refreshToken: refresh.token,
    tokenType: "Bearer" as const,
  };
}

async function sendVerification(user: User) {
  const t = newOpaqueToken();
  await emailTokenRepository.create({
    userId: user.id,
    purpose: "verifyEmail",
    tokenHash: t.hash,
    expiresAt: new Date(Date.now() + VERIFY_TTL_MS),
  });
  const link = `${appLinkBase()}/verify-email?token=${t.token}`;
  await mailer().send({
    to: user.email,
    subject: "Verify your STRIDE email",
    text: `Open this link to verify your email: ${link}`,
    actionUrl: link,
  });
}

export const authService = {
  async register(raw: unknown, ip: string) {
    const input = registerSchema.parse(raw);
    await limitAuth("register", ip);
    const passwordHash = await bcrypt.hash(input.password, rounds());
    let user: User;
    try {
      user = await userRepository.create({
        id: newId(),
        email: input.email,
        passwordHash,
        displayName: input.displayName ?? null,
      });
    } catch (err) {
      if (isUniqueViolation(err)) throw conflict("email_taken", "An account with this email already exists");
      throw err;
    }
    await sendVerification(user);
    const session = await sessionRepository.create(user.id);
    logger.info("user_registered", { userId: user.id, email: maskEmail(user.email) });
    return { user: toUserDto(user), tokens: await issueTokens(user.id, session.id) };
  },

  async verifyEmail(raw: unknown, ip: string) {
    const { token } = tokenSchema.parse(raw);
    await limitAuth("verify", ip);
    const record = await emailTokenRepository.findValid(hashOpaqueToken(token), "verifyEmail");
    if (!record || (await emailTokenRepository.consume(record.id)) === 0) {
      throw new AppError(400, "invalid_token", "Verification link is invalid or expired");
    }
    const user = await userRepository.update(record.userId, { emailVerifiedAt: new Date() });
    return { user: toUserDto(user) };
  },

  async resendVerification(userId: string) {
    const user = await userRepository.findById(userId);
    if (!user) throw unauthorized();
    if (!user.emailVerifiedAt) {
      await emailTokenRepository.invalidateAll(user.id, "verifyEmail");
      await sendVerification(user);
    }
    return { ok: true };
  },

  async login(raw: unknown, ip: string) {
    const input = loginSchema.parse(raw);
    await limitAuth("login", ip, input.email);
    const user = await userRepository.findByEmail(input.email);
    const valid = await bcrypt.compare(input.password, user?.passwordHash ?? getDummyHash());
    if (!user || !valid || user.status !== "active") {
      throw unauthorized("invalid_credentials", "Email or password is incorrect");
    }
    const session = await sessionRepository.create(user.id);
    return { user: toUserDto(user), tokens: await issueTokens(user.id, session.id) };
  },

  /** Refresh xoay vòng. Token đã dùng bị trình lại => thu hồi cả family (session). */
  async refresh(raw: unknown, ip: string) {
    const { refreshToken } = refreshSchema.parse(raw);
    await limitAuth("refresh", ip);
    const record = await refreshTokenRepository.findByHash(hashOpaqueToken(refreshToken));
    if (!record) throw unauthorized("invalid_refresh_token", "Refresh token is invalid");
    if (record.session.revokedAt) throw unauthorized("invalid_refresh_token", "Session has been revoked");
    if (record.usedAt || (await refreshTokenRepository.markUsed(record.id)) === 0) {
      await sessionRepository.revoke(record.sessionId, "reuse");
      logger.warn("refresh_token_reuse_detected", { userId: record.userId, sessionId: record.sessionId });
      throw unauthorized("refresh_token_reused", "Refresh token reuse detected; session revoked");
    }
    if (record.expiresAt.getTime() <= Date.now()) {
      throw unauthorized("invalid_refresh_token", "Refresh token expired");
    }
    const user = await userRepository.findById(record.userId);
    if (!user || user.status !== "active") throw unauthorized("invalid_refresh_token", "Account unavailable");
    return { user: toUserDto(user), tokens: await issueTokens(user.id, record.sessionId) };
  },

  async logout(sessionId: string) {
    await sessionRepository.revoke(sessionId, "logout");
    return { ok: true };
  },

  /** Luôn trả cùng một phản hồi, không tiết lộ email có tồn tại hay không. */
  async forgotPassword(raw: unknown, ip: string) {
    const { email } = forgotSchema.parse(raw);
    await limitAuth("forgot", ip, email);
    const user = await userRepository.findByEmail(email);
    if (user && user.status === "active") {
      await emailTokenRepository.invalidateAll(user.id, "resetPassword");
      const t = newOpaqueToken();
      await emailTokenRepository.create({
        userId: user.id,
        purpose: "resetPassword",
        tokenHash: t.hash,
        expiresAt: new Date(Date.now() + RESET_TTL_MS),
      });
      const link = `${appLinkBase()}/reset-password?token=${t.token}`;
      await mailer().send({
        to: user.email,
        subject: "Reset your STRIDE password",
        text: `Open this link to reset your password (valid 30 minutes): ${link}`,
        actionUrl: link,
      });
    }
    return { ok: true, message: "If an account exists for this email, a reset link has been sent." };
  },

  async resetPassword(raw: unknown, ip: string) {
    const input = resetSchema.parse(raw);
    await limitAuth("reset", ip);
    const record = await emailTokenRepository.findValid(hashOpaqueToken(input.token), "resetPassword");
    if (!record) throw new AppError(400, "invalid_token", "Reset link is invalid or expired");
    const passwordHash = await bcrypt.hash(input.newPassword, rounds());
    await runInTransaction(async (tx) => {
      if ((await emailTokenRepository.consume(record.id, tx)) === 0) {
        throw new AppError(400, "invalid_token", "Reset link is invalid or expired");
      }
      await userRepository.update(record.userId, { passwordHash }, tx);
      // Đổi mật khẩu => đăng xuất mọi thiết bị.
      await sessionRepository.revokeAllForUser(record.userId, "passwordReset", tx);
    });
    return { ok: true };
  },

  /** Xác thực lại bằng mật khẩu, mở cửa sổ 5 phút cho thao tác nhạy cảm (xóa tài khoản). */
  async reauth(userId: string, sessionId: string, raw: unknown, ip: string) {
    const { password } = reauthSchema.parse(raw);
    await limitAuth("reauth", ip, userId);
    const user = await userRepository.findById(userId);
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      throw unauthorized("invalid_credentials", "Password is incorrect");
    }
    const s = await sessionRepository.markReauth(sessionId);
    return { reauthUntil: (s.reauthAt?.getTime() ?? Date.now()) + REAUTH_WINDOW_MS };
  },
};
