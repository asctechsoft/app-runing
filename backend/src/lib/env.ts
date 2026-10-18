// Đọc cấu hình môi trường tại thời điểm gọi (để test có thể đổi giá trị).
export function isProduction(): boolean {
  return process.env.NODE_ENV === "production";
}

export function jwtSecret(): Uint8Array {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("JWT_SECRET must be set (>= 32 chars)");
  }
  return new TextEncoder().encode(secret);
}

export function publicBaseUrl(): string {
  return (process.env.PUBLIC_BASE_URL ?? "http://localhost:3001").replace(/\/$/, "");
}

export function appLinkBase(): string {
  return (process.env.APP_LINK_BASE ?? "stride://auth").replace(/\/$/, "");
}

export function intEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  const n = raw ? Number.parseInt(raw, 10) : NaN;
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
