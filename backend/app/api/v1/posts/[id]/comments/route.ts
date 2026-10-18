import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await feedService.listComments(ctx.userId, pid(ctx.params.id, "Post"), ctx.searchParams()));
});

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.addComment(ctx.userId, pid(ctx.params.id, "Post"), await ctx.input()), 201);
});
