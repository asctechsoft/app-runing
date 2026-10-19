// DEV FIXTURES ONLY — nạp dữ liệu mẫu (clubs, challenges, routes, events) vào Cloud Firestore bằng Admin SDK.
// Port từ backend/prisma/seed.ts. Mọi document có isDevFixture: true và tên tiền tố "[DEV]". Polyline là hình học giả lập,
// KHÔNG phải dữ liệu bản đồ thật. Không chạy trên project production thật của người dùng cuối.
//
// Chạy (Node 20+):
//   cd scripts && npm install
//   # Tải service account key (Firebase Console > Project settings > Service accounts), KHÔNG commit file này:
//   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\serviceAccount.json        (PowerShell: $env:GOOGLE_APPLICATION_CREDENTIALS="...")
//   node seed-firestore.mjs --yes
//
// Idempotent: ID cố định (dev-*), chạy lại chỉ cập nhật trường tĩnh và cửa sổ thời gian; KHÔNG ghi đè các bộ đếm
// (memberCount, participantCount, goingCount) của document đã tồn tại. Thiếu cờ --yes thì từ chối chạy.

import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const PROJECT_ID = "app-runing-667b3";
const OWNER_ID = "dev-fixture-owner";
const OWNER_NAME = "[DEV] Fixture owner";
const TZ_OFFSET_MS = 7 * 3600 * 1000; // Asia/Ho_Chi_Minh (không DST)

