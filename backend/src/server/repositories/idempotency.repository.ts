import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";

export const idempotencyRepository = {
  find(userId: string, key: string, db: Db = prisma) {
    return db.idempotencyRecord.findUnique({ where: { userId_key: { userId, key } } });
  },
  create(
    data: {
      userId: string;
      key: string;
      method: string;
      path: string;
      requestHash: string;
      statusCode: number;
      responseBody: string;
      responseHash: string;
    },
    db: Db = prisma,
  ) {
    return db.idempotencyRecord.create({ data: { id: newId(), ...data } });
  },
  deleteForUser(userId: string, db: Db = prisma) {
    return db.idempotencyRecord.deleteMany({ where: { userId } });
  },
};
