import { z, ZodError, type ZodType, type ZodTypeDef } from "zod";
import { AppError, badRequest, notFound, payloadTooLarge, unauthorized } from "@/lib/errors";
import { logger } from "@/lib/logger";
import { authenticate, type AuthMode, type AuthUser } from "@/server/auth/context";
import { idempotencyService } from "@/server/services/idempotency.service";

// Controller wrapper chung: parse request, xác thực, idempotency, map lỗi -> error envelope (C06, N01).

export const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
};

const DEFAULT_JSON_LIMIT = 1024 * 1024;

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(status === 204 ? null : JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...SECURITY_HEADERS, ...headers },
  });
}

export function errorResponse(err: AppError): Response {
  const body: { error: { code: string; message: string; details?: unknown } } = {
    error: { code: err.code, message: err.message },
  };
  if (err.details !== undefined) body.error.details = err.details;
  const headers: Record<string, string> = {};
  if (err.status === 429) {
    const d = err.details as { retryAfterSec?: number } | undefined;
    headers["Retry-After"] = String(d?.retryAfterSec ?? 60);
  }
  return json(body, err.status, headers);
}

export interface RequestContext<P> {
  req: Request;
  url: URL;
  params: P;
  ip: string;
  auth: AuthUser | null;
  /** userId của người gọi; ném 401 nếu route không xác thực. */
  readonly userId: string;
  user(): AuthUser;
  body<T>(schema: ZodType<T, ZodTypeDef, unknown>): Promise<T>;
  /** JSON body thô; service tự validate bằng zod. */
  input(): Promise<unknown>;
  /** Query string dạng object; service tự validate. */
  searchParams(): Record<string, string>;
  rawBody(limitBytes: number): Promise<Uint8Array>;
  query<T>(schema: ZodType<T, ZodTypeDef, unknown>): T;
}

export interface RouteOptions {
  auth?: AuthMode;
  /** Bật Idempotency-Key cho endpoint thay đổi dữ liệu. */
  idempotent?: boolean;
  jsonLimitBytes?: number;
}

type RouteFn<P> = (ctx: RequestContext<P>) => Promise<Response>;

function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return req.headers.get("x-real-ip") ?? "unknown";
}

function zodDetails(err: ZodError) {
  return err.issues.map((i) => ({ path: i.path.join("."), message: i.message, code: i.code }));
}

export function route<P extends Record<string, string> = Record<string, never>>(
  options: RouteOptions,
  fn: RouteFn<P>,
) {
  return async (req: Request, context: { params: Promise<P> }): Promise<Response> => {
    try {
      const params = ((await context?.params) ?? {}) as P;
      const url = new URL(req.url);
      const auth = await authenticate(req, options.auth ?? "user");
      let textCache: Promise<string> | null = null;
      const jsonLimit = options.jsonLimitBytes ?? DEFAULT_JSON_LIMIT;

      const readText = () => {
        textCache ??= (async () => {
          const len = Number(req.headers.get("content-length") ?? "0");
          if (len > jsonLimit) throw payloadTooLarge(jsonLimit);
          const buf = new Uint8Array(await req.arrayBuffer());
          if (buf.byteLength > jsonLimit) throw payloadTooLarge(jsonLimit);
          return new TextDecoder().decode(buf);
        })();
        return textCache;
      };

      const ctx: RequestContext<P> = {
        req,
        url,
        params,
        ip: clientIp(req),
        auth,
        get userId() {
          if (!auth) throw unauthorized();
          return auth.userId;
        },
        user() {
          if (!auth) throw unauthorized();
          return auth;
        },
        async body(schema) {
          const text = await readText();
          let parsed: unknown;
          try {
            parsed = text.length ? JSON.parse(text) : {};
          } catch {
            throw badRequest("invalid_json", "Request body is not valid JSON");
          }
          return schema.parse(parsed);
        },
        input() {
          return this.body(z.unknown());
        },
        searchParams() {
          return Object.fromEntries(url.searchParams.entries());
        },
        async rawBody(limitBytes) {
          const len = Number(req.headers.get("content-length") ?? "0");
          if (len > limitBytes) throw payloadTooLarge(limitBytes);
          const buf = new Uint8Array(await req.arrayBuffer());
          if (buf.byteLength > limitBytes) throw payloadTooLarge(limitBytes);
          return buf;
        },
        query(schema) {
          return schema.parse(Object.fromEntries(url.searchParams.entries()));
        },
      };

      const key = req.headers.get("idempotency-key");
      if (options.idempotent && key && auth) {
        const text = await readText();
        return await idempotencyService.run(
          { userId: auth.userId, key, method: req.method, path: url.pathname, body: text },
          () => fn(ctx).catch(handleError),
        );
      }
      return await fn(ctx);
    } catch (err) {
      return handleError(err);
    }
  };
}

export function handleError(err: unknown): Response {
  if (err instanceof AppError) return errorResponse(err);
  if (err instanceof ZodError) {
    return errorResponse(new AppError(422, "validation_error", "Invalid input", zodDetails(err)));
  }
  logger.error("unhandled_error", err);
  return errorResponse(new AppError(500, "internal_error", "Internal server error"));
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Tham số id trên path: không phải UUID => 404 (không lộ thông tin, không phân biệt với id không tồn tại). */
export function pid(value: string | undefined, what = "Resource"): string {
  if (!value || !UUID_RE.test(value)) throw notFound(what);
  return value;
}
