import { json, route } from "@/server/http/handler";
import { meService } from "@/server/services/me.service";

export const GET = route({}, async (ctx) => {
  return json(await meService.get(ctx.userId));
});
