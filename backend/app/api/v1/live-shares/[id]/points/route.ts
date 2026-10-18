import { json, pid, route } from "@/server/http/handler";
import { liveShareService } from "@/server/services/live-share.service";

export const POST = route<{ id: string }>({}, async (ctx) => {
  return json(await liveShareService.publishPoint(ctx.userId, pid(ctx.params.id, "Live share"), await ctx.input()));
});
