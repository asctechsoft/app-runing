import { json, route } from "@/server/http/handler";
import { syncService } from "@/server/services/sync.service";

export const POST = route({ jsonLimitBytes: 4 * 1024 * 1024 }, async (ctx) => {
  return json(await syncService.push(ctx.userId, await ctx.input()));
});
