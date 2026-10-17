import { json, pid, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const POST = route<{ id: string; userId: string }>({ idempotent: true }, async (ctx) => {
  return json(await clubService.decide(ctx.userId, pid(ctx.params.id, "Club"), pid(ctx.params.userId, "Join request"), true));
});
