import { json, route } from "@/server/http/handler";
import { notificationService } from "@/server/services/notification.service";

export const POST = route({}, async (ctx) => {
  return json(await notificationService.markAllRead(ctx.userId));
});
