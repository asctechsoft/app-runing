import { json, route } from "@/server/http/handler";
import { authService } from "@/server/services/auth.service";

// Đăng nhập Google qua Firebase Auth. Apple: chưa hỗ trợ (không có route).
export const POST = route({ auth: "none" }, async (ctx) => {
  return json(await authService.firebaseLogin(await ctx.input(), ctx.ip));
});
