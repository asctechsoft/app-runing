import { json, pid, route } from "@/server/http/handler";
import { trackService } from "@/server/services/track.service";
import { MAX_CHUNK_BYTES } from "@/server/validators/activity";

export const PUT = route<{ id: string; seq: string }>({}, async (ctx) => {
  pid(ctx.params.id, "Activity");
  const bytes = await ctx.rawBody(MAX_CHUNK_BYTES);
  const r = await trackService.putChunk(ctx.userId, ctx.params, bytes, ctx.req.headers.get("x-checksum-sha256"));
  return json(r.chunk, r.status);
});
