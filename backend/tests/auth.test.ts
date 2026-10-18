import { describe, expect, it } from "vitest";
import { memoryMailer } from "@/lib/mailer";
import { api, lastMailToken, randomUUID, registerUser, routePatterns } from "./helpers";

describe("E02 identity", () => {
  it("registers, verifies email, logs in", async () => {
    const u = await registerUser();
    const me = await api("GET", "/api/v1/me", { token: u.token });
    expect(me.status).toBe(200);
    expect(me.body.user.emailVerified).toBe(false);
    expect(me.body.user).not.toHaveProperty("passwordHash");
    expect(me.body.profile.revision).toBe(1);

    const token = lastMailToken(u.email);
    const v = await api("POST", "/api/v1/auth/verify-email", { body: { token } });
    expect(v.status).toBe(200);
    expect(v.body.user.emailVerified).toBe(true);
    // Token chỉ dùng một lần.
    expect((await api("POST", "/api/v1/auth/verify-email", { body: { token } })).status).toBe(400);

    const login = await api("POST", "/api/v1/auth/login", { body: { email: u.email, password: u.password } });
    expect(login.status).toBe(200);
    expect(login.body.tokens.refreshToken).toBeTruthy();
  });

  it("enforces password rule and rejects duplicates", async () => {
    for (const password of ["short1", "allletters", "12345678"]) {
      const r = await api("POST", "/api/v1/auth/register", { body: { email: `x-${randomUUID()}@example.com`, password } });
      expect(r.status).toBe(422);
      expect(r.body.error.code).toBe("validation_error");
    }
    const u = await registerUser();
    const dup = await api("POST", "/api/v1/auth/register", { body: { email: u.email, password: "another123" } });
    expect(dup.status).toBe(409);
  });

  it("rejects wrong password with generic error", async () => {
    const u = await registerUser();
    const bad = await api("POST", "/api/v1/auth/login", { body: { email: u.email, password: "wrong1234" } });
    const unknown = await api("POST", "/api/v1/auth/login", { body: { email: "nobody@example.com", password: "wrong1234" } });
    expect(bad.status).toBe(401);
    expect(unknown.status).toBe(401);
    expect(bad.body.error.code).toBe(unknown.body.error.code);
  });

  it("rotates refresh tokens and revokes the family on reuse", async () => {
    const u = await registerUser();
    const r1 = await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: u.refreshToken } });
    expect(r1.status).toBe(200);
    const second = r1.body.tokens.refreshToken as string;
    expect(second).not.toBe(u.refreshToken);

    // Trình lại token cũ => phát hiện reuse => thu hồi cả session.
    const reuse = await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: u.refreshToken } });
    expect(reuse.status).toBe(401);
    expect(reuse.body.error.code).toBe("refresh_token_reused");
    const afterReuse = await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: second } });
    expect(afterReuse.status).toBe(401);
    // Access token của session bị thu hồi cũng hết hiệu lực ngay.
    expect((await api("GET", "/api/v1/me", { token: r1.body.tokens.accessToken })).status).toBe(401);
  });

  it("logout revokes the session", async () => {
    const u = await registerUser();
    expect((await api("POST", "/api/v1/auth/logout", { token: u.token })).status).toBe(200);
    expect((await api("GET", "/api/v1/me", { token: u.token })).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/refresh", { body: { refreshToken: u.refreshToken } })).status).toBe(401);
  });

  it("forgot password does not reveal account existence; reset revokes sessions", async () => {
    const u = await registerUser();
    const before = memoryMailer().outbox.length;
    const unknown = await api("POST", "/api/v1/auth/forgot-password", { body: { email: `none-${randomUUID()}@example.com` } });
    expect(memoryMailer().outbox.length).toBe(before);
    const known = await api("POST", "/api/v1/auth/forgot-password", { body: { email: u.email } });
    expect(unknown.status).toBe(202);
    expect(known.status).toBe(202);
    expect(known.body).toEqual(unknown.body);

    const token = lastMailToken(u.email);
    const weak = await api("POST", "/api/v1/auth/reset-password", { body: { token, newPassword: "weak" } });
    expect(weak.status).toBe(422);
    const ok = await api("POST", "/api/v1/auth/reset-password", { body: { token, newPassword: "newpass456" } });
    expect(ok.status).toBe(200);
    expect((await api("GET", "/api/v1/me", { token: u.token })).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/login", { body: { email: u.email, password: u.password } })).status).toBe(401);
    expect((await api("POST", "/api/v1/auth/login", { body: { email: u.email, password: "newpass456" } })).status).toBe(200);
    expect((await api("POST", "/api/v1/auth/reset-password", { body: { token, newPassword: "again789x" } })).status).toBe(400);
  });

  it("reauth checks the password", async () => {
    const u = await registerUser();
    expect((await api("POST", "/api/v1/auth/reauth", { token: u.token, body: { password: "nope12345" } })).status).toBe(401);
    const ok = await api("POST", "/api/v1/auth/reauth", { token: u.token, body: { password: u.password } });
    expect(ok.status).toBe(200);
    expect(ok.body.reauthUntil).toBeGreaterThan(Date.now());
  });

  it("rate limits auth endpoints", async () => {
    process.env.RATE_LIMIT_AUTH_PER_MIN = "3";
    try {
      const statuses: number[] = [];
      for (let i = 0; i < 5; i++) {
        const r = await api("POST", "/api/v1/auth/login", { ip: "203.0.113.9", body: { email: "rl@example.com", password: "whatever1" } });
        statuses.push(r.status);
        if (r.status === 429) expect(r.headers.get("retry-after")).toBeTruthy();
      }
      expect(statuses.slice(0, 3)).toEqual([401, 401, 401]);
      expect(statuses[3]).toBe(429);
    } finally {
      process.env.RATE_LIMIT_AUTH_PER_MIN = "10000";
    }
  });

  it("has no Apple route stubs; Google only via /auth/firebase", () => {
    expect(routePatterns.some((p) => /apple|google|oauth/i.test(p))).toBe(false);
    expect(routePatterns).toContain("/api/v1/auth/firebase");
  });

  it("requires auth and returns error envelope", async () => {
    const r = await api("GET", "/api/v1/me");
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ error: { code: "unauthorized", message: expect.any(String) } });
    expect(r.headers.get("x-content-type-options")).toBe("nosniff");
    const bad = await api("GET", "/api/v1/me", { token: "garbage.token.value" });
    expect(bad.status).toBe(401);
  });
});
