import { json, route } from "@/server/http/handler";
import { activityService } from "@/server/services/activity.service";

export const GET = route({}, async (ctx) => {
  return json(await activityService.list(ctx.userId, ctx.searchParams()));
});
