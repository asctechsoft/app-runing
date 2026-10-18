import { json, pid, route } from "@/server/http/handler";
import { liveShareService } from "@/server/services/live-share.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await liveShareService.get(ctx.userId, pid(ctx.params.id, "Live share")));
});
