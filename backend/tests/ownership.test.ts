import { describe, expect, it } from "vitest";
import { activityBody, api, createActivity, randomUUID, registerUser } from "./helpers";
import { buildTrackChunks, sha256 } from "./track-helpers";

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d, 1, 2, 3, 4]);

describe("H01 owner isolation", () => {
  it("user B cannot read/modify/delete user A's activity, track, attachment (real and guessed ids => 404)", async () => {
    const a = await registerUser("A");
    const b = await registerUser("B");
    const { id } = await createActivity(a);

    const chunk = buildTrackChunks(Date.UTC(2026, 9, 10, 6))[0]!;
    await api("PUT", `/api/v1/activities/${id}/track/chunks/0`, { token: a.token, raw: chunk, headers: { "x-checksum-sha256": sha256(chunk) } });
    await api("POST", `/api/v1/activities/${id}/track/finalize`, { token: a.token, body: { totalChunks: 1 } });

    const attId = randomUUID();
    const req = await api("POST", `/api/v1/activities/${id}/attachments`, { token: a.token, body: { id: attId, mime: "image/png", bytes: PNG.byteLength } });
    expect(req.status).toBe(201);
    const uploadPath = new URL(req.body.upload.uploadUrl).pathname;
    expect((await api("PUT", uploadPath, { raw: PNG, headers: { "content-type": "image/png" } })).status).toBe(204);
    expect((await api("POST", `/api/v1/attachments/${attId}/complete`, { token: a.token })).status).toBe(200);

    const guessed = randomUUID();
    for (const target of [id, guessed]) {
      const checks = [
        await api("GET", `/api/v1/activities/${target}`, { token: b.token }),
        await api("PATCH", `/api/v1/activities/${target}`, { token: b.token, body: { expectedRevision: 1, title: "hack" } }),
        await api("DELETE", `/api/v1/activities/${target}`, { token: b.token }),
        await api("GET", `/api/v1/activities/${target}/track`, { token: b.token }),
        await api("GET", `/api/v1/activities/${target}/gpx`, { token: b.token }),
        await api("PUT", `/api/v1/activities/${target}/track/chunks/1`, { token: b.token, raw: chunk, headers: { "x-checksum-sha256": sha256(chunk) } }),
        await api("POST", `/api/v1/activities/${target}/track/finalize`, { token: b.token, body: { totalChunks: 1 } }),
        await api("GET", `/api/v1/activities/${target}/attachments`, { token: b.token }),
        await api("POST", `/api/v1/activities/${target}/attachments`, { token: b.token, body: { id: randomUUID(), mime: "image/png", bytes: 10 } }),
      ];
      for (const r of checks) {
        expect(r.status).toBe(404);
        expect(r.body.error.code).toBe("not_found");
      }
    }
    // Ghi đè bằng id thật của A => 404 (không tạo/không sửa). Id đoán ngẫu nhiên thì B tạo hoạt động mới của chính B.
    const overwrite = await api("PUT", `/api/v1/activities/${id}`, { token: b.token, body: { activity: activityBody(), expectedRevision: 1 } });
    expect(overwrite.status).toBe(404);
    for (const target of [attId, guessed]) {
      expect((await api("GET", `/api/v1/attachments/${target}/url`, { token: b.token })).status).toBe(404);
      expect((await api("POST", `/api/v1/attachments/${target}/complete`, { token: b.token })).status).toBe(404);
      expect((await api("DELETE", `/api/v1/attachments/${target}`, { token: b.token })).status).toBe(404);
    }
    // Đặt trùng id attachment của A vào hoạt động của B => 404.
    const bAct = await createActivity(b);
    const steal = await api("POST", `/api/v1/activities/${bAct.id}/attachments`, { token: b.token, body: { id: attId, mime: "image/png", bytes: PNG.byteLength } });
    expect(steal.status).toBe(404);
    // Path không phải UUID => 404.
    expect((await api("GET", `/api/v1/activities/not-a-uuid`, { token: b.token })).status).toBe(404);

    // Dữ liệu của A vẫn nguyên vẹn.
    const mine = await api("GET", `/api/v1/activities/${id}`, { token: a.token });
    expect(mine.status).toBe(200);
    expect(mine.body.title).toBe("Morning run");
    expect(mine.body.revision).toBe(1);
    expect((await api("GET", `/api/v1/activities`, { token: b.token })).body.items.map((x: { id: string }) => x.id)).not.toContain(id);
  });
});

describe("H05 attachments", () => {
  it("validates mime/size, uploads via signed URL, serves only via signed download URL", async () => {
    const u = await registerUser();
    const { id } = await createActivity(u);
    expect((await api("POST", `/api/v1/activities/${id}/attachments`, { token: u.token, body: { id: randomUUID(), mime: "image/gif", bytes: 10 } })).status).toBe(422);
    expect(
      (await api("POST", `/api/v1/activities/${id}/attachments`, { token: u.token, body: { id: randomUUID(), mime: "image/png", bytes: 10 * 1024 * 1024 + 1 } })).status,
    ).toBe(422);

    const attId = randomUUID();
    const req = await api("POST", `/api/v1/activities/${id}/attachments`, { token: u.token, body: { id: attId, mime: "image/png", bytes: PNG.byteLength } });
    expect(req.body.attachment.uploadState).toBe("pending");
    const uploadPath = new URL(req.body.upload.uploadUrl).pathname;
    expect((await api("POST", `/api/v1/attachments/${attId}/complete`, { token: u.token })).status).toBe(409);
    expect((await api("PUT", uploadPath, { raw: PNG, headers: { "content-type": "image/jpeg" } })).status).toBe(422);
    expect((await api("PUT", uploadPath, { raw: new Uint8Array(PNG.byteLength), headers: { "content-type": "image/png" } })).status).toBe(422);
    expect((await api("PUT", "/api/v1/uploads/forged.token.here", { raw: PNG, headers: { "content-type": "image/png" } })).status).toBe(404);
    expect((await api("PUT", uploadPath, { raw: PNG, headers: { "content-type": "image/png" } })).status).toBe(204);
    const done = await api("POST", `/api/v1/attachments/${attId}/complete`, { token: u.token });
    expect(done.body.uploadState).toBe("uploaded");

    const link = await api("GET", `/api/v1/attachments/${attId}/url`, { token: u.token });
    expect(link.body.expiresAt).toBeGreaterThan(Date.now());
    const file = await api("GET", new URL(link.body.url).pathname);
    expect(file.status).toBe(200);
    expect(file.headers.get("content-type")).toBe("image/png");
    expect(file.headers.get("cache-control")).toContain("private");
    expect(Array.from(file.bytes)).toEqual(Array.from(PNG));

    const del = await api("DELETE", `/api/v1/attachments/${attId}`, { token: u.token });
    expect(del.body.deletedAt).toBeTruthy();
    expect((await api("GET", new URL(link.body.url).pathname)).status).toBe(404);
  });
});
