import { json, pid, route } from "@/server/http/handler";
import { jobService } from "@/server/services/job.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  return json(await jobService.getExport(ctx.userId, pid(ctx.params.id, "Export")));
});
