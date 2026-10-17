import { describe, expect, it } from "vitest";
import { activityBody, api, createActivity, randomUUID, registerUser } from "./helpers";
import { buildTrackChunks, sha256 } from "./track-helpers";

describe("H02 activities", () => {
  it("upsert by client id is idempotent on retry", async () => {
    const u = await registerUser();
    const id = randomUUID();
    const body = { activity: activityBody() };
    const first = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body });
    expect(first.status).toBe(201);
    expect(first.body.revision).toBe(1);
    expect(first.body.privacy).toBe("onlyMe");
    // Retry không có Idempotency-Key, cùng nội dung => 200, không tăng revision.
    const retry = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body });
    expect(retry.status).toBe(200);
    expect(retry.body.revision).toBe(1);
    // Nội dung khác mà không có expectedRevision => 409 kèm bản server.
    const changed = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body: { activity: activityBody({ title: "Other" }) } });
    expect(changed.status).toBe(409);
    expect(changed.body.error.code).toBe("revision_required");
    expect(changed.body.error.details.server.title).toBe("Morning run");
  });

  it("Idempotency-Key replays the stored response and rejects reuse with another body", async () => {
    const u = await registerUser();
    const id = randomUUID();
    const headers = { "idempotency-key": `key-${randomUUID()}` };
    const a = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, headers, body: { activity: activityBody() } });
    const b = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, headers, body: { activity: activityBody() } });
    expect(a.status).toBe(201);
    expect(b.status).toBe(201);
    expect(b.headers.get("idempotent-replayed")).toBe("true");
    expect(b.body).toEqual(a.body);
    const reuse = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, headers, body: { activity: activityBody({ title: "x" }) } });
    expect(reuse.status).toBe(422);
    expect(reuse.body.error.code).toBe("idempotency_key_reused");
    // Key của user khác không đụng nhau.
    const other = await registerUser();
    const o = await api("PUT", `/api/v1/activities/${randomUUID()}`, { token: other.token, headers, body: { activity: activityBody() } });
    expect(o.status).toBe(201);
  });

  it("updates with expectedRevision, patches metadata, conflicts return server copy", async () => {
    const u = await registerUser();
    const { id } = await createActivity(u);
    const upd = await api("PUT", `/api/v1/activities/${id}`, {
      token: u.token,
      body: { activity: activityBody({ notes: "felt good" }), expectedRevision: 1 },
    });
    expect(upd.status).toBe(200);
    expect(upd.body.revision).toBe(2);
    const stale = await api("PATCH", `/api/v1/activities/${id}`, { token: u.token, body: { expectedRevision: 1, title: "Stale" } });
    expect(stale.status).toBe(409);
    expect(stale.body.error.details.server.revision).toBe(2);
    const ok = await api("PATCH", `/api/v1/activities/${id}`, { token: u.token, body: { expectedRevision: 2, title: "Renamed", privacy: "followers" } });
    expect(ok.status).toBe(200);
    expect(ok.body).toMatchObject({ title: "Renamed", privacy: "followers", revision: 3 });
  });

  it("delete creates a tombstone; tombstone wins over later upserts", async () => {
    const u = await registerUser();
    const { id } = await createActivity(u);
    const del = await api("DELETE", `/api/v1/activities/${id}`, { token: u.token });
    expect(del.status).toBe(200);
    expect(del.body.deletedAt).toEqual(expect.any(Number));
    expect(del.body.revision).toBe(2);
    expect((await api("DELETE", `/api/v1/activities/${id}`, { token: u.token })).status).toBe(200);
    expect((await api("GET", `/api/v1/activities/${id}`, { token: u.token })).status).toBe(404);
    const resurrect = await api("PUT", `/api/v1/activities/${id}`, { token: u.token, body: { activity: activityBody() } });
    expect(resurrect.status).toBe(409);
    expect(resurrect.body.error.code).toBe("activity_deleted");
    const list = await api("GET", `/api/v1/activities?includeDeleted=true`, { token: u.token });
    expect(list.body.items.find((a: { id: string }) => a.id === id).deletedAt).toBeTruthy();
  });

  it("validates input: no fake pace, missing data stays null", async () => {
    const u = await registerUser();
    const bad = await api("PUT", `/api/v1/activities/${randomUUID()}`, {
      token: u.token,
      body: { activity: activityBody({ distanceM: 5, avgPaceSecPerKm: 300 }) },
    });
    expect(bad.status).toBe(422);
    const nulls = await api("PUT", `/api/v1/activities/${randomUUID()}`, {
      token: u.token,
      body: { activity: activityBody({ type: "indoorRun", hasGps: false, distanceSource: "steps", distanceM: null, avgPaceSecPerKm: null, steps: null }) },
    });
    expect(nulls.status).toBe(201);
    expect(nulls.body.distanceM).toBeNull();
    expect(nulls.body.avgPaceSecPerKm).toBeNull();
    expect(nulls.body.steps).toBeNull();
  });

  it("paginates activities with a cursor", async () => {
    const u = await registerUser();
    for (let i = 0; i < 5; i++) await createActivity(u, { startedAt: Date.UTC(2026, 8, 1 + i, 6), endedAt: Date.UTC(2026, 8, 1 + i, 7) });
    const p1 = await api("GET", "/api/v1/activities?limit=2", { token: u.token });
    expect(p1.body.items).toHaveLength(2);
    expect(p1.body.nextCursor).toBeTruthy();
    const p2 = await api("GET", `/api/v1/activities?limit=2&cursor=${p1.body.nextCursor}`, { token: u.token });
    const p3 = await api("GET", `/api/v1/activities?limit=2&cursor=${p2.body.nextCursor}`, { token: u.token });
    expect(p3.body.items).toHaveLength(1);
    expect(p3.body.nextCursor).toBeNull();
    const ids = [...p1.body.items, ...p2.body.items, ...p3.body.items].map((a: { id: string }) => a.id);
    expect(new Set(ids).size).toBe(5);
    expect((await api("GET", "/api/v1/activities?cursor=%%%bad", { token: u.token })).status).toBe(400);
  });
});

