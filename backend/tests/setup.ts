import { copyFileSync, mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import path from "node:path";

// Mỗi file test: DB SQLite tạm + thư mục storage tạm riêng, cấu hình môi trường test.
const dir = path.resolve(__dirname, "../.tmp-test");
const id = randomUUID();
const db = path.join(dir, `test-${id}.db`);
copyFileSync(path.join(dir, "template.db"), db);
const storageDir = path.join(dir, `storage-${id}`);
mkdirSync(storageDir, { recursive: true });

Object.assign(process.env, {
  NODE_ENV: "test",
  DATABASE_URL: `file:${db.replace(/\\/g, "/")}`,
  JWT_SECRET: "test-secret-0123456789-abcdefghijklmnopqrstuvwxyz",
  MAILER_DRIVER: "memory",
  JOB_RUNNER: "manual",
  STORAGE_DRIVER: "local",
  STORAGE_DIR: storageDir,
  BCRYPT_ROUNDS: "4",
  RATE_LIMIT_AUTH_PER_MIN: "10000",
  RATE_LIMIT_SOCIAL_PER_MIN: "10000",
  RATE_LIMIT_LOOKUP_PER_HOUR: "10000",
  RATE_LIMIT_FEEDBACK_PER_HOUR: "10000",
  LOG_SILENT: "1",
  PUBLIC_BASE_URL: "http://test.local",
  APP_LINK_BASE: "stride://auth",
});
