import { json, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await feedService.report(ctx.userId, await ctx.input()), 201);
});
