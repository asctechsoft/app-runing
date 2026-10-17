# STRIDE backend

API cho app STRIDE (đếm bước + ghi buổi chạy). Next.js 15 App Router (chỉ route handler, không UI), TypeScript strict,
Prisma, zod, bcryptjs, jose, vitest. Stack theo [ADR 0001](../docs/adr/0001-stack.md); domain theo
[domain-model.md](../docs/domain-model.md).

## Cài đặt (B06)

Yêu cầu: Node 22, npm.

```bash
cd backend
npm ci
cp .env.example .env          # rồi đặt JWT_SECRET (>= 32 ký tự ngẫu nhiên)
npx prisma migrate dev        # tạo prisma/dev.db (SQLite) + Prisma Client
npm run seed                  # (tùy chọn) dữ liệu mẫu DEV: clubs, challenges, routes
npm run dev                   # http://localhost:3001/api/health
```

npm 12 chặn install script mặc định; `package.json#allowScripts` đã cho phép đúng các gói cần thiết
(`prisma`, `@prisma/client`, `@prisma/engines`, `esbuild`).

## Lệnh

| Việc | Lệnh |
|---|---|
| Chạy dev | `npm run dev` (port 3001) |
| Test | `npm test` (vitest, mỗi file test dùng một SQLite tạm trong `.tmp-test/`) |
| Lint | `npm run lint` |
| Type-check | `npx tsc --noEmit` |
| Migration dev | `npx prisma migrate dev` |
| Migration deploy | `npm run migrate:deploy` |
| Seed (chỉ dev) | `npm run seed` |
| Chạy job thủ công | `npm run jobs` (khi `JOB_RUNNER=manual`) |

## Cấu hình (.env)

Xem `.env.example`. Không commit `.env`. Biến chính: `DATABASE_URL`, `JWT_SECRET`, `PUBLIC_BASE_URL` (dựng URL ký số
upload/download), `APP_LINK_BASE` (link trong email), `STORAGE_DIR`, `MAILER_DRIVER` (`console` | `memory`),
`JOB_RUNNER` (`inline` | `manual`), `RATE_LIMIT_AUTH_PER_MIN`, `RATE_LIMIT_SOCIAL_PER_MIN`, `BCRYPT_ROUNDS` (mặc định 12).

## Đổi sang PostgreSQL

Schema tránh tính năng riêng của từng DB: không dùng Prisma enum (enum lưu `String`, validate bằng zod), JSON lưu
`String` (cột `*Json`), tìm kiếm dùng cột chữ thường (`searchText`, `regionLower`) thay vì `mode: insensitive`.

1. `prisma/schema.prisma`: đổi `provider = "sqlite"` thành `provider = "postgresql"`.
2. `.env`: `DATABASE_URL="postgresql://user:pass@host:5432/stride?schema=public"`.
3. Migration hiện có là SQL của SQLite (`migration_lock.toml` ghi provider). Với DB Postgres mới: xóa
   `prisma/migrations/` (hoặc giữ ở nhánh riêng) rồi chạy `npx prisma migrate dev --name init` để sinh migration
   Postgres; commit migration đó; production chạy `npm run migrate:deploy`.
4. Chạy lại `npm test` với một Postgres test (đặt `DATABASE_URL` tương ứng và chỉnh `tests/global-setup.ts`,
   hiện đang copy file SQLite mẫu).

Lưu ý: `ChangeLog.seq` (cursor sync) là autoincrement. Trên Postgres, các transaction chạy song song có thể commit
seq không theo thứ tự; trước production cần thêm "watermark" (chỉ trả seq nhỏ hơn transaction đang mở nhỏ nhất)
hoặc khóa theo user khi ghi ChangeLog.

## Kiến trúc

```
app/api/health/route.ts           health check (B06)
app/api/v1/**/route.ts            controller mỏng: parse request -> service -> json
src/server/http/handler.ts        wrapper: auth, error envelope, Idempotency-Key, giới hạn body, header an toàn
src/server/services/*.ts          nghiệp vụ
src/server/repositories/*.ts      nơi duy nhất gọi Prisma; owner-scope.ts ép điều kiện ownerId (H01)
src/server/validators/*.ts        zod schema cho mọi input
src/lib/                          prisma singleton, storage driver, mailer, rate limiter, redact/logger, token ký số
prisma/schema.prisma, migrations/ schema + migration
prisma/seed.ts                    dữ liệu mẫu DEV (bị chặn khi NODE_ENV=production)
openapi.yaml, fixtures/           hợp đồng API (C06) + JSON mẫu dùng chung với mobile
tests/                            vitest gọi trực tiếp route handler thật
```

## Hợp đồng API (C06)

