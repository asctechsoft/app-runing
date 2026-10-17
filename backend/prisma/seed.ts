/**
 * DEV FIXTURES ONLY — dữ liệu mẫu cho môi trường phát triển (clubs, challenges, routes).
 * KHÔNG chạy ở production: script tự thoát nếu NODE_ENV=production hoặc DATABASE_URL không phải sqlite
 * mà không có ALLOW_DEV_SEED=1. Mọi bản ghi được đánh dấu isDevFixture=true và tên có tiền tố "[DEV]".
 * Polyline của route là hình học giả lập cho dev, KHÔNG phải dữ liệu bản đồ thật.
 */
import { randomBytes, randomUUID } from "node:crypto";
import bcrypt from "bcryptjs";
import { PrismaClient } from "@prisma/client";

if (process.env.NODE_ENV === "production") {
  console.error("Refusing to seed: NODE_ENV=production. Dev fixtures must never be loaded in production.");
  process.exit(1);
}
const url = process.env.DATABASE_URL ?? "";
if (!url.startsWith("file:") && process.env.ALLOW_DEV_SEED !== "1") {
  console.error("Refusing to seed a non-SQLite database without ALLOW_DEV_SEED=1 (dev/staging only).");
  process.exit(1);
}

const prisma = new PrismaClient();
const DEV_OWNER_EMAIL = "dev-fixtures-owner@stride.invalid";

/** Mã hóa polyline Google (precision 5). */
function encodePolyline(points: Array<[number, number]>): string {
  let out = "";
  let prevLat = 0;
  let prevLon = 0;
  const enc = (v: number) => {
    let n = v < 0 ? ~(v << 1) : v << 1;
    let s = "";
    while (n >= 0x20) {
      s += String.fromCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    return s + String.fromCharCode(n + 63);
  };
  for (const [lat, lon] of points) {
    const la = Math.round(lat * 1e5);
    const lo = Math.round(lon * 1e5);
    out += enc(la - prevLat) + enc(lo - prevLon);
    prevLat = la;
    prevLon = lo;
  }
  return out;
}

function loop(lat: number, lon: number, radiusDeg: number, n = 12): Array<[number, number]> {
  const pts: Array<[number, number]> = [];
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * 2 * Math.PI;
    pts.push([lat + radiusDeg * Math.sin(a), lon + radiusDeg * Math.cos(a)]);
  }
  return pts;
}

async function main() {
  // Chủ sở hữu các club mẫu: mật khẩu ngẫu nhiên không in ra => không thể đăng nhập.
  const owner = await prisma.user.upsert({
    where: { email: DEV_OWNER_EMAIL },
    update: {},
    create: {
      id: randomUUID(),
      email: DEV_OWNER_EMAIL,
      passwordHash: await bcrypt.hash(randomBytes(24).toString("base64url"), 10),
      displayName: "[DEV] Fixture owner",
      emailVerifiedAt: new Date(),
      profile: { create: { displayName: "[DEV] Fixture owner" } },
    },
  });

  await prisma.club.deleteMany({ where: { isDevFixture: true } });
  await prisma.challenge.deleteMany({ where: { isDevFixture: true } });
  await prisma.route.deleteMany({ where: { isDevFixture: true } });

  const clubs = [
    { name: "[DEV] Riverside Runners", regionText: "Ho Chi Minh City", lat: 10.776, lon: 106.703 },
    { name: "[DEV] Lake Loop Club", regionText: "Hanoi", lat: 21.028, lon: 105.852 },
    { name: "[DEV] Beach Joggers", regionText: "Da Nang", lat: 16.061, lon: 108.247 },
  ];
  for (const c of clubs) {
    const id = randomUUID();
    await prisma.club.create({
      data: {
        id,
        ...c,
        description: "Development fixture club. Not a real community.",
        searchText: `${c.name} ${c.regionText}`.toLowerCase(),
        ownerId: owner.id,
        isDevFixture: true,
        memberships: { create: { id: randomUUID(), userId: owner.id, role: "owner", status: "approved" } },
      },
    });
  }

  const year = new Date().getUTCFullYear();
  const month = String(new Date().getUTCMonth() + 1).padStart(2, "0");
  const lastDay = new Date(Date.UTC(year, new Date().getUTCMonth() + 1, 0)).getUTCDate();
  const challenges = [
    { title: "[DEV] Run 50 km this month", activityTypesJson: '["run","indoorRun"]', targetType: "distance", targetValue: 50_000 },
    { title: "[DEV] 12 activities this month", activityTypesJson: '["run","walk","indoorRun"]', targetType: "count", targetValue: 12 },
    { title: "[DEV] 10 hours on your feet", activityTypesJson: '["run","walk"]', targetType: "time", targetValue: 10 * 3600 * 1000 },
  ];
  for (const ch of challenges) {
    await prisma.challenge.create({
      data: {
        id: randomUUID(),
        ...ch,
        description: "Development fixture challenge.",
        startDate: `${year}-${month}-01`,
        endDate: `${year}-${month}-${String(lastDay).padStart(2, "0")}`,
        tzId: "Asia/Ho_Chi_Minh",
        badgeKey: "dev-badge",
        isDevFixture: true,
      },
    });
  }

  const routes = [
    { name: "[DEV] Riverside loop", region: "Ho Chi Minh City", lat: 10.776, lon: 106.703, r: 0.01, surface: "road", distanceM: 6900 },
    { name: "[DEV] Lake circuit", region: "Hanoi", lat: 21.028, lon: 105.852, r: 0.004, surface: "road", distanceM: 2800 },
    { name: "[DEV] Hill trail", region: "Da Nang", lat: 16.1, lon: 108.27, r: 0.015, surface: "trail", distanceM: 10_300 },
  ];
  for (const r of routes) {
    await prisma.route.create({
      data: {
        id: randomUUID(),
        name: r.name,
        region: r.region,
        regionLower: r.region.toLowerCase(),
        distanceM: r.distanceM,
        surface: r.surface,
        polyline: encodePolyline(loop(r.lat, r.lon, r.r)),
        attribution: "Synthetic dev fixture geometry — not real map data",
        startLat: r.lat,
        startLon: r.lon + r.r,
        isDevFixture: true,
      },
    });
  }
  console.info(`Seeded dev fixtures: ${clubs.length} clubs, ${challenges.length} challenges, ${routes.length} routes.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
