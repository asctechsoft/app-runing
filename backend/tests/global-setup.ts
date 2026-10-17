import { execSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";

// Tạo DB SQLite mẫu (đã migrate) một lần; mỗi file test copy ra DB tạm riêng (tests/setup.ts).
export default function setup() {
  const dir = path.resolve(__dirname, "../.tmp-test");
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const template = path.join(dir, "template.db").replace(/\\/g, "/");
  execSync("npx prisma migrate deploy", {
    cwd: path.resolve(__dirname, ".."),
    env: { ...process.env, DATABASE_URL: `file:${template}` },
    stdio: "pipe",
  });
  return () => rmSync(dir, { recursive: true, force: true });
}
