import { SECURITY_HEADERS, route } from "@/server/http/handler";
import { attachmentService } from "@/server/services/attachment.service";

export const GET = route<{ token: string }>({ auth: "none" }, async (ctx) => {
  const f = await attachmentService.serve(ctx.params.token);
  return new Response(new Uint8Array(f.bytes), {
    status: 200,
    headers: { ...SECURITY_HEADERS, "Content-Type": f.mime, "Cache-Control": "private, no-store", "Content-Disposition": "inline" },
  });
});
