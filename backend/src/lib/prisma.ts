import { PrismaClient, Prisma } from "@prisma/client";

// Prisma Client singleton, an toàn khi hot-reload của Next dev.
const globalForPrisma = globalThis as unknown as { __stridePrisma?: PrismaClient };

export const prisma: PrismaClient =
  globalForPrisma.__stridePrisma ?? new PrismaClient({ log: process.env.LOG_SILENT === "1" ? [] : ["error"] });

if (process.env.NODE_ENV !== "production") globalForPrisma.__stridePrisma = prisma;

/** Client dùng trong repository: client gốc hoặc client của transaction. */
export type Db = PrismaClient | Prisma.TransactionClient;

export function runInTransaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
  return prisma.$transaction(fn);
}

export function isUniqueViolation(err: unknown): boolean {
  return err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002";
}
