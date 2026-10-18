import { json, pid, route } from "@/server/http/handler";
import { trackService } from "@/server/services/track.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await trackService.download(ctx.userId, pid(ctx.params.id, "Activity")));
});
