import { json, route } from "@/server/http/handler";
import { healthRepository } from "@/server/repositories/health.repository";

// B06: health check — kiểm tra process và kết nối DB. Không trả thông tin nhạy cảm.
export const GET = route({ auth: "none" }, async () => {
  let db = "ok";
  try {
    await healthRepository.ping();
  } catch {
    db = "error";
  }
  return json({ status: db === "ok" ? "ok" : "degraded", db, time: Date.now(), apiVersion: "v1" }, db === "ok" ? 200 : 503);
});
