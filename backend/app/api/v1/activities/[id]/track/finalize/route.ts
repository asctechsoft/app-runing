import { json, pid, route } from "@/server/http/handler";
import { trackService } from "@/server/services/track.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await trackService.finalize(ctx.userId, pid(ctx.params.id, "Activity"), await ctx.input()));
});
