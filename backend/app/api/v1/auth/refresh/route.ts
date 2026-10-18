import { json, route } from "@/server/http/handler";
import { authService } from "@/server/services/auth.service";

export const POST = route({ auth: "none" }, async (ctx) => {
  return json(await authService.refresh(await ctx.input(), ctx.ip));
});
