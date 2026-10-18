import { json, route } from "@/server/http/handler";
import { meService } from "@/server/services/me.service";

export const GET = route({}, async (ctx) => {
  return json(await meService.currentGoals(ctx.userId, ctx.url.searchParams.get("date") ?? ""));
});
