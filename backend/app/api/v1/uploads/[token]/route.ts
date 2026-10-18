import { json, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";
import { MAX_ATTACHMENT_BYTES } from "@/server/validators/misc";

export const PUT = route<{ token: string }>({ auth: "none" }, async (ctx) => {
  const bytes = await ctx.rawBody(MAX_ATTACHMENT_BYTES);
  await attachmentService.receiveUpload(ctx.params.token, ctx.req.headers.get("content-type"), bytes);
  return json(null, 204);
});
