import { describe, expect, it } from "vitest";
import { activityBody, api, createActivity, randomUUID, registerUser } from "./helpers";

describe("H03/H04 sync", () => {
  it("push acks each operation, replays by idempotencyKey, returns conflicts with server version", async () => {
    const u = await registerUser();
    const actId = randomUUID();
    const goalId = randomUUID();
    const ops = [
      { idempotencyKey: `op-${randomUUID()}`, entity: "activity", op: "upsert", entityId: actId, payload: activityBody() },
      { idempotencyKey: `op-${randomUUID()}`, entity: "goal", op: "upsert", entityId: goalId, payload: { type: "dailySteps", value: 8000, effectiveFrom: "2026-10-01" } },
      { idempotencyKey: `op-${randomUUID()}`, entity: "activity", op: "upsert", entityId: randomUUID(), payload: { type: "run" } },
    ];
    const r1 = await api("POST", "/api/v1/sync/push", { token: u.token, body: { operations: ops } });
    expect(r1.status).toBe(200);
    expect(r1.body.results.map((r: { status: string }) => r.status)).toEqual(["acked", "acked", "rejected"]);
    expect(r1.body.results[0].revision).toBe(1);
    expect(r1.body.results[2].error.code).toBe("validation_error");

    // Gửi lại cùng batch (mất ack) => kết quả y hệt, không tạo bản ghi trùng, không tăng revision.
    const r2 = await api("POST", "/api/v1/sync/push", { token: u.token, body: { operations: ops } });
    expect(r2.body.results).toEqual(r1.body.results);
    const goals = await api("GET", "/api/v1/me/goals", { token: u.token });
    expect(goals.body.items).toHaveLength(1);

    // Server đã ở revision 2 (sửa từ thiết bị khác); thiết bị này gửi với expectedRevision 1 => conflict.
    await api("PATCH", `/api/v1/activities/${actId}`, { token: u.token, body: { expectedRevision: 1, title: "From web" } });
    const conflict = await api("POST", "/api/v1/sync/push", {
      token: u.token,
      body: {
        operations: [
          { idempotencyKey: `op-${randomUUID()}`, entity: "activity", op: "upsert", entityId: actId, expectedRevision: 1, payload: activityBody({ title: "From phone" }) },
        ],
      },
    });
    expect(conflict.body.results[0].status).toBe("conflict");
    expect(conflict.body.results[0].server).toMatchObject({ id: actId, title: "From web", revision: 2 });

    // Cùng key nhưng nội dung khác => từ chối.
    const reused = await api("POST", "/api/v1/sync/push", {
      token: u.token,
      body: { operations: [{ ...ops[0], payload: activityBody({ title: "changed" }) }] },
    });
    expect(reused.body.results[0].status).toBe("rejected");
    expect(reused.body.results[0].error.code).toBe("idempotency_key_reused");
  });

  it("pull returns changes since cursor including tombstones; cursor is monotonic", async () => {
    const u = await registerUser();
    const other = await registerUser();
    const a1 = await createActivity(u);
    const a2 = await createActivity(u, { title: "Second" });
    await createActivity(other);

    const p1 = await api("GET", "/api/v1/sync/pull", { token: u.token });
    expect(p1.status).toBe(200);
    const ids = p1.body.items.map((i: { entityId: string }) => i.entityId);
    expect(ids).toEqual([a1.id, a2.id]);
    const cursor1 = p1.body.nextCursor as string;

    const del = await api("POST", "/api/v1/sync/push", {
      token: u.token,
      body: { operations: [{ idempotencyKey: `op-${randomUUID()}`, entity: "activity", op: "delete", entityId: a1.id }] },
    });
    expect(del.body.results[0].status).toBe("acked");
    await api("PUT", "/api/v1/me/profile", { token: u.token, body: { expectedRevision: 1, distanceUnit: "mi" } });

    const p2 = await api("GET", `/api/v1/sync/pull?cursor=${cursor1}`, { token: u.token });
    expect(p2.body.items.map((i: { entity: string; op: string }) => `${i.entity}:${i.op}`)).toEqual(["activity:delete", "profile:upsert"]);
    expect(p2.body.items[0].data.deletedAt).toEqual(expect.any(Number));
    expect(Number(p2.body.nextCursor)).toBeGreaterThan(Number(cursor1));

    const p3 = await api("GET", `/api/v1/sync/pull?cursor=${p2.body.nextCursor}`, { token: u.token });
    expect(p3.body.items).toEqual([]);
    expect(p3.body.nextCursor).toBe(p2.body.nextCursor);

    // Tombstone không bao giờ bị bỏ: pull lại từ đầu vẫn thấy hoạt động đã xóa ở dạng delete.
    const full = await api("GET", "/api/v1/sync/pull", { token: u.token });
    const t = full.body.items.find((i: { entityId: string }) => i.entityId === a1.id);
    expect(t.op).toBe("delete");

    // Phân trang pull.
    const small = await api("GET", "/api/v1/sync/pull?limit=1", { token: u.token });
    expect(small.body.items).toHaveLength(1);
    expect(small.body.hasMore).toBe(true);
  });
});

