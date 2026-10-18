import { json, route } from "@/server/http/handler";
import { jobService } from "@/server/services/job.service";

export const GET = route({ auth: "userAllowDeleting" }, async (ctx) => {
  return json(await jobService.deletionStatus(ctx.userId));
});

export const POST = route({ auth: "userAllowDeleting" }, async (ctx) => {
  return json(await jobService.requestDeletion(ctx.user()), 202);
});
