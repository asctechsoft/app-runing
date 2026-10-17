import { prisma, type Db } from "@/lib/prisma";
import { newId } from "@/lib/crypto";

export const feedbackRepository = {
  create(data: { ownerId: string | null; message: string; diagnostics: string | null; appVersion: string | null }, db: Db = prisma) {
    return db.feedback.create({ data: { id: newId(), ...data } });
  },
  deleteAllOwned(ownerId: string, db: Db = prisma) {
    return db.feedback.deleteMany({ where: { ownerId } });
  },
};
