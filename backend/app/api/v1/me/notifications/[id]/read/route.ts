import { json, pid, route } from "@/server/http/handler";
import { notificationService } from "@/server/services/notification.service";

export const POST = route<{ id: string }>({}, async (ctx) => {
  return json(await notificationService.markRead(ctx.userId, pid(ctx.params.id, "Notification")));
});
