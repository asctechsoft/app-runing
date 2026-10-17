import { json, route } from "@/server/http/handler";
import { meService } from "@/server/services/me.service";

export const GET = route({}, async (ctx) => {
  return json(await meService.getSourcePriorities(ctx.userId));
});

export const PUT = route({ idempotent: true }, async (ctx) => {
  return json(await meService.setSourcePriorities(ctx.userId, await ctx.input()));
});
