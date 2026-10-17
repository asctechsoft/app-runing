import { describe, expect, it } from "vitest";
import { redact, redactString } from "@/lib/redact";
import { LocalDiskStorage } from "@/lib/storage/local-disk";
import { api, registerUser } from "./helpers";
import path from "node:path";

describe("B06 health + N01 basics", () => {
  it("health reports db status", async () => {
    const r = await api("GET", "/api/health");
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ status: "ok", db: "ok", apiVersion: "v1" });
  });

  it("redacts tokens, passwords and coordinates from logs", () => {
    const out = redact({
      password: "secret123",
      refreshToken: "abc",
      nested: { lat: 10.7, lon: 106.7, title: "ok" },
      header: "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijk",
      url: "https://x/verify?token=supersecret&x=1",
    }) as Record<string, unknown>;
    expect(out.password).toBe("[REDACTED]");
    expect(out.refreshToken).toBe("[REDACTED]");
    expect(out.nested).toEqual({ lat: "[REDACTED]", lon: "[REDACTED]", title: "ok" });
    expect(String(out.header)).not.toContain("eyJ");
    expect(redactString("https://x/verify?token=supersecret&x=1")).toBe("https://x/verify?token=[REDACTED]&x=1");
  });

  it("storage driver rejects path traversal", async () => {
    const s = new LocalDiskStorage(path.resolve(process.env.STORAGE_DIR!));
    await expect(s.put("../escape.txt", new Uint8Array([1]))).rejects.toThrow();
    await s.put("a/b.txt", new Uint8Array([1, 2]));
    expect(await s.get("a/b.txt")).toEqual(new Uint8Array([1, 2]));
    await s.deletePrefix("a");
    expect(await s.exists("a/b.txt")).toBe(false);
  });

  it("rejects invalid JSON, oversized bodies and malformed idempotency keys", async () => {
    const u = await registerUser();
    const bad = await api("PUT", "/api/v1/me/profile", { token: u.token, raw: "{not json", headers: { "content-type": "application/json" } });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe("invalid_json");
    const big = await api("PUT", "/api/v1/me/profile", { token: u.token, raw: "x".repeat(1024 * 1024 + 10) });
    expect(big.status).toBe(413);
    const key = await api("PUT", "/api/v1/me/profile", { token: u.token, headers: { "idempotency-key": "short" }, body: { expectedRevision: 1 } });
    expect(key.status).toBe(400);
  });

  it("notifications inbox: list and mark read for owner only", async () => {
    const owner = await registerUser();
    const other = await registerUser();
    // Tạo thông báo qua luồng thật: yêu cầu tham gia club.
    const club = await api("POST", "/api/v1/clubs", { token: owner.token, body: { name: "Club X", regionText: "Hanoi" } });
    await api("POST", `/api/v1/clubs/${club.body.id}/join`, { token: other.token });
    const list = await api("GET", "/api/v1/me/notifications", { token: owner.token });
    expect(list.body.unreadCount).toBe(1);
    const n = list.body.items[0];
    expect(n.kind).toBe("clubJoinRequest");
    expect((await api("POST", `/api/v1/me/notifications/${n.id}/read`, { token: other.token })).status).toBe(404);
    expect((await api("POST", `/api/v1/me/notifications/${n.id}/read`, { token: owner.token })).body.readAt).toEqual(expect.any(Number));
    expect((await api("GET", "/api/v1/me/notifications", { token: owner.token })).body.unreadCount).toBe(0);
  });
});
