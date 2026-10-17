import { json, pid, route } from "@/server/http/handler";
import { feedService } from "@/server/services/feed.service";

export const DELETE = route<{ userId: string }>({}, async (ctx) => {
  return json(await feedService.unblock(ctx.userId, pid(ctx.params.userId, "Block")));
});
