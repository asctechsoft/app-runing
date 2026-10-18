import { json, route } from "@/server/http/handler";
import { liveShareService } from "@/server/services/live-share.service";

export const GET = route({}, async (ctx) => {
  return json(await liveShareService.listViewing(ctx.userId));
});
