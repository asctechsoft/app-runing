import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.cheer(ctx.userId, pid(ctx.params.id, "Post"), true));
});

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.cheer(ctx.userId, pid(ctx.params.id, "Post"), false));
});
