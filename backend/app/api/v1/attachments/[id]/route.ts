import { json, pid, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await attachmentService.remove(ctx.userId, pid(ctx.params.id, "Attachment")));
});
