import { json, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const GET = route({}, async (ctx) => {
  return json(await feedService.listBlocks(ctx.userId));
});

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await feedService.block(ctx.userId, await ctx.input()), 201);
});
