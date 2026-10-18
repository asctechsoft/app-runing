import bcrypt from "bcryptjs";
import type { User } from "@prisma/client";
import { newId } from "@/lib/crypto";
import { appLinkBase, intEnv } from "@/lib/env";
import { AppError, conflict, forbidden, unauthorized } from "@/lib/errors";
import { logger } from "@/lib/logger";
import { mailer } from "@/lib/mailer";
import { isUniqueViolation, runInTransaction } from "@/lib/prisma";
import { limitAuth } from "@/lib/rate-limit";
import { maskEmail } from "@/lib/redact";
import {
  authIdentityRepository,
  emailTokenRepository,
  refreshTokenRepository,
  sessionRepository,
  userRepository,
} from "@/server/repositories/auth.repository";
import { firebaseVerifier } from "@/server/auth/firebase";
import { ACCESS_TTL_SEC, REFRESH_TTL_MS, hashOpaqueToken, newOpaqueToken, signAccessToken } from "@/server/auth/tokens";
import {
  firebaseLoginSchema,
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

const accountDisabled = () => forbidden("account_disabled", "This account is not available");

async function resolveGoogleUser(claims: { uid: string; email: string | null; emailVerified: boolean; name: string | null }) {
  return runInTransaction(async (tx) => {
    const identity = await authIdentityRepository.find("google", claims.uid, tx);
    if (identity) {
      const user = await userRepository.findById(identity.userId, tx);
      if (!user || user.status !== "active") throw accountDisabled();
      return { user, created: false };
    }
    if (!claims.email || !claims.emailVerified) {
      throw new AppError(422, "email_not_verified", "Google account email is missing or not verified");
    }
    const existing = await userRepository.findByEmail(claims.email, tx);
    if (existing) {
      if (existing.status !== "active") throw accountDisabled();
      // Không cho đăng nhập Google chiếm tài khoản mật khẩu chưa xác minh email.
      if (!existing.emailVerifiedAt) {
        throw conflict("account_exists_unverified", "An account with this email exists but its email is not verified");
      }
      await authIdentityRepository.create({ userId: existing.id, provider: "google", providerUid: claims.uid, email: claims.email }, tx);
      return { user: existing, created: false };
    }
    const user = await userRepository.create(
      { id: newId(), email: claims.email, passwordHash: null, displayName: claims.name, emailVerifiedAt: new Date() },
      tx,
    );
    await authIdentityRepository.create({ userId: user.id, provider: "google", providerUid: claims.uid, email: claims.email }, tx);
    return { user, created: true };
  });
}

export const authService = {
  /** Đăng nhập Google qua Firebase ID token. Không bao giờ log idToken. */
  async firebaseLogin(raw: unknown, ip: string) {
    const { idToken } = firebaseLoginSchema.parse(raw);
    await limitAuth("firebase", ip);
    const claims = await firebaseVerifier().verify(idToken);
    let result;
    try {
      result = await resolveGoogleUser(claims);
    } catch (err) {
      // Hai request song song cùng uid/email: lần sau đọc lại identity vừa tạo.
      if (!isUniqueViolation(err)) throw err;
      result = await resolveGoogleUser(claims);
    }
    const session = await sessionRepository.create(result.user.id);
    if (result.created) logger.info("user_registered_google", { userId: result.user.id, email: maskEmail(result.user.email) });
    return { user: toUserDto(result.user), tokens: await issueTokens(result.user.id, session.id) };
  },

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
    // Tài khoản chỉ có Google (không mật khẩu) => cùng lỗi chung, không lộ loại tài khoản.
    if (!user || !user.passwordHash || !valid || user.status !== "active") {
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
    // Tài khoản không mật khẩu (chỉ Google): không gửi link, phản hồi vẫn giống hệt.
    if (user && user.status === "active" && user.passwordHash) {
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
    const input = reauthSchema.parse(raw);
    await limitAuth("reauth", ip, userId);
    const user = await userRepository.findById(userId);
    if (!user) throw unauthorized("invalid_credentials", "Credentials are incorrect");
    if ("idToken" in input) {
      // Token Google phải thuộc đúng identity đã liên kết với tài khoản này.
      const claims = await firebaseVerifier().verify(input.idToken);
      const identity = await authIdentityRepository.find("google", claims.uid);
      if (!identity || identity.userId !== user.id) throw unauthorized("invalid_credentials", "Credentials are incorrect");
    } else if (!user.passwordHash || !(await bcrypt.compare(input.password, user.passwordHash))) {
      throw unauthorized("invalid_credentials", "Credentials are incorrect");
    }
    const s = await sessionRepository.markReauth(sessionId);
    return { reauthUntil: (s.reauthAt?.getTime() ?? Date.now()) + REAUTH_WINDOW_MS };
  },
};
