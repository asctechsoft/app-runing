import { json, pid, route } from "@/server/http/handler";
import { routeService } from "@/server/services/route.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await routeService.save(ctx.userId, pid(ctx.params.id, "Route"), true));
});

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await routeService.save(ctx.userId, pid(ctx.params.id, "Route"), false));
});
