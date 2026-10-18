import { json, pid, route } from "@/server/http/handler";
import { challengeService } from "@/server/services/challenge.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await challengeService.join(ctx.userId, pid(ctx.params.id, "Challenge"), await ctx.input()));
});
