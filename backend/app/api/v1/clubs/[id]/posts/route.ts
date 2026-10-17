import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await feedService.list(ctx.userId, pid(ctx.params.id, "Club"), ctx.searchParams()));
});

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.create(ctx.userId, pid(ctx.params.id, "Club"), await ctx.input()), 201);
});
