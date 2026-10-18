import { json, pid, route } from "@/server/http/handler";
import { activityService } from "@/server/services/activity.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await activityService.get(ctx.userId, pid(ctx.params.id, "Activity")));
});

export const PUT = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  const r = await activityService.upsert(ctx.userId, pid(ctx.params.id, "Activity"), await ctx.input());
  return json(r.activity, r.created ? 201 : 200);
});

export const PATCH = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await activityService.patch(ctx.userId, pid(ctx.params.id, "Activity"), await ctx.input()));
});

export const DELETE = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await activityService.remove(ctx.userId, pid(ctx.params.id, "Activity"), ctx.searchParams()));
});
