// Worker chạy job export / xóa tài khoản khi JOB_RUNNER=manual. Dùng: npm run jobs
import { prisma } from "../src/lib/prisma";
import { jobService } from "../src/server/services/job.service";

async function main() {
  const n = await jobService.processPending();
  console.info(`Processed ${n} job(s).`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
