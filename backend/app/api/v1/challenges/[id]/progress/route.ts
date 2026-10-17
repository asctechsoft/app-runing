import { json, pid, route } from "@/server/http/handler";
import { challengeService } from "@/server/services/challenge.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await challengeService.progress(ctx.userId, pid(ctx.params.id, "Challenge")));
});
