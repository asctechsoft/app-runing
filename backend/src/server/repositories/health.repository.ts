import { prisma } from "@/lib/prisma";

export const healthRepository = {
  async ping(): Promise<boolean> {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  },
};