describe("H02 track chunks + I07 GPX", () => {
  it("chunk retry is idempotent, finalize requires all chunks, GPX keeps segments", async () => {
    const u = await registerUser();
    const { id } = await createActivity(u);
    const chunks = buildTrackChunks(Date.UTC(2026, 9, 10, 6));
    const put = (seq: number, bytes: Uint8Array, checksum = sha256(bytes)) =>
      api("PUT", `/api/v1/activities/${id}/track/chunks/${seq}`, {
        token: u.token,
        raw: bytes,
        headers: { "x-checksum-sha256": checksum, "content-type": "application/json" },
      });

    expect((await put(0, chunks[0]!)).status).toBe(201);
    const retry = await put(0, chunks[0]!);
    expect(retry.status).toBe(200);
    expect(retry.body.duplicate).toBe(true);
    expect((await put(0, chunks[1]!)).status).toBe(409);
    expect((await put(1, chunks[1]!, sha256("other"))).status).toBe(422);
    expect((await put(2, chunks[2]!)).status).toBe(201);

    const incomplete = await api("POST", `/api/v1/activities/${id}/track/finalize`, { token: u.token, body: { totalChunks: 3 } });
    expect(incomplete.status).toBe(409);
    expect(incomplete.body.error.code).toBe("track_incomplete");
    expect(incomplete.body.error.details.missing).toEqual([1]);

    expect((await put(1, chunks[1]!)).status).toBe(201);
    const fin = await api("POST", `/api/v1/activities/${id}/track/finalize`, { token: u.token, body: { totalChunks: 3 } });
    expect(fin.status).toBe(200);
    expect(fin.body).toMatchObject({ status: "finalized", pointCount: 6, segmentCount: 2 });
    const again = await api("POST", `/api/v1/activities/${id}/track/finalize`, { token: u.token, body: { totalChunks: 3 } });
    expect(again.status).toBe(200);
    // Re-upload chunk sau finalize vẫn idempotent.
    expect((await put(1, chunks[1]!)).status).toBe(200);

    const track = await api("GET", `/api/v1/activities/${id}/track`, { token: u.token });
    expect(track.status).toBe(200);
    expect(track.body.segments).toHaveLength(2);
    expect(track.body.segments[0].endedAt).toBe(Date.UTC(2026, 9, 10, 6) + 60_000);

    const gpx = await api("GET", `/api/v1/activities/${id}/gpx`, { token: u.token });
    expect(gpx.status).toBe(200);
    expect(gpx.headers.get("content-type")).toContain("gpx");
    expect(gpx.text.match(/<trkseg>/g)).toHaveLength(2);
    // Chỉ point accepted (5/6), không lấp khoảng trống.
    expect(gpx.text.match(/<trkpt /g)).toHaveLength(5);
    expect(gpx.text).not.toContain('lat="10.7900000"');
  });

  it("rejects invalid chunk content and activities without GPS", async () => {
    const u = await registerUser();
    const { id } = await createActivity(u);
    const junk = new TextEncoder().encode(JSON.stringify({ points: [{ lat: 999 }] }));
    const r = await api("PUT", `/api/v1/activities/${id}/track/chunks/0`, { token: u.token, raw: junk, headers: { "x-checksum-sha256": sha256(junk) } });
    expect(r.status).toBe(422);
    const noChecksum = await api("PUT", `/api/v1/activities/${id}/track/chunks/0`, { token: u.token, raw: junk });
    expect(noChecksum.status).toBe(400);
    const indoor = await createActivity(u, { type: "indoorRun", hasGps: false, distanceSource: "steps", distanceM: null, avgPaceSecPerKm: null });
    const chunk = buildTrackChunks(Date.UTC(2026, 9, 10, 6))[0]!;
    const g = await api("PUT", `/api/v1/activities/${indoor.id}/track/chunks/0`, { token: u.token, raw: chunk, headers: { "x-checksum-sha256": sha256(chunk) } });
    expect(g.status).toBe(409);
    expect(g.body.error.code).toBe("no_gps");
  });
});
