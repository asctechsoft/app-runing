import { json, pid, route } from "@/server/http/handler";
import { clubService } from "@/server/services/club.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await clubService.listEvents(ctx.userId, pid(ctx.params.id, "Club"), ctx.searchParams()));
});

export const POST = route<{ id: string }>({ idempotent: true }, async (ctx) => {
  return json(await clubService.createEvent(ctx.userId, pid(ctx.params.id, "Club"), await ctx.input()), 201);
});
