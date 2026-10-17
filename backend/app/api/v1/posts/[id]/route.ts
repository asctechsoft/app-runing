import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await feedService.get(ctx.userId, pid(ctx.params.id, "Post")));
});

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.remove(ctx.userId, pid(ctx.params.id, "Post")));
});
