import { json, pid, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await clubService.getEvent(ctx.userId, pid(ctx.params.id, "Event")));
});
