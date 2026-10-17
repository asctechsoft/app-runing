/// <reference types="vite/client" />
import { randomUUID } from "node:crypto";
import { memoryMailer } from "@/lib/mailer";

// Gọi trực tiếp route handler thật trong app/api (không cần chạy server Next).
type Handler = (req: Request, ctx: { params: Promise<Record<string, string>> }) => Promise<Response>;
type RouteModule = Partial<Record<"GET" | "POST" | "PUT" | "PATCH" | "DELETE", Handler>>;

const modules = import.meta.glob<RouteModule>("../app/api/**/route.ts");

const table = Object.entries(modules)
  .map(([file, load]) => {
    const pattern = file.replace(/^\.\.\/app/, "").replace(/\/route\.ts$/, "");
    const names: string[] = [];
    const re = new RegExp(
      "^" +
        pattern.replace(/\[(\w+)\]/g, (_m, name: string) => {
          names.push(name);
          return "([^/]+)";
        }) +
        "$",
    );
    return { pattern, re, names, load };
  })
  .sort((a, b) => a.names.length - b.names.length);

export const routePatterns = table.map((t) => t.pattern);

export interface ApiResponse {
  status: number;
  headers: Headers;
  body: any; // eslint-disable-line @typescript-eslint/no-explicit-any
  text: string;
  bytes: Uint8Array;
}

export interface ApiOptions {
  token?: string;
  body?: unknown;
  raw?: Uint8Array | string;
  headers?: Record<string, string>;
  ip?: string;
}

export async function api(method: string, url: string, opts: ApiOptions = {}): Promise<ApiResponse> {
  const u = new URL(url, "http://test.local");
  const entry = table.find((t) => t.re.test(u.pathname));
  if (!entry) return { status: 404, headers: new Headers(), body: null, text: "", bytes: new Uint8Array() };
  const match = entry.re.exec(u.pathname)!;
  const params = Object.fromEntries(entry.names.map((n, i) => [n, decodeURIComponent(match[i + 1]!)]));
  const mod = await entry.load();
  const handler = mod[method as keyof RouteModule];
  if (!handler) return { status: 405, headers: new Headers(), body: null, text: "", bytes: new Uint8Array() };

  const headers: Record<string, string> = { "x-forwarded-for": opts.ip ?? "10.0.0.1", ...opts.headers };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  let body: BodyInit | undefined;
  if (opts.raw !== undefined) body = typeof opts.raw === "string" ? opts.raw : new Uint8Array(opts.raw);
  else if (opts.body !== undefined) {
    body = JSON.stringify(opts.body);
    headers["content-type"] ??= "application/json";
  }
  const res = await handler(new Request(u, { method, headers, body }), { params: Promise.resolve(params) });
  const bytes = new Uint8Array(await res.arrayBuffer());
  const text = new TextDecoder().decode(bytes);
  let parsed: unknown = null;
  if ((res.headers.get("content-type") ?? "").includes("application/json") && text) parsed = JSON.parse(text);
  return { status: res.status, headers: res.headers, body: parsed, text, bytes };
}

export interface TestUser {
  userId: string;
  email: string;
  password: string;
  token: string;
  refreshToken: string;
}

export async function registerUser(name = "Runner"): Promise<TestUser> {
  const email = `u-${randomUUID()}@example.com`;
  const password = "secret123";
  const res = await api("POST", "/api/v1/auth/register", { body: { email, password, displayName: name } });
  if (res.status !== 201) throw new Error(`register failed ${res.status} ${res.text}`);
  return { userId: res.body.user.id, email, password, token: res.body.tokens.accessToken, refreshToken: res.body.tokens.refreshToken };
}

export function lastMailToken(to: string): string {
  const mail = [...memoryMailer().outbox].reverse().find((m) => m.to === to);
  const token = mail?.actionUrl ? new URL(mail.actionUrl.replace("stride://", "http://")).searchParams.get("token") : null;
  if (!token) throw new Error(`no mail token for ${to}`);
  return token;
}

export const DAY = 86_400_000;

export function activityBody(overrides: Record<string, unknown> = {}) {
  const startedAt = Date.UTC(2026, 9, 10, 6, 0, 0);
  return {
    type: "run",
    status: "saved",
    startedAt,
    endedAt: startedAt + 30 * 60_000,
    tzId: "Asia/Ho_Chi_Minh",
    tzOffsetMin: 420,
    distanceM: 5000,
    movingMs: 29 * 60_000,
    elapsedMs: 30 * 60_000,
    avgPaceSecPerKm: 348,
    steps: 5200,
    caloriesKcal: null,
    calorieModel: null,
    weightKgUsed: null,
    title: "Morning run",
    feeling: "steady",
    notes: null,
    privacy: "onlyMe",
    shareRoute: false,
    goal: { type: "free" },
    hasGps: true,
    distanceSource: "gps",
    ...overrides,
  };
}

export async function createActivity(user: TestUser, overrides: Record<string, unknown> = {}, id = randomUUID()) {
  const res = await api("PUT", `/api/v1/activities/${id}`, { token: user.token, body: { activity: activityBody(overrides) } });
  if (res.status !== 201) throw new Error(`create activity failed ${res.status} ${res.text}`);
  return res.body as { id: string; revision: number };
}

export { randomUUID };
