import { json, route } from "@/server/http/handler";
import { routeService } from "@/server/services/route.service";

export const GET = route({}, async (ctx) => {
  return json(await routeService.search(ctx.userId, ctx.searchParams()));
});