- `openapi.yaml` (OpenAPI 3.1), mọi endpoint dưới `/api/v1` (trừ `/api/health`).
- Lỗi: `{ "error": { "code", "message", "details"? } }`. Danh sách: `{ "items", "nextCursor" }`.
- Endpoint thay đổi dữ liệu nhận `Idempotency-Key`; bản ghi lưu theo user (key + hash request + response + hash response).
- Tài nguyên không thuộc người gọi luôn trả **404** (kể cả id thật), không phải 403.
- `fixtures/*.json`: mẫu request/response; `tests/fixtures.test.ts` kiểm tra fixture request khớp schema server.

## Checklist đã làm

| ID | Nội dung | Ghi chú |
|---|---|---|
| B06 | Skeleton API, Prisma migration, `GET /api/health`, `StorageDriver` + local disk (`storage/`, gitignore), `.env.example`, README | |
| C06 | OpenAPI 3.1, fixtures, `/api/v1`, error envelope, cursor pagination, Idempotency-Key | |
| E02 | Đăng ký (mật khẩu ≥ 8, có chữ + số), xác minh email (Mailer console/memory), đăng nhập, refresh xoay vòng + phát hiện reuse (thu hồi cả family), logout, quên/đặt lại mật khẩu (phản hồi chung), reauth, rate limit (in-memory, interface `RateLimiter`) | Apple/Google: chỉ có interface `src/server/auth/providers.ts`, **không** có route |
| E03 | `POST /me/claim-guest` giữ chỗ id hoạt động guest; idempotent; không bao giờ gắn dữ liệu của người khác | |
| Me | Profile/settings với `expectedRevision` (409 + bản server), GoalVersion append-only theo `effectiveFrom`, source priorities | |
| H01 | Mọi truy vấn dữ liệu người dùng qua `ownerScope`; test A không đọc/sửa/xóa được activity/track/attachment của B (id thật + id đoán => 404) | |
| H02 | Upsert activity theo id client, PATCH với revision, DELETE => tombstone; track chunk có sha256, re-upload idempotent, finalize kiểm tra 0..n-1, tải track | |
| H03/H04 | `POST /sync/push` (ack/reject/conflict từng op, idempotencyKey), `GET /sync/pull?cursor=` (seq đơn điệu, gồm tombstone) | Xem lưu ý Postgres ở trên |
| H05 | Ảnh đính kèm: kiểm mime (jpeg/png/heic/webp) + magic bytes, ≤ 10 MB, URL upload/download ký số ngắn hạn, chỉ chủ sở hữu | |
| H06 | Export (zip JSON + CSV + GPX, hạn 7 ngày) và xóa tài khoản (cần reauth ≤ 5 phút, job xóa dữ liệu, trạng thái chỉ `succeeded` khi xong) | Job chạy trong process (`JOB_RUNNER=inline`) hoặc `npm run jobs` |
| I07 (server) | GPX chỉ từ GPS thật: một `<trkseg>` mỗi segment, chỉ point accepted, không lấp khoảng trống | |
| J04 | Mặc định `onlyMe`; người khác chỉ xem khi privacy cho phép + cùng club đã duyệt + không chặn nhau; không lộ tọa độ đầu/cuối trừ khi `shareRoute` | |
| M01–M07 | Clubs (tìm theo text/khu vực/lat-lon box, tham gia không trùng, duyệt/từ chối, vai trò, rời), feed (post theo privacy, comment, cheer, xóa bài mình, report, block hai chiều, rate limit theo user), sự kiện (owner/mod tạo, tzId, nơi tập trung do người tổ chức nhập, RSVP), challenges (tiến độ tính ở server theo tz challenge, tính lại khi sửa/xóa, không cộng trùng, huy hiệu, leaderboard opt-in), routes (tìm, polyline + attribution, lưu), live sharing (viewer chỉ định, TTL, dừng khi hoạt động kết thúc, 404 sau hết hạn) | |
| Notifications | Inbox: danh sách, đánh dấu đã đọc | |
| N01 (cơ bản) | zod cho mọi input, giới hạn body/upload, `redact()` cho log (token, mật khẩu, lat/lon), header an toàn | |

## Giới hạn / chưa làm

- Rate limiter và job runner chạy trong bộ nhớ một process: chạy nhiều instance cần Redis/queue (interface đã tách).
- `ConsoleMailer` ở production không gửi email (chỉ cảnh báo); cần driver SMTP/nhà cung cấp trước khi phát hành.
- Storage chỉ có local disk; driver S3-compatible chưa làm (chưa chọn nhà cung cấp).
- Challenge/route chỉ đến từ seed DEV hoặc DB; chưa có API quản trị (web admin là P2).
- Club bị xóa cùng chủ sở hữu khi xóa tài khoản; chưa có chuyển quyền sở hữu.
- Chính sách giữ dữ liệu sau xóa tài khoản (đề xuất 30 ngày ở scope.md) chưa chốt: hiện xóa cứng ngay khi job chạy.
