// H01: mọi truy vấn dữ liệu người dùng phải đi qua helper này để luôn có điều kiện ownerId.
// Không tìm theo id trần rồi so sánh owner sau — truy vấn không khớp owner trả null -> 404.

export function assertUserId(userId: string): string {
  if (typeof userId !== "string" || userId.length === 0 || userId.startsWith("guest:")) {
    throw new Error("ownerScope requires an authenticated userId");
  }
  return userId;
}

export function ownerScope<T extends object>(userId: string, where: T = {} as T): T & { ownerId: string } {
  return { ...where, ownerId: assertUserId(userId) };
}

/** Như ownerScope nhưng loại bản ghi tombstone. */
export function liveOwnerScope<T extends object>(
  userId: string,
  where: T = {} as T,
): T & { ownerId: string; deletedAt: null } {
  return { ...ownerScope(userId, where), deletedAt: null };
}
