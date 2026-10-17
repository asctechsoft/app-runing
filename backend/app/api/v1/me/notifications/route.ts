import { json, route } from "@/server/http/handler";
import { notificationService } from "@/server/services/notification.service";

export const GET = route({}, async (ctx) => {
  return json(await notificationService.list(ctx.userId, ctx.searchParams()));
});
