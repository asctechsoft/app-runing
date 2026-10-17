import { json, pid, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const PUT = route<{ id: string; userId: string }>({ idempotent: true }, async (ctx) => {
  return json(await clubService.setRole(ctx.userId, pid(ctx.params.id, "Club"), pid(ctx.params.userId, "Member"), await ctx.input()));
});
