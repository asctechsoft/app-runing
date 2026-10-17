import { describe, expect, it } from "vitest";
import { unzipSync, strFromU8 } from "fflate";
import { prisma } from "@/lib/prisma";
import { jobService } from "@/server/services/job.service";
import { api, createActivity, registerUser } from "./helpers";
import { buildTrackChunks, sha256 } from "./track-helpers";

describe("H06 export", () => {
  it("builds a zip with JSON, CSV and GPX of the owner's data only", async () => {
    const u = await registerUser();
    const other = await registerUser();
    const act = await createActivity(u, { title: "=cmd|' /C calc'!A0" });
    await createActivity(other, { title: "Not mine" });
    for (const [seq, chunk] of buildTrackChunks(Date.UTC(2026, 9, 10, 6)).entries()) {
      await api("PUT", `/api/v1/activities/${act.id}/track/chunks/${seq}`, { token: u.token, raw: chunk, headers: { "x-checksum-sha256": sha256(chunk) } });
    }
    await api("POST", `/api/v1/activities/${act.id}/track/finalize`, { token: u.token, body: { totalChunks: 3 } });

    const job = await api("POST", "/api/v1/me/exports", { token: u.token });
    expect(job.status).toBe(202);
    expect(job.body.status).toBe("queued");
    expect((await api("GET", `/api/v1/me/exports/${job.body.id}/download`, { token: u.token })).status).toBe(409);
    expect((await api("GET", `/api/v1/me/exports/${job.body.id}`, { token: other.token })).status).toBe(404);

    await jobService.processPending();
    const status = await api("GET", `/api/v1/me/exports/${job.body.id}`, { token: u.token });
    expect(status.body.status).toBe("succeeded");
    expect(status.body.expiresAt).toBeGreaterThan(Date.now());
    expect((await api("GET", `/api/v1/me/exports/${job.body.id}/download`, { token: other.token })).status).toBe(404);

    const dl = await api("GET", `/api/v1/me/exports/${job.body.id}/download`, { token: u.token });
    expect(dl.status).toBe(200);
    expect(dl.headers.get("content-type")).toBe("application/zip");
    const files = unzipSync(dl.bytes);
    expect(Object.keys(files).sort()).toEqual(["README.txt", "activities.csv", "activities.json", "goals.json", `gpx/${act.id}.gpx`, "profile.json"]);
    const acts = JSON.parse(strFromU8(files["activities.json"]!));
    expect(acts).toHaveLength(1);
    const csv = strFromU8(files["activities.csv"]!);
    // Chống formula injection: ô bắt đầu bằng "=" được thêm dấu ' phía trước.
    expect(csv).toContain("'=cmd|' /C calc'!A0");
    expect(strFromU8(files[`gpx/${act.id}.gpx`]!).match(/<trkseg>/g)).toHaveLength(2);

    // Hết hạn => 410.
    await prisma.job.update({ where: { id: job.body.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    expect((await api("GET", `/api/v1/me/exports/${job.body.id}/download`, { token: u.token })).status).toBe(410);
  });
});

describe("H06 delete account", () => {
  it("requires recent reauth, reports pending until the job finishes, then removes data", async () => {
    const u = await registerUser();
    const act = await createActivity(u);
    expect((await api("POST", "/api/v1/me/deletion", { token: u.token })).status).toBe(403);

    await api("POST", "/api/v1/auth/reauth", { token: u.token, body: { password: u.password } });
    const req = await api("POST", "/api/v1/me/deletion", { token: u.token });
    expect(req.status).toBe(202);
    expect(req.body.status).toBe("queued");
    // Trước khi job chạy: không báo đã xóa; các API khác bị khóa.
    expect((await api("GET", "/api/v1/me/deletion", { token: u.token })).body.status).toBe("queued");
    expect((await api("GET", "/api/v1/activities", { token: u.token })).status).toBe(403);
    expect(await prisma.activity.count({ where: { ownerId: u.userId } })).toBe(1);

    await jobService.processPending();
    expect((await prisma.job.findUnique({ where: { id: req.body.id } }))?.status).toBe("succeeded");
    const after = await api("GET", "/api/v1/me", { token: u.token });
    expect(after.status).toBe(401);
    expect(await prisma.activity.count({ where: { ownerId: u.userId } })).toBe(0);
    expect(await prisma.activity.count({ where: { id: act.id } })).toBe(0);
    expect(await prisma.refreshToken.count({ where: { userId: u.userId, session: { revokedAt: null } } })).toBe(0);
    expect((await api("POST", "/api/v1/auth/login", { body: { email: u.email, password: u.password } })).status).toBe(401);
    // Email được giải phóng để đăng ký lại.
    expect((await api("POST", "/api/v1/auth/register", { body: { email: u.email, password: "fresh1234" } })).status).toBe(201);
  });
});
