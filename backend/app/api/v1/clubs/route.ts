import { json, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const GET = route({}, async (ctx) => {
  return json(await clubService.search(ctx.userId, ctx.searchParams()));
});

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await clubService.create(ctx.userId, await ctx.input()), 201);
});
