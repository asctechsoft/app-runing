import { SignJWT, jwtVerify } from "jose";
import { jwtSecret } from "@/lib/env";
import { randomToken, sha256Hex } from "@/lib/crypto";

export const ACCESS_TTL_SEC = 15 * 60;
export const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const AUDIENCE = "stride:access";

export interface AccessClaims {
  userId: string;
  sessionId: string;
}

export async function signAccessToken(claims: AccessClaims): Promise<{ token: string; expiresAt: number }> {
  const expiresAt = Date.now() + ACCESS_TTL_SEC * 1000;
  const token = await new SignJWT({ sid: claims.sessionId })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(claims.userId)
    .setAudience(AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt / 1000))
    .sign(jwtSecret());
  return { token, expiresAt };
}

export async function verifyAccessToken(token: string): Promise<AccessClaims | null> {
  try {
    const { payload } = await jwtVerify(token, jwtSecret(), { audience: AUDIENCE, algorithms: ["HS256"] });
    if (typeof payload.sub !== "string" || typeof payload.sid !== "string") return null;
    return { userId: payload.sub, sessionId: payload.sid };
  } catch {
    return null;
  }
}

/** Refresh token là chuỗi ngẫu nhiên opaque; DB chỉ lưu hash. */
export function newOpaqueToken(): { token: string; hash: string } {
  const token = randomToken(32);
  return { token, hash: sha256Hex(token) };
}

export const hashOpaqueToken = (token: string): string => sha256Hex(token);
