import { createHash, randomBytes, randomUUID } from "node:crypto";

export const newId = (): string => randomUUID();
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString("base64url");
export const sha256Hex = (data: string | Uint8Array): string => createHash("sha256").update(data).digest("hex");

/** JSON ổn định (khóa sắp xếp) để băm nội dung. */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`).join(",")}}`;
}
