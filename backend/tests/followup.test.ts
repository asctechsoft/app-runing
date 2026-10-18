import { describe, expect, it } from "vitest";
import { prisma } from "@/lib/prisma";
import { activityBody, api, createActivity, lastMailToken, randomUUID, registerUser, type TestUser } from "./helpers";

async function verified(name = "Verified"): Promise<TestUser> {
  const u = await registerUser(name);
  await api("POST", "/api/v1/auth/verify-email", { body: { token: lastMailToken(u.email) } });
  return u;
}

describe("users lookup", () => {
  it("returns only {id, displayName} for active verified unblocked users; uniform 404 otherwise", async () => {
    const caller = await verified("Caller");
    const target = await verified("Target");
    const unverified = await registerUser("Unverified");

    const ok = await api("GET", `/api/v1/users/lookup?email=${encodeURIComponent(target.email.toUpperCase())}`, { token: caller.token });
    expect(ok.status).toBe(200);
    expect(ok.body).toEqual({ id: target.userId, displayName: "Target" });

    const cases = [
      `nobody-${randomUUID()}@example.com`, // không tồn tại
      unverified.email, // chưa xác minh email
      caller.email, // chính mình
    ];
    for (const email of cases) {
      const r = await api("GET", `/api/v1/users/lookup?email=${encodeURIComponent(email)}`, { token: caller.token });
      expect(r.status).toBe(404);
      expect(r.body.error.code).toBe("user_not_found");
    }
    // Chặn theo cả hai chiều => 404.
    await api("POST", "/api/v1/me/blocks", { token: target.token, body: { userId: caller.userId } });
    expect((await api("GET", `/api/v1/users/lookup?email=${encodeURIComponent(target.email)}`, { token: caller.token })).status).toBe(404);
    await api("DELETE", `/api/v1/me/blocks/${caller.userId}`, { token: target.token });
    await api("POST", "/api/v1/me/blocks", { token: caller.token, body: { userId: target.userId } });
    expect((await api("GET", `/api/v1/users/lookup?email=${encodeURIComponent(target.email)}`, { token: caller.token })).status).toBe(404);

    expect((await api("GET", `/api/v1/users/lookup?email=${encodeURIComponent(target.email)}`)).status).toBe(401);
    expect((await api("GET", "/api/v1/users/lookup?email=not-an-email", { token: caller.token })).status).toBe(422);
  });

  it("is rate limited per user", async () => {
    const caller = await verified();
    process.env.RATE_LIMIT_LOOKUP_PER_HOUR = "3";
    try {
      const s: number[] = [];
      for (let i = 0; i < 4; i++) s.push((await api("GET", `/api/v1/users/lookup?email=x${i}@example.com`, { token: caller.token })).status);
      expect(s).toEqual([404, 404, 404, 429]);
    } finally {
      process.env.RATE_LIMIT_LOOKUP_PER_HOUR = "10000";
    }
  });
});

describe("live point status", () => {
  it("stores status from points and returns it to viewers", async () => {
    const owner = await registerUser("Owner");
    const viewer = await registerUser("Viewer");
    const act = await createActivity(owner, { status: "recording", endedAt: null });
    const share = await api("POST", "/api/v1/live-shares", { token: owner.token, body: { activityId: act.id, viewerIds: [viewer.userId] } });
    expect(share.body.lastStatus).toBeNull();
    await api("POST", `/api/v1/live-shares/${share.body.id}/points`, { token: owner.token, body: { t: Date.now(), lat: 10.77, lon: 106.7, status: "paused" } });
    let seen = await api("GET", `/api/v1/live-shares/${share.body.id}`, { token: viewer.token });
    expect(seen.body.lastStatus).toBe("paused");
    expect(seen.body.lastPoint).not.toHaveProperty("status");
    // Point không có status => giữ status trước đó.
    await api("POST", `/api/v1/live-shares/${share.body.id}/points`, { token: owner.token, body: { t: Date.now(), lat: 10.78, lon: 106.7 } });
    seen = await api("GET", `/api/v1/live-shares/${share.body.id}`, { token: viewer.token });
    expect(seen.body.lastStatus).toBe("paused");
    await api("POST", `/api/v1/live-shares/${share.body.id}/points`, { token: owner.token, body: { t: Date.now(), lat: 10.79, lon: 106.7, status: "active" } });
    expect((await api("GET", `/api/v1/live-shares/${share.body.id}`, { token: viewer.token })).body.lastStatus).toBe("active");
    expect(
      (await api("POST", `/api/v1/live-shares/${share.body.id}/points`, { token: owner.token, body: { t: Date.now(), lat: 1, lon: 1, status: "stopped" } })).status,
    ).toBe(422);
  });
});

