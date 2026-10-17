import type { Route } from "@prisma/client";
import { notFound } from "@/lib/errors";
import { decodeCursor, toPage } from "@/server/http/pagination";
import { routeRepository } from "@/server/repositories/explore.repository";
import { routeSearchQuery } from "@/server/validators/misc";

// M05: tuyến chạy gợi ý. Luôn trả attribution của nguồn dữ liệu bản đồ.

function toRouteDto(r: Route, saved: boolean, detail: boolean) {
  return {
    id: r.id,
    name: r.name,
    region: r.region,
    distanceM: r.distanceM,
    surface: r.surface,
    attribution: r.attribution,
    start: r.startLat != null && r.startLon != null ? { lat: r.startLat, lon: r.startLon } : null,
    isDevFixture: r.isDevFixture,
    saved,
    ...(detail && { polyline: r.polyline, polylineEncoding: "google-polyline-5" }),
  };
}

export const routeService = {
  async search(userId: string, rawQuery: unknown) {
    const q = routeSearchQuery.parse(rawQuery);
    const rows = await routeRepository.search(q, decodeCursor(q.cursor), q.limit);
    const page = toPage(rows, q.limit, (r) => r.createdAt);
    const saved = new Set((await routeRepository.savedIds(userId, page.items.map((r) => r.id))).map((s) => s.routeId));
    return { items: page.items.map((r) => toRouteDto(r, saved.has(r.id), false)), nextCursor: page.nextCursor };
  },

  async detail(userId: string, id: string) {
    const r = await routeRepository.find(id);
    if (!r) throw notFound("Route");
    const saved = (await routeRepository.savedIds(userId, [id])).length > 0;
    return toRouteDto(r, saved, true);
  },

  async save(userId: string, id: string, on: boolean) {
    const r = await routeRepository.find(id);
    if (!r) throw notFound("Route");
    if (on) await routeRepository.save(userId, id);
    else await routeRepository.unsave(userId, id);
    return toRouteDto(r, on, false);
  },

  async listSaved(userId: string) {
    const saved = await routeRepository.listSaved(userId);
    const routes = await routeRepository.findMany(saved.map((s) => s.routeId));
    const byId = new Map(routes.map((r) => [r.id, r]));
    return {
      items: saved.flatMap((s) => {
        const r = byId.get(s.routeId);
        return r ? [toRouteDto(r, true, false)] : [];
      }),
      nextCursor: null,
    };
  },
};
