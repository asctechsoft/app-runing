import { json, pid, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await clubService.leave(ctx.userId, pid(ctx.params.id, "Club")));
});