describe("feedback", () => {
  it("stores feedback with or without auth, redacts diagnostics, rate limits", async () => {
    const u = await registerUser();
    const diagnostics = JSON.stringify({ lat: 10.77, lon: 106.7, refreshToken: "abc", log: "GET /x?token=sekret Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijk" });
    const signed = await api("POST", "/api/v1/feedback", { token: u.token, body: { message: "GPS drops", diagnostics, appVersion: "0.1.0+3" } });
    expect(signed.status).toBe(201);
    const row = await prisma.feedback.findUnique({ where: { id: signed.body.id } });
    expect(row?.ownerId).toBe(u.userId);
    expect(row?.diagnostics).not.toMatch(/10\.77|106\.7|sekret|eyJhbGci|"abc"/);

    const plain = await api("POST", "/api/v1/feedback", { body: { message: "hello", diagnostics: "password=hunter2 lat=10.5 lon:106.1 plate=ok" } });
    expect(plain.status).toBe(201);
    const row2 = await prisma.feedback.findUnique({ where: { id: plain.body.id } });
    expect(row2?.ownerId).toBeNull();
    expect(row2?.diagnostics).toBe("password=[REDACTED] lat=[REDACTED] lon:[REDACTED] plate=ok");

    expect((await api("POST", "/api/v1/feedback", { body: { message: "" } })).status).toBe(422);
    expect((await api("POST", "/api/v1/feedback", { body: { message: "x", diagnostics: "d".repeat(8001) } })).status).toBe(422);

    process.env.RATE_LIMIT_FEEDBACK_PER_HOUR = "1";
    try {
      expect((await api("POST", "/api/v1/feedback", { ip: "198.51.100.7", body: { message: "a" } })).status).toBe(201);
      expect((await api("POST", "/api/v1/feedback", { ip: "198.51.100.7", body: { message: "b" } })).status).toBe(429);
    } finally {
      process.env.RATE_LIMIT_FEEDBACK_PER_HOUR = "10000";
    }
  });
});

describe("upsert over an open (recording/paused) activity", () => {
  it("accepts the client version without expectedRevision while open, keeping server metadata the client omits", async () => {
    const u = await registerUser();
    const id = randomUUID();
    // Plugin live tạo trước (recording), người dùng đã đặt title/notes/privacy trong lúc chạy.
    const live = await createActivity(u, { status: "recording", endedAt: null, title: "Live run", notes: "with Lan", privacy: "followers" }, id);
    expect(live.revision).toBe(1);

    // Sync engine đẩy bản kết thúc, không có expectedRevision và không gửi notes/feeling.
    const { notes: _n, feeling: _f, ...finalBody } = activityBody({ status: "saved", title: "Morning run", distanceM: 5400 });
    const pushed = await api("POST", "/api/v1/sync/push", {
      token: u.token,
      body: { operations: [{ idempotencyKey: `op-${randomUUID()}`, entity: "activity", op: "upsert", entityId: id, payload: finalBody }] },
    });
    expect(pushed.body.results[0].status).toBe("acked");
    const a = pushed.body.results[0].data;
    expect(a).toMatchObject({ status: "saved", distanceM: 5400, title: "Morning run", notes: "with Lan", revision: 2 });
    // privacy được client gửi (default onlyMe từ activityBody) => client thắng vì đã gửi rõ.
    expect(a.privacy).toBe("onlyMe");

    // Đã saved => quy tắc thường: thiếu expectedRevision và khác nội dung => 409.
    const later = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body: { activity: activityBody({ status: "saved", title: "Changed" }) } });
    expect(later.status).toBe(409);
    expect(later.body.error.code).toBe("revision_required");
    // expectedRevision khớp => chấp nhận.
    const ok = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body: { activity: activityBody({ status: "saved", title: "Changed" }), expectedRevision: 2 } });
    expect(ok.status).toBe(200);
    expect(ok.body.revision).toBe(3);
  });

  it("stale expectedRevision on an open activity is accepted; other owners still get 404", async () => {
    const u = await registerUser();
    const other = await registerUser();
    const id = randomUUID();
    await createActivity(u, { status: "recording", endedAt: null }, id);
    await api("PATCH", `/api/v1/activities/${id}`, { token: u.token, body: { expectedRevision: 1, notes: "patched" } });
    const r = await api("PUT", `/api/v1/activities/${id}`, {
      token: u.token,
      body: { activity: activityBody({ status: "paused", endedAt: null, distanceM: 1200, notes: null }), expectedRevision: 1 },
    });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ status: "paused", distanceM: 1200, notes: "patched", revision: 3 });
    expect((await api("PUT", `/api/v1/activities/${id}`, { token: other.token, body: { activity: activityBody() } })).status).toBe(404);
  });
});
