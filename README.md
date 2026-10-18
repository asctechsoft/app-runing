# STRIDE — đếm bước chân và chạy bộ

Monorepo gồm:

| Thư mục | Nội dung |
|---|---|
| `mobile/` | App Flutter (Android/iOS): đếm bước, ghi GPS, lịch sử, tiến độ, hồ sơ, Explore |
| `backend/` | API Next.js 15 + Prisma (SQLite khi dev/test, PostgreSQL production) — xem `backend/README.md` |
| `docs/` | ADR chọn stack, phạm vi + feature flag, domain model |
| `*.docx`, `sceam/`, `component_reference.png` | Tài liệu đặc tả và ảnh thiết kế gốc |

## Cài đặt nhanh

Yêu cầu: Flutter 3.38.x (Dart 3.10), Android SDK, Node 22.

```bash
# Backend (cổng 3001)
cd backend
npm ci
cp .env.example .env          # sửa JWT_SECRET
npx prisma migrate dev
npm run seed                  # dữ liệu mẫu chỉ cho dev
npm run dev

# Mobile
cd mobile
flutter pub get
flutter run                   # mặc định STRIDE_ENV=dev, API http://10.0.2.2:3001/api/v1 (Android emulator)
```

Biến build mobile (`--dart-define`): `STRIDE_ENV` (dev|staging|production), `STRIDE_API_URL`, `STRIDE_TILE_URL`, `STRIDE_TILE_ATTRIBUTION`.

## Kiểm chứng

```bash
cd mobile  && flutter analyze && flutter test
cd backend && npm run lint && npx tsc --noEmit && npm test
```

CI (`.github/workflows/ci.yml`) chạy các bước trên và build APK staging.

## Quy ước

- Nhánh chính `main` được bảo vệ; làm trên nhánh tính năng, PR theo `.github/pull_request_template.md`.
- Commit/PR ghi ID checklist (vd. `G03 G04: ...`) theo `STRIDE_Todo_Code_End_to_End.docx`.
- Không commit secret, `.env`, DB local.

## Giới hạn hiện tại

Xem mục "Trạng thái" trong `docs/scope.md`: các hạng mục cần máy thật (ghi GPS nền, đếm bước thực địa, BLE) chưa được kiểm chứng.
