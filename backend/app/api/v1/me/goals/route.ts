import { json, route } from "@/server/http/handler";
import { meService } from "@/server/services/me.service";

export const GET = route({}, async (ctx) => {
  return json(await meService.listGoals(ctx.userId));
});

export const POST = route({ idempotent: true }, async (ctx) => {
  const r = await meService.createGoal(ctx.userId, await ctx.input());
  return json(r.goal, r.created ? 201 : 200);
});
