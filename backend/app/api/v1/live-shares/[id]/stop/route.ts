import { json, pid, route } from "@/server/http/handler";
import { liveShareService } from "@/server/services/live-share.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await liveShareService.stop(ctx.userId, pid(ctx.params.id, "Live share")));
});
