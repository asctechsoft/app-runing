import { json, pid, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await attachmentService.downloadUrl(ctx.userId, pid(ctx.params.id, "Attachment")));
});
