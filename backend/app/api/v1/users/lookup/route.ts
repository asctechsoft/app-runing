import { json, route } from "@/server/http/handler";
import { userService } from "@/server/services/user.service";

export const GET = route({}, async (ctx) => {
  return json(await userService.lookupByEmail(ctx.userId, ctx.searchParams()));
});
