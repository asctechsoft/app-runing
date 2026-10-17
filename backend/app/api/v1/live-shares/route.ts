import { json, route } from "@/server/http/handler";
import { liveShareService } from "@/server/services/live-share.service";

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await liveShareService.start(ctx.userId, await ctx.input()), 201);
});
