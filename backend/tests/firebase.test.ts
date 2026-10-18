import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type CryptoKey, type JWK } from "jose";
import { memoryMailer } from "@/lib/mailer";
import { prisma } from "@/lib/prisma";
import { JoseFirebaseTokenVerifier, setFirebaseVerifierForTests } from "@/server/auth/firebase";
import { jobService } from "@/server/services/job.service";
import { api, lastMailToken, randomUUID, registerUser } from "./helpers";

// Dùng verifier THẬT (JoseFirebaseTokenVerifier) với khóa RSA sinh cục bộ + JWKS cục bộ thay cho JWKS của Google.
const PROJECT = "test-project";
let privateKey: CryptoKey;
let otherKey: CryptoKey;

interface TokenOpts {
  sub?: string;
  email?: string | null;
  emailVerified?: boolean;
  name?: string;
  provider?: string;
  iss?: string;
  aud?: string;
  authTime?: number;
  exp?: string | number;
  key?: CryptoKey;
}

async function idToken(o: TokenOpts = {}) {
  const now = Math.floor(Date.now() / 1000);
  const claims: Record<string, unknown> = {
    email_verified: o.emailVerified ?? true,
    auth_time: o.authTime ?? now - 10,
    firebase: { sign_in_provider: o.provider ?? "google.com", identities: {} },
  };
  if (o.email !== null) claims.email = o.email ?? `g-${randomUUID()}@gmail.com`;
  if (o.name) claims.name = o.name;
  return new SignJWT(claims)
    .setProtectedHeader({ alg: "RS256", kid: "test-kid" })
    .setIssuer(o.iss ?? `https://securetoken.google.com/${PROJECT}`)
    .setAudience(o.aud ?? PROJECT)
    .setSubject(o.sub ?? `uid-${randomUUID()}`)
    .setIssuedAt(now - 10)
    .setExpirationTime(o.exp ?? now + 3600)
    .sign(o.key ?? privateKey);
}

const login = (token: string) => api("POST", "/api/v1/auth/firebase", { body: { idToken: token } });

beforeAll(async () => {
  const pair = await generateKeyPair("RS256", { extractable: true });
  privateKey = pair.privateKey;
  otherKey = (await generateKeyPair("RS256")).privateKey;
  const jwk: JWK = { ...(await exportJWK(pair.publicKey)), kid: "test-kid", alg: "RS256", use: "sig" };
  setFirebaseVerifierForTests(new JoseFirebaseTokenVerifier(PROJECT, createLocalJWKSet({ keys: [jwk] })));
  process.env.FIREBASE_PROJECT_ID = PROJECT;
});

afterAll(() => {
  setFirebaseVerifierForTests(null);
  delete process.env.FIREBASE_PROJECT_ID;
});

