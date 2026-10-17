import { z } from "zod";
import { badRequest } from "@/lib/errors";

// Cursor pagination {items, nextCursor} (C06). Cursor opaque = base64url của {t, id}.
export interface CursorPos {
  t: number;
  id: string;
}

export function encodeCursor(pos: CursorPos): string {
  return Buffer.from(JSON.stringify(pos)).toString("base64url");
}

export function decodeCursor(cursor: string | undefined): CursorPos | null {
  if (!cursor) return null;
  try {
    const v = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as unknown;
    const parsed = z.object({ t: z.number().int(), id: z.string().min(1).max(100) }).parse(v);
    return parsed;
  } catch {
    throw badRequest("invalid_cursor", "Cursor is invalid");
  }
}

export const pageQuery = z.object({
  cursor: z.string().max(500).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

/** Điều kiện "sau cursor" cho thứ tự (createdAt desc, id desc). */
export function beforeCursor(pos: CursorPos | null, field = "createdAt") {
  if (!pos) return {};
  const at = new Date(pos.t);
  return { OR: [{ [field]: { lt: at } }, { [field]: at, id: { lt: pos.id } }] };
}

export function toPage<T extends { id: string }>(
  rows: T[],
  limit: number,
  timeOf: (row: T) => Date,
): { items: T[]; nextCursor: string | null } {
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const last = items[items.length - 1];
  return { items, nextCursor: hasMore && last ? encodeCursor({ t: timeOf(last).getTime(), id: last.id }) : null };
}
