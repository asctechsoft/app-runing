import { json, pid, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await attachmentService.complete(ctx.userId, pid(ctx.params.id, "Attachment")));
});
