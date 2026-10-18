import { json, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const GET = route({}, async (ctx) => {
  return json(await clubService.myClubs(ctx.userId));
});
