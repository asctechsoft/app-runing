import { json, route } from "@/server/http/handler";
import { userService } from "@/server/services/user.service";

export const POST = route({ auth: "optional", jsonLimitBytes: 64 * 1024 }, async (ctx) => {
  return json(await userService.submitFeedback(ctx.auth?.userId ?? null, ctx.ip, await ctx.input()), 201);
});
