import { SECURITY_HEADERS, pid, route } from "@/server/http/handler";
import { trackService } from "@/server/services/track.service";

export const GET = route<{ id: string }>({}, async (ctx) => {
  const id = pid(ctx.params.id, "Activity");
  const gpx = await trackService.gpx(ctx.userId, id);
  return new Response(gpx, {
    status: 200,
    headers: { ...SECURITY_HEADERS, "Content-Type": "application/gpx+xml; charset=utf-8", "Content-Disposition": `attachment; filename="${id}.gpx"` },
  });
});
