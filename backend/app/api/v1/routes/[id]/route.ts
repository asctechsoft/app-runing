import { json, pid, route } from "@/server/http/handler";
import { routeService } from "@/server/services/route.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await routeService.detail(ctx.userId, pid(ctx.params.id, "Route")));
});
