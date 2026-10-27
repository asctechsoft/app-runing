# STRIDE mobile

App Flutter (Android/iOS) đếm bước và ghi buổi chạy. Dữ liệu cục bộ là SQLite (offline-first), đồng bộ lên Firebase Auth + Cloud
Firestore; không có server backend riêng. Tổng quan monorepo: [`../README.md`](../README.md).

## Yêu cầu

- Flutter **3.47.x** (Dart ≥ 3.13.3). Kiểm tra: `flutter --version`.
- Android SDK 37. Python 3 nếu dùng build tự động (`build.py`).
- Submodule `dsp_base/` (và `../asc_common/`): `git submodule update --init --recursive`.
- `android/app/google-services.json` lấy từ Firebase Console (project `app-runing-667b3`). **Không commit.**

## Chạy app

Flavor là bắt buộc (`alpha | dev | product | claude`):

```bash
flutter pub get
flutter run --flavor dev
```

VS Code có sẵn cấu hình chạy theo flavor ở `../.vscode/launch.json`.

Biến build (`--dart-define`): `STRIDE_ENV` (dev | staging | production), `STRIDE_TILE_URL`, `STRIDE_TILE_FALLBACK_URL`,
`STRIDE_TILE_ATTRIBUTION`, `STRIDE_TILE_MAX_ZOOM`. Chi tiết flavor, build tự động, bản đồ, secret: [`../docs/build.md`](../docs/build.md).

## Kiểm tra trước khi tạo PR

```bash
flutter analyze
flutter test
# format bằng Dart của Flutter (không dùng dart cũ trong PATH)
<flutter-sdk>/bin/cache/dart-sdk/bin/dart format -l 160 lib test
```

Chạy một file test: `flutter test test/run/run_engine_test.dart`; lọc theo tên: thêm `--plain-name "<tên test>"`.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `lib/presentation/` | Màn hình và widget dùng chung |
| `lib/controller/` | State và logic (Riverpod); `run/engine/` là engine ghi buổi chạy |
| `lib/repository/` | Truy cập dữ liệu (SQLite + Firestore) |
| `lib/services/` | Hạ tầng: khởi động, đồng bộ, đếm bước, quyền, database |
| `lib/utils/calc/` | Tính toán thuần (calo, GPS, kỷ lục…) |
| `lib/xml_strings/` | Chuỗi giao diện en/vi (`'key'.tr`) |
| `test/` | Test tự động (DB in-memory, fixture GPS/bước) |

Quy ước chi tiết (chuỗi đa ngôn ngữ, tầng thư mục, luồng dữ liệu): [`../CLAUDE.md`](../CLAUDE.md).

## Tài liệu

- Việc còn lại: [`../docs/checklist-con-lai.md`](../docs/checklist-con-lai.md)
- Quyết định kỹ thuật: [`../docs/adr/`](../docs/adr/)
- Schema Firestore: [`../docs/firestore-schema.md`](../docs/firestore-schema.md)
- Phạm vi và feature flag: [`../docs/scope.md`](../docs/scope.md)
