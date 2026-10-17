import { json, pid, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await attachmentService.list(ctx.userId, pid(ctx.params.id, "Activity")));
});

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await attachmentService.requestUpload(ctx.userId, pid(ctx.params.id, "Activity"), await ctx.input()), 201);
});
