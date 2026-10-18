import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";

export const userRepository = {
  findByEmail(email: string, db: Db = prisma) {
    return db.user.findUnique({ where: { email } });
  },
  findById(id: string, db: Db = prisma) {
    return db.user.findUnique({ where: { id } });
  },
  findManyActiveByIds(ids: string[], db: Db = prisma) {
    return db.user.findMany({ where: { id: { in: ids }, status: "active" }, select: { id: true } });
  },
  create(
    data: { id: string; email: string; passwordHash: string | null; displayName?: string | null; emailVerifiedAt?: Date | null },
    db: Db = prisma,
  ) {
    return db.user.create({ data: { ...data, profile: { create: { displayName: data.displayName ?? null } } } });
  },
  update(id: string, data: { emailVerifiedAt?: Date; passwordHash?: string | null; status?: string; deletionRequestedAt?: Date | null; email?: string; displayName?: string | null }, db: Db = prisma) {
    return db.user.update({ where: { id }, data });
  },
};

export const authIdentityRepository = {
  find(provider: string, providerUid: string, db: Db = prisma) {
    return db.authIdentity.findUnique({ where: { provider_providerUid: { provider, providerUid } } });
  },
  create(data: { userId: string; provider: string; providerUid: string; email: string | null }, db: Db = prisma) {
    return db.authIdentity.create({ data: { id: newId(), ...data } });
  },
  deleteAllForUser(userId: string, db: Db = prisma) {
    return db.authIdentity.deleteMany({ where: { userId } });
  },
};

export const sessionRepository = {
  create(userId: string, db: Db = prisma) {
    return db.session.create({ data: { id: newId(), userId } });
  },
  findWithUser(id: string, db: Db = prisma) {
    return db.session.findUnique({ where: { id }, include: { user: true } });
  },
  revoke(id: string, reason: string, db: Db = prisma) {
    return db.session.updateMany({ where: { id, revokedAt: null }, data: { revokedAt: new Date(), revokeReason: reason } });
  },
  revokeAllForUser(userId: string, reason: string, db: Db = prisma) {
    return db.session.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date(), revokeReason: reason } });
  },
  markReauth(id: string, db: Db = prisma) {
    return db.session.update({ where: { id }, data: { reauthAt: new Date() } });
  },
};

export const refreshTokenRepository = {
  create(data: { sessionId: string; userId: string; tokenHash: string; expiresAt: Date }, db: Db = prisma) {
    return db.refreshToken.create({ data: { id: newId(), ...data } });
  },
  findByHash(tokenHash: string, db: Db = prisma) {
    return db.refreshToken.findUnique({ where: { tokenHash }, include: { session: true } });
  },
  /** Đánh dấu đã dùng có điều kiện (chống race): trả về số bản ghi bị cập nhật. */
  async markUsed(id: string, db: Db = prisma) {
    const r = await db.refreshToken.updateMany({ where: { id, usedAt: null }, data: { usedAt: new Date() } });
    return r.count;
  },
};

export const emailTokenRepository = {
  create(data: { userId: string; purpose: string; tokenHash: string; expiresAt: Date }, db: Db = prisma) {
    return db.emailToken.create({ data: { id: newId(), ...data } });
  },
  findValid(tokenHash: string, purpose: string, db: Db = prisma) {
    return db.emailToken.findFirst({ where: { tokenHash, purpose, usedAt: null, expiresAt: { gt: new Date() } } });
  },
  async consume(id: string, db: Db = prisma) {
    const r = await db.emailToken.updateMany({ where: { id, usedAt: null }, data: { usedAt: new Date() } });
    return r.count;
  },
  invalidateAll(userId: string, purpose: string, db: Db = prisma) {
    return db.emailToken.updateMany({ where: { userId, purpose, usedAt: null }, data: { usedAt: new Date() } });
  },
};
