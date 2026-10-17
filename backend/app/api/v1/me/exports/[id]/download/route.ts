import { SECURITY_HEADERS, pid, route } from "@/server/http/handler";
import { jobService } from "@/server/services/job.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  const id = pid(ctx.params.id, "Export");
  const bytes = await jobService.downloadExport(ctx.userId, id);
  return new Response(new Uint8Array(bytes), {
    status: 200,
    headers: {
      ...SECURITY_HEADERS,
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="stride-export-${id}.zip"`,
      "Cache-Control": "private, no-store",
    },
  });
});
