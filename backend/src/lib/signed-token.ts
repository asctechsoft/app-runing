import { SignJWT, jwtVerify } from "jose";
import { jwtSecret } from "@/lib/env";

// Token ký số ngắn hạn cho URL upload/download (H05, H06). Audience tách biệt với access token.
export type SignedPurpose = "upload" | "download";

export async function signPurposeToken(
  purpose: SignedPurpose,
  claims: Record<string, string | number>,
  ttlSec: number,
): Promise<{ token: string; expiresAt: number }> {
  const expiresAt = Date.now() + ttlSec * 1000;
  const token = await new SignJWT(claims)
    .setProtectedHeader({ alg: "HS256" })
    .setAudience(`stride:${purpose}`)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt / 1000))
    .sign(jwtSecret());
  return { token, expiresAt };
}

export async function verifyPurposeToken(purpose: SignedPurpose, token: string): Promise<Record<string, unknown> | null> {
  try {
    const { payload } = await jwtVerify(token, jwtSecret(), { audience: `stride:${purpose}`, algorithms: ["HS256"] });
    return payload as Record<string, unknown>;
  } catch {
    return null;
  }
}
