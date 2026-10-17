import { json, route } from "@/server/http/handler";
import { meService } from "@/server/services/me.service";

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await meService.claimGuest(ctx.userId, await ctx.input()));
});
