# STRIDE — đếm bước chân và chạy bộ

Monorepo gồm:

| Thư mục | Nội dung |
|---|---|
| `mobile/` | App Flutter (Android/iOS): đếm bước, ghi GPS, lịch sử, tiến độ, hồ sơ, Explore. Dữ liệu đám mây qua **Firebase Auth + Cloud Firestore** (không có server backend riêng) |
| _(git dependency)_ | `asc_common`, `dsp_base`: base dùng chung của ASC, khai trong `mobile/pubspec.yaml` (ghim theo commit), `flutter pub get` tự tải từ GitHub |
| `scripts/` | Script seed dữ liệu dev cho Firestore (`seed-firestore.mjs`, Admin SDK) |
| `firestore.rules`, `firestore.indexes.json`, `firebase.json` | Quy tắc bảo mật, index và cấu hình triển khai Firestore |
| `docs/` | ADR chọn stack, phạm vi + feature flag, schema Firestore, build, **checklist việc còn lại** |
| `*.docx`, `component_reference.png` | Tài liệu đặc tả và ảnh thiết kế gốc |

## Cài đặt nhanh

Yêu cầu: Flutter 3.47.x (Dart ≥ 3.13.3), Android SDK 37, Python 3 (build tự động), Firebase CLI (deploy rules/phân phối).

```bash
git clone https://github.com/asctechsoft/app-runing.git

cd mobile
flutter pub get
# android/app/google-services.json đã nằm trong repo (config client Firebase, project app-runing-667b3)
flutter run --flavor dev
```

Biến build mobile (`--dart-define`): `STRIDE_ENV` (dev|staging|production), `STRIDE_TILE_URL`, `STRIDE_TILE_FALLBACK_URL`, `STRIDE_TILE_ATTRIBUTION`.
Chi tiết flavor, build tự động, bản đồ: `docs/build.md`.

Firestore (lần đầu hoặc khi sửa rules/index): bật Cloud Firestore (Native mode) trong Firebase Console rồi
`firebase deploy --only firestore:rules,firestore:indexes --project app-runing-667b3`. Dữ liệu mẫu dev: `cd scripts && npm install && node seed-firestore.mjs`.

## Kiểm chứng

```bash
cd mobile && flutter analyze && flutter test
```

CI (`.github/workflows/ci.yml`) chạy các bước trên và build APK staging.

## Quy ước

- Nhánh chính `main` được bảo vệ; làm trên nhánh tính năng, PR theo `.github/pull_request_template.md`.
- Commit/PR ghi ID checklist (vd. `G03 G04: ...`) theo `STRIDE_Todo_Code_End_to_End.docx`.
- Không commit secret, khóa ký, service account, file `.env`.
- Quy ước code, cấu trúc thư mục, chuỗi đa ngôn ngữ: `CLAUDE.md`.

## Giới hạn hiện tại

Việc còn lại và những phần chưa kiểm chứng trên máy thật: `docs/checklist-con-lai.md`.
