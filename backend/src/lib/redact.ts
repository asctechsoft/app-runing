// N01: loại bỏ token, mật khẩu, tọa độ khỏi log.
const SENSITIVE_KEY =
  /pass(word)?|token|secret|authorization|cookie|refresh|^lat$|^lon$|^lng$|latitude|longitude|polyline|signature|idempotency/i;
const JWT_LIKE = /eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}/g;
const BEARER = /Bearer\s+[A-Za-z0-9._~+/=-]+/gi;
const TOKEN_QUERY = /([?&](token|code|key)=)[^&\s]+/gi;
// Dạng key=value / "key": value trong văn bản tự do (log chẩn đoán, chuỗi JSON).
const KV_SECRET =
  /\b(password|passwd|pwd|access_?token|refresh_?token|token|secret|authorization|lat|lon|lng|latitude|longitude)(["']?\s*[:=]\s*["']?)(?!\[REDACTED)[^\s,"'&}\]]+/gi;

export function redactString(s: string): string {
  return s
    .replace(JWT_LIKE, "[REDACTED_JWT]")
    .replace(BEARER, "Bearer [REDACTED]")
    .replace(TOKEN_QUERY, "$1[REDACTED]")
    .replace(KV_SECRET, "$1$2[REDACTED]");
}

export function redact(value: unknown, depth = 0): unknown {
  if (depth > 8) return "[TRUNCATED]";
  if (typeof value === "string") return redactString(value);
  if (Array.isArray(value)) return value.map((v) => redact(v, depth + 1));
  if (value instanceof Error) return { name: value.name, message: redactString(value.message) };
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = SENSITIVE_KEY.test(k) ? "[REDACTED]" : redact(v, depth + 1);
    }
    return out;
  }
  return value;
}

/** Làm sạch văn bản chẩn đoán trước khi lưu: nếu là JSON thì redact theo khóa, luôn redact chuỗi. */
export function redactText(text: string): string {
  try {
    const parsed = JSON.parse(text) as unknown;
    if (parsed && typeof parsed === "object") return redactString(JSON.stringify(redact(parsed)));
  } catch {
    // không phải JSON
  }
  return redactString(text);
}

export function maskEmail(email: string): string {
  const [local = "", domain = ""] = email.split("@");
  return `${local.slice(0, 1)}***@${domain}`;
}