describe("POST /auth/firebase (Google via Firebase)", () => {
  it("creates a new verified user without password, second login returns the same user", async () => {
    const sub = `uid-${randomUUID()}`;
    const email = `new-${randomUUID()}@gmail.com`;
    const first = await login(await idToken({ sub, email, name: "Lan Nguyen" }));
    expect(first.status).toBe(200);
    expect(first.body.user).toMatchObject({ email, emailVerified: true, displayName: "Lan Nguyen" });
    expect(first.body.tokens).toMatchObject({ accessToken: expect.any(String), refreshToken: expect.any(String), accessTokenExpiresAt: expect.any(Number) });
    const db = await prisma.user.findUnique({ where: { id: first.body.user.id } });
    expect(db?.passwordHash).toBeNull();

    const second = await login(await idToken({ sub, email }));
    expect(second.status).toBe(200);
    expect(second.body.user.id).toBe(first.body.user.id);
    expect(await prisma.authIdentity.count({ where: { providerUid: sub } })).toBe(1);

    // Cùng cơ chế refresh xoay vòng như /auth/login.
    expect((await api("GET", "/api/v1/me", { token: second.body.tokens.accessToken })).status).toBe(200);
    const r = await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: second.body.tokens.refreshToken } });
    expect(r.status).toBe(200);
    expect((await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: second.body.tokens.refreshToken } })).body.error.code).toBe("refresh_token_reused");
  });

  it("links to an existing account only when its email is verified", async () => {
    const verified = await registerUser();
    await api("POST", "/api/v1/auth/verify-email", { body: { token: lastMailToken(verified.email) } });
    const linked = await login(await idToken({ email: verified.email.toUpperCase() }));
    expect(linked.status).toBe(200);
    expect(linked.body.user.id).toBe(verified.userId);
    // Mật khẩu cũ vẫn dùng được.
    expect((await api("POST", "/api/v1/auth/login", { body: { email: verified.email, password: verified.password } })).status).toBe(200);

    const unverified = await registerUser();
    const refused = await login(await idToken({ email: unverified.email }));
    expect(refused.status).toBe(409);
    expect(refused.body.error.code).toBe("account_exists_unverified");
    expect(await prisma.authIdentity.count({ where: { userId: unverified.userId } })).toBe(0);

    const notVerifiedGoogle = await login(await idToken({ emailVerified: false }));
    expect(notVerifiedGoogle.status).toBe(422);
  });

  it("rejects wrong aud, iss, provider, foreign key, expired token and future auth_time", async () => {
    const now = Math.floor(Date.now() / 1000);
    const bad = [
      await idToken({ aud: "other-project" }),
      await idToken({ iss: "https://securetoken.google.com/other-project" }),
      await idToken({ iss: "https://accounts.google.com" }),
      await idToken({ provider: "password" }),
      await idToken({ provider: "apple.com" }),
      await idToken({ key: otherKey }),
      await idToken({ exp: now - 60 }),
      await idToken({ authTime: now + 600 }),
      await idToken({ sub: "x".repeat(129) }),
    ];
    for (const t of bad) {
      const r = await login(t);
      expect(r.status).toBe(401);
      expect(r.body.error.code).toBe("invalid_id_token");
    }
    expect((await login("not-a-jwt-but-long-enough-string")).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/firebase", { body: {} })).status).toBe(422);
  });

  it("returns 503 provider_not_configured when FIREBASE_PROJECT_ID is missing", async () => {
    const token = await idToken();
    delete process.env.FIREBASE_PROJECT_ID;
    try {
      const r = await login(token);
      expect(r.status).toBe(503);
      expect(r.body.error.code).toBe("provider_not_configured");
    } finally {
      process.env.FIREBASE_PROJECT_ID = PROJECT;
    }
  });

  it("password-less accounts: password login and forgot-password stay generic", async () => {
    const email = `g-${randomUUID()}@gmail.com`;
    await login(await idToken({ email }));
    const pw = await api("POST", "/api/v1/auth/login", { body: { email, password: "dummy-password-1" } });
    expect(pw.status).toBe(401);
    expect(pw.body.error.code).toBe("invalid_credentials");
    const before = memoryMailer().outbox.length;
    const forgot = await api("POST", "/api/v1/auth/forgot-password", { body: { email } });
    const unknown = await api("POST", "/api/v1/auth/forgot-password", { body: { email: `none-${randomUUID()}@gmail.com` } });
    expect(forgot.status).toBe(202);
    expect(forgot.body).toEqual(unknown.body);
    expect(memoryMailer().outbox.length).toBe(before);
  });

  it("reauth accepts the linked Google idToken and enables account deletion", async () => {
    const sub = `uid-${randomUUID()}`;
    const email = `g-${randomUUID()}@gmail.com`;
    const s = await login(await idToken({ sub, email }));
    const token = s.body.tokens.accessToken as string;
    // Token của identity Google khác => từ chối; mật khẩu => từ chối (không có mật khẩu).
    expect((await api("POST", "/api/v1/auth/reauth", { token, body: { idToken: await idToken() } })).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/reauth", { token, body: { password: "anything1" } })).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/reauth", { token, body: { idToken: await idToken({ sub, aud: "other" }) } })).status).toBe(401);
    const ok = await api("POST", "/api/v1/auth/reauth", { token, body: { idToken: await idToken({ sub, email }) } });
    expect(ok.status).toBe(200);
    expect((await api("POST", "/api/v1/me/deletion", { token })).status).toBe(202);

    // Đang xóa => đăng nhập Google bị 403.
    const during = await login(await idToken({ sub, email }));
    expect(during.status).toBe(403);
    expect(during.body.error.code).toBe("account_disabled");

    await jobService.processPending();
    expect(await prisma.authIdentity.count({ where: { providerUid: sub } })).toBe(0);
  });
});
