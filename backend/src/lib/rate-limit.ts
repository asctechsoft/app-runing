import { intEnv } from "@/lib/env";
import { tooManyRequests } from "@/lib/errors";

// Interface để sau này thay bằng Redis; hiện dùng bộ nhớ trong process (fixed window).
export interface RateLimiter {
  consume(key: string, limit: number, windowMs: number): Promise<{ allowed: boolean; retryAfterMs: number }>;
}

export class MemoryRateLimiter implements RateLimiter {
  private buckets = new Map<string, { count: number; resetAt: number }>();

  async consume(key: string, limit: number, windowMs: number) {
    const now = Date.now();
    let b = this.buckets.get(key);
    if (!b || b.resetAt <= now) {
      b = { count: 0, resetAt: now + windowMs };
      this.buckets.set(key, b);
    }
    b.count += 1;
    if (this.buckets.size > 50_000) this.sweep(now);
    return { allowed: b.count <= limit, retryAfterMs: Math.max(0, b.resetAt - now) };
  }

  private sweep(now: number) {
    for (const [k, v] of this.buckets) if (v.resetAt <= now) this.buckets.delete(k);
  }

  reset() {
    this.buckets.clear();
  }
}

const g = globalThis as unknown as { __strideLimiter?: MemoryRateLimiter };
export function rateLimiter(): MemoryRateLimiter {
  g.__strideLimiter ??= new MemoryRateLimiter();
  return g.__strideLimiter;
}

async function enforce(key: string, limit: number, windowMs = 60_000) {
  const r = await rateLimiter().consume(key, limit, windowMs);
  if (!r.allowed) throw tooManyRequests(Math.ceil(r.retryAfterMs / 1000));
}

/** Giới hạn endpoint xác thực theo IP (+ định danh như email nếu có). */
export async function limitAuth(route: string, ip: string, identity?: string) {
  const limit = intEnv("RATE_LIMIT_AUTH_PER_MIN", 10);
  await enforce(`auth:${route}:ip:${ip}`, limit);
  if (identity) await enforce(`auth:${route}:id:${identity.toLowerCase()}`, limit);
}

/** Tra cứu người dùng theo email là vector dò tài khoản: giới hạn theo user mỗi giờ. */
export async function limitUserLookup(userId: string) {
  await enforce(`lookup:${userId}`, intEnv("RATE_LIMIT_LOOKUP_PER_HOUR", 20), 3_600_000);
}

/** Feedback: theo user nếu đã đăng nhập, ngược lại theo IP. */
export async function limitFeedback(identity: string) {
  await enforce(`feedback:${identity}`, intEnv("RATE_LIMIT_FEEDBACK_PER_HOUR", 10), 3_600_000);
}

/** Giới hạn hành động xã hội theo người dùng (post, comment, cheer, report). */
export async function limitSocial(action: string, userId: string) {
  await enforce(`social:${action}:${userId}`, intEnv("RATE_LIMIT_SOCIAL_PER_MIN", 30));
}