describe("Me: profile, goals, source priorities", () => {
  it("profile update with expectedRevision; stale revision gets 409 with server copy", async () => {
    const u = await registerUser();
    const ok = await api("PUT", "/api/v1/me/profile", { token: u.token, body: { expectedRevision: 1, weightKg: 70, audioCues: { enabled: false, everyKm: 1, voice: null } } });
    expect(ok.status).toBe(200);
    expect(ok.body).toMatchObject({ revision: 2, weightKg: 70, audioCues: { enabled: false } });
    const stale = await api("PUT", "/api/v1/me/profile", { token: u.token, body: { expectedRevision: 1, weightKg: 80 } });
    expect(stale.status).toBe(409);
    expect(stale.body.error.details.server.weightKg).toBe(70);
    const sp = await api("PUT", "/api/v1/me/source-priorities", { token: u.token, body: { expectedRevision: 2, priorities: ["healthConnect", "phoneSensor"] } });
    expect(sp.body).toEqual({ priorities: ["healthConnect", "phoneSensor"], revision: 3 });
    expect((await api("PUT", "/api/v1/me/source-priorities", { token: u.token, body: { expectedRevision: 3, priorities: ["fitbit"] } })).status).toBe(422);
  });

  it("goals are append-only versions resolved by effectiveFrom", async () => {
    const u = await registerUser();
    const g1 = await api("POST", "/api/v1/me/goals", { token: u.token, body: { type: "dailySteps", value: 6000, effectiveFrom: "2026-01-01" } });
    expect(g1.status).toBe(201);
    await api("POST", "/api/v1/me/goals", { token: u.token, body: { type: "dailySteps", value: 9000, effectiveFrom: "2026-06-01" } });
    const before = await api("GET", "/api/v1/me/goals/current?date=2026-05-31", { token: u.token });
    const after = await api("GET", "/api/v1/me/goals/current?date=2026-06-01", { token: u.token });
    expect(before.body.goals.dailySteps.value).toBe(6000);
    expect(after.body.goals.dailySteps.value).toBe(9000);
    expect(after.body.goals.weeklyRuns).toBeNull();
    const id = randomUUID();
    const body = { id, type: "weeklyRuns", value: 3, effectiveFrom: "2026-10-01" };
    expect((await api("POST", "/api/v1/me/goals", { token: u.token, body })).status).toBe(201);
    expect((await api("POST", "/api/v1/me/goals", { token: u.token, body })).status).toBe(200);
    expect((await api("POST", "/api/v1/me/goals", { token: u.token, body: { ...body, value: 4 } })).status).toBe(409);
  });
});

describe("E03 claim guest", () => {
  it("claims guest activity ids idempotently and never attaches another user's data", async () => {
    const a = await registerUser();
    const b = await registerUser();
    const ids = [randomUUID(), randomUUID()];
    const guestId = `guest:${randomUUID()}`;
    const c1 = await api("POST", "/api/v1/me/claim-guest", { token: a.token, body: { guestId, activityIds: ids } });
    expect(c1.body.results.map((r: { status: string }) => r.status)).toEqual(["claimed", "claimed"]);
    const c2 = await api("POST", "/api/v1/me/claim-guest", { token: a.token, body: { guestId, activityIds: ids } });
    expect(c2.body.results.map((r: { status: string }) => r.status)).toEqual(["alreadyClaimed", "alreadyClaimed"]);

    // B cố claim / upload cùng id => bị từ chối, không tạo bản ghi.
    const cb = await api("POST", "/api/v1/me/claim-guest", { token: b.token, body: { guestId: `guest:${randomUUID()}`, activityIds: [ids[0]] } });
    expect(cb.body.results[0].status).toBe("rejected");
    expect((await api("PUT", `/api/v1/activities/${ids[0]}`, { token: b.token, body: { activity: activityBody() } })).status).toBe(404);

    // A upload hoạt động đã claim; claim lại => alreadyOwned; upload lại => idempotent.
    expect((await api("PUT", `/api/v1/activities/${ids[0]}`, { token: a.token, body: { activity: activityBody() } })).status).toBe(201);
    expect((await api("PUT", `/api/v1/activities/${ids[0]}`, { token: a.token, body: { activity: activityBody() } })).status).toBe(200);
    const c3 = await api("POST", "/api/v1/me/claim-guest", { token: a.token, body: { guestId, activityIds: [ids[0]] } });
    expect(c3.body.results[0].status).toBe("alreadyOwned");
    const list = await api("GET", "/api/v1/activities", { token: a.token });
    expect(list.body.items).toHaveLength(1);

    // Hoạt động đã thuộc B: A claim => rejected.
    const bAct = await createActivity(b);
    const steal = await api("POST", "/api/v1/me/claim-guest", { token: a.token, body: { guestId, activityIds: [bAct.id] } });
    expect(steal.body.results[0].status).toBe("rejected");
  });
});
