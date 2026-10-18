import { json, route } from "@/server/http/handler";
import { syncService } from "@/server/services/sync.service";

export const GET = route({}, async (ctx) => {
  return json(await syncService.pull(ctx.userId, ctx.searchParams()));
});