if (!process.argv.includes("--yes")) {
  console.error("Từ chối chạy: thêm cờ --yes để xác nhận nạp dữ liệu DEV vào project", PROJECT_ID);
  process.exit(1);
}
if (process.env.NODE_ENV === "production") {
  console.error("Từ chối chạy: NODE_ENV=production.");
  process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Thiếu GOOGLE_APPLICATION_CREDENTIALS (đường dẫn file service account JSON).");
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

/** Mã hóa polyline Google (precision 5). */
function encodePolyline(points) {
  let out = "";
  let prevLat = 0;
  let prevLon = 0;
  const enc = (v) => {
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

function loop(lat, lon, radiusDeg, n = 12) {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * 2 * Math.PI;
    pts.push([lat + radiusDeg * Math.sin(a), lon + radiusDeg * Math.cos(a)]);
  }
  return pts;
}

/** Ghi document; bộ đếm chỉ được khởi tạo khi document chưa tồn tại. */
async function upsert(ref, fixed, counters = {}) {
  const snap = await ref.get();
  if (snap.exists) await ref.set(fixed, { merge: true });
  else await ref.set({ ...fixed, ...counters });
}

const now = Date.now();
const nowLocal = new Date(now + TZ_OFFSET_MS);
const year = nowLocal.getUTCFullYear();
const month = nowLocal.getUTCMonth();
const monthStartMs = Date.UTC(year, month, 1) - TZ_OFFSET_MS;
const monthEndMs = Date.UTC(year, month + 1, 1) - TZ_OFFSET_MS - 1;
const pad = (n) => String(n).padStart(2, "0");
const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
const startDate = `${year}-${pad(month + 1)}-01`;
const endDate = `${year}-${pad(month + 1)}-${pad(lastDay)}`;

// ---- Clubs (+ membership của chủ sở hữu giả, không đăng nhập được)
const clubs = [
  { id: "dev-club-riverside", name: "[DEV] Riverside Runners", region: "Ho Chi Minh City" },
  { id: "dev-club-lake-loop", name: "[DEV] Lake Loop Club", region: "Hanoi" },
  { id: "dev-club-beach", name: "[DEV] Beach Joggers", region: "Da Nang" },
];
for (const c of clubs) {
  const ref = db.collection("clubs").doc(c.id);
  await upsert(
    ref,
    {
      name: c.name,
      nameLower: c.name.toLowerCase(),
      description: "Development fixture club. Not a real community.",
      region: c.region,
      visibility: "public",
      ownerId: OWNER_ID,
      createdAt: now,
      isDevFixture: true,
    },
    { memberCount: 1 },
  );
  await ref.collection("members").doc(OWNER_ID).set(
    { userId: OWNER_ID, clubId: c.id, role: "owner", status: "active", displayName: OWNER_NAME, joinedAt: now },
    { merge: true },
  );
}

// ---- Events: một buổi chạy thứ Bảy 06:00 (giờ VN) kế tiếp cho mỗi club
const localSat6 = (() => {
  const d = new Date(Date.UTC(nowLocal.getUTCFullYear(), nowLocal.getUTCMonth(), nowLocal.getUTCDate(), 6, 0, 0));
  const add = (6 - d.getUTCDay() + 7) % 7;
  d.setUTCDate(d.getUTCDate() + add);
  if (d.getTime() - TZ_OFFSET_MS <= now) d.setUTCDate(d.getUTCDate() + 7);
  return d.getTime() - TZ_OFFSET_MS;
})();
for (const c of clubs) {
  await upsert(
    db.collection("events").doc(`dev-event-${c.id.replace("dev-club-", "")}`),
    {
      clubId: c.id,
      title: "[DEV] Saturday easy run",
      description: "Development fixture event.",
      startsAt: localSat6,
      location: `${c.region} — meeting point (dev fixture)`,
      createdBy: OWNER_ID,
      cancelledAt: null,
      isDevFixture: true,
    },
    { goingCount: 0 },
  );
}

// ---- Challenges (cửa sổ = tháng hiện tại theo giờ VN; target theo đơn vị gốc: m / lần / ms)
const challenges = [
  { id: "dev-challenge-distance", title: "[DEV] Run 50 km this month", metric: "distance", target: 50_000, activityTypes: ["run", "indoorRun"] },
  { id: "dev-challenge-count", title: "[DEV] 12 activities this month", metric: "count", target: 12, activityTypes: ["run", "walk", "indoorRun"] },
  { id: "dev-challenge-time", title: "[DEV] 10 hours on your feet", metric: "time", target: 10 * 3600 * 1000, activityTypes: ["run", "walk"] },
];
for (const ch of challenges) {
  await upsert(
    db.collection("challenges").doc(ch.id),
    {
      title: ch.title,
      description: "Development fixture challenge.",
      metric: ch.metric,
      target: ch.target,
      startsAt: monthStartMs,
      endsAt: monthEndMs,
      activityTypes: ch.activityTypes,
      tzId: "Asia/Ho_Chi_Minh",
      startDate,
      endDate,
      badgeKey: "dev-badge",
      isDevFixture: true,
    },
    { participantCount: 0 },
  );
}

// ---- Routes (chỉ Admin SDK ghi)
const routes = [
  { id: "dev-route-riverside", name: "[DEV] Riverside loop", region: "Ho Chi Minh City", lat: 10.776, lon: 106.703, r: 0.01, surface: "road", distanceM: 6900 },
  { id: "dev-route-lake", name: "[DEV] Lake circuit", region: "Hanoi", lat: 21.028, lon: 105.852, r: 0.004, surface: "road", distanceM: 2800 },
  { id: "dev-route-hill", name: "[DEV] Hill trail", region: "Da Nang", lat: 16.1, lon: 108.27, r: 0.015, surface: "trail", distanceM: 10_300 },
];
for (const r of routes) {
  await db.collection("routes").doc(r.id).set(
    {
      name: r.name,
      nameLower: r.name.toLowerCase(),
      description: "Development fixture route.",
      region: r.region,
      distanceM: r.distanceM,
      surface: r.surface,
      polyline: encodePolyline(loop(r.lat, r.lon, r.r)),
      attribution: "Synthetic dev fixture geometry — not real map data",
      createdAt: now,
      isDevFixture: true,
    },
    { merge: true },
  );
}

console.info(`Seeded dev fixtures vào ${PROJECT_ID}: ${clubs.length} clubs, ${clubs.length} events, ${challenges.length} challenges, ${routes.length} routes.`);
