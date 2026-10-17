import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await feedService.removeComment(ctx.userId, pid(ctx.params.id, "Comment")));
});
