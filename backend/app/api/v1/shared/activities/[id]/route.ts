import { json, pid, route } from "@/server/http/handler";
import { privacyService } from "@/server/services/privacy.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await privacyService.getShared(ctx.userId, pid(ctx.params.id, "Activity")));
});
