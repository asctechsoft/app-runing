import { json, route } from "@/server/http/handler";
import { jobService } from "@/server/services/job.service";

export const POST = route({ idempotent: true }, async (ctx) => {
  return json(await jobService.createExport(ctx.userId), 202);
});
