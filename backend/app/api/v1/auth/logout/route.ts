import { json, route } from "@/server/http/handler";
import { authService } from "@/server/services/auth.service";

export const POST = route({ auth: "userAllowDeleting" }, async (ctx) => {
  return json(await authService.logout(ctx.user().sessionId));
});
