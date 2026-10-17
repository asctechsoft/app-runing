import { json, pid, route } from "@/server/http/handler";
import { challengeService } from "@/server/services/challenge.service";

export const PUT = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await challengeService.setLeaderboardOptIn(ctx.userId, pid(ctx.params.id, "Challenge"), await ctx.input()));
});
