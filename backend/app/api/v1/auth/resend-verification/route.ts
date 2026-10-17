import { json, route } from "@/server/http/handler";
import { authService } from "@/server/services/auth.service";

export const POST = route({ auth: "user" }, async (ctx) => {
  return json(await authService.resendVerification(ctx.userId), 202);
});
