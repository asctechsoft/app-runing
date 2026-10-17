import { json, route } from "@/server/http/handler";
import { challengeService } from "@/server/services/challenge.service";

export const GET = route({}, async (ctx) => {
  return json(await challengeService.badges(ctx.userId));
});
