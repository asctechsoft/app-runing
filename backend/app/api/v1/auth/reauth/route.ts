import { json, route } from "@/server/http/handler";
import { authService } from "@/server/services/auth.service";

export const POST = route({ auth: "userAllowDeleting" }, async (ctx) => {
  const u = ctx.user();
  return json(await authService.reauth(u.userId, u.sessionId, await ctx.input(), ctx.ip));
});
