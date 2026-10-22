# CLAUDE.md — STRIDE (app đếm bước chân và chạy bộ)

Repo hiện chỉ chứa tài liệu đặc tả và ảnh UI; **chưa có source code, build hay test**. Khi bắt đầu viết code, cập nhật mục "Lệnh" bên dưới.

## Tài liệu nguồn (đọc trước khi làm)
- `Full_luong_app_dem_buoc_chan_chay_bo.docx` — kịch bản nghiệp vụ, luồng người dùng, yêu cầu chức năng (v1.0).
- `STRIDE_Design_System_v1.docx` — màu, typography, spacing, component, hành vi UI (token HEX/font là baseline).
- `STRIDE_Todo_Code_End_to_End.docx` — checklist triển khai (ID A01…, mức P0/P1/P2, mốc G0–G5).
- `component_reference.png`, `sceam/*.png` — ảnh tham chiếu giao diện (splash, home, progress, history, settings, map). Ảnh render không phải nguồn số đo; số đo lấy từ Design System.

## Nguyên tắc sản phẩm (bắt buộc)
- Đếm bước hằng ngày và ghi buổi chạy là hai nghiệp vụ riêng.
- Chỉ ghi GPS khi người dùng chủ động bắt đầu hoạt động; không theo dõi vị trí cả ngày.
- Hoạt động mặc định riêng tư. Một người chỉ có một phiên đang ghi trên một thiết bị.
- Không giả lập dữ liệu thiếu; calo và quãng đường suy từ bước ghi rõ là "estimated". Pace thiếu dữ liệu hiển thị `—`.
- Không ship nút giả, không tự báo thành công khi chưa có xác nhận. Mọi màn cần empty/loading/error/permission state.
- Hoạt động offline-first: vào app và lưu hoạt động được khi không có mạng.

## Quy ước UI (từ Design System)
- Light theme; màn khóa khi chạy dùng nền tối riêng. Font Inter (fallback font hệ thống theo script).
- Màu chính `#137A4B`, lime `#D6F45B`, canvas `#F8FAF8`, navy logo `#102134`. Luôn dùng token, không hard-code HEX.
- Sentence case; tên tab: Home, Progress, Run, History, Profile. Body tối thiểu 16.
- Số dùng tabular numerals; lưu đơn vị gốc, đổi hiển thị theo cài đặt (km/mi).
- Logo: không kéo giãn/xoay/đổi màu; vùng an toàn tối thiểu 16%. Logo chính thức `mobile/assets/images/img_logo.png` (dùng qua `StrideLogo`/`strideLogoAsset`); icon launcher sinh từ `mobile/tool/icons/img_logo_launcher.png` (nền navy `#0A2038` phủ vuông, không bo góc) bằng `dart run flutter_launcher_icons` — đổi logo thì thay hai file này rồi chạy lại.

## Stack
Đã chốt trong `docs/adr/0001-stack.md` (Flutter + Riverpod/go_router + Next.js/Prisma + OSM) và `docs/adr/0002-shared-base.md` (dùng chung base ASC). Không tự đổi framework hay nâng/hạ phiên bản thư viện nền mà không cập nhật ADR.

## Base dùng chung với các app ASC (smart_drink...)
- `asc_common/` (submodule ở gốc repo) và `mobile/dsp_base/` (submodule) cùng commit với smart_drink. **Không sửa trong repo này** — sửa ở repo gốc của base rồi cập nhật con trỏ submodule. Clone mới: `git submodule update --init --recursive`.
- Phiên bản Firebase (`firebase_core ^4`, `firebase_auth ^6`, `cloud_firestore ^6`) và `permission_handler ^13` phải khớp họ phiên bản của `dsp_base`/`asc_common`; đừng nâng riêng lẻ.
- STRIDE giữ Riverpod + go_router; GetX chỉ là hạ tầng của base (`Get.put` service, `.tr` cho chuỗi XML). Không viết màn hình/state mới bằng GetX.
- Khởi động: `lib/main.dart` → `services/application/stride_base.dart` (Firebase, App Check, Crashlytics, Remote Config chạy nền). Chưa có quảng cáo: không gọi `DspAdsController.start` khi chưa có quyết định sản phẩm. Vòng đời: `services/application/app_lifecycle.dart`. Analytics: `utils/analytics.dart`, `utils/route_analytics.dart` (không đưa id/tọa độ vào event).
- Flavor `alpha | dev | product | claude` (bắt buộc truyền `--flavor`); cờ trong code: `configs/app_figs.dart`. Build tự động, secret và AdMob: `docs/build.md`.

## Chuỗi giao diện (đa ngôn ngữ) — bắt buộc
- **Không viết chữ cứng** trong widget/logic/model/repository nếu người dùng có thể nhìn thấy. Thêm key vào CẢ HAI file
  `mobile/lib/xml_strings/values/strings.xml` (en) và `values-vi/strings.xml` (vi), rồi gọi `'key'.tr` hoặc `'key'.trArgs([a, b])`
  (`import '.../utils/l10n.dart'`, không import `package:get/get.dart` trực tiếp). Placeholder trong XML dùng `%1$s`, `%2$s`.
- Tên key: snake_case, tiền tố theo màn/khu vực (`run_`, `profile_`, `explore_`, `activity_`, `progress_`, `history_`, `steps_`, `goals_`, `account_`, `auth_`,
  `setup_`, `home_`, `workout_`, `devices_`, `live_`, `reminders_`, `model_`, `common_`...). Đặt theo ý nghĩa, không theo nguyên văn.
- Không gọi `.tr` ở khởi tạo tĩnh (`const`/`static final`): lưu key rồi `.tr` ở nơi hiển thị. `.tr` không phải `const` nên bỏ `const` của widget bao quanh.
- Không đưa vào XML: log, lỗi lập trình nội bộ, tên field/collection, route, tên event analytics, mẫu `DateFormat`. Tên thương hiệu `STRIDE` giữ nguyên.
- Ngày giờ: `DateFormat(pattern, appDateLocale)` (`utils/date_locale.dart`), không ghi cứng `'en_US'`.
- `test/core/strings_xml_test.dart` kiểm tra en/vi đủ key, placeholder khớp, mọi key dùng trong code đều tồn tại — chạy `flutter test` sau khi thêm chuỗi.
- Hạn chế đã biết: đổi ngôn ngữ lúc chạy chưa làm UI cập nhật ngay (app Riverpod, không có `GetMaterialApp`) — áp dụng ở lần mở sau; giọng đọc TTS (chạy bộ, thử giọng) vẫn đặt `en-US`.

## Cấu trúc `mobile/lib` (cùng bố cục với smart_drink)
```
main.dart
configs/        env, app_figs, pref_const, locale_config
values/         theme + design tokens (stride_theme, tokens), routes, router (go_router)
utils/          analytics, route_analytics, logger, formatters, clock, activity_format, progress_data, route_geometry; utils/calc/ (tính toán thuần: calo, geo, gps_filter, records...)
models/         data_models/ (activity, profile, steps, sync, session_state), ui_models/ (period, explore_models, live_share_models, workout_models)
repository/     *_repository.dart (truy cập dữ liệu: SQLite + Firestore)
services/       application/ (stride_base, app_lifecycle, sync_service, step_tracking_service, plugin/scheduler/export...), native/ (permission), storage/ (app_database)
controller/     providers.dart, run_plugins.dart, <feature>/ (Riverpod providers, *_logic, controller; run/engine = engine ghi chạy)
presentation/   common_components/ (widget dùng chung), screen_shell/ (AppShell 5 tab), screen_<feature>/ hoặc screens_<feature>/ (+ components/)
xml_strings/    values*/strings.xml (AscLocale)
```
Quy ước: màn hình chỉ ở `presentation/`, truy cập dữ liệu qua `repository/`, logic/state qua `controller/` (Riverpod, không phải GetX controller), hạ tầng ở `services/`. File mới đặt đúng tầng theo bảng này.

## Lệnh
- Mobile (`mobile/`): `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run --flavor dev`, build tự động `python build.py` (xem `docs/build.md`).
- Format: dùng Dart **của Flutter**, không dùng `dart` trong PATH nếu nó là SDK cũ (`dart --version` phải ≥ 3.13): `flutter/bin/cache/dart-sdk/bin/dart format -l 160 lib test`. Dart cũ format sai kiểu và đổi hàng loạt file.
- Backend (`backend/`): `npm ci`, `npm run dev` (cổng 3001), `npm run lint`, `npx tsc --noEmit`, `npm test`, `npx prisma migrate dev`, `npm run seed` (chỉ dev).
- Máy dev có Kaspersky từng cách ly `dart.exe`: nếu `dart.exe is not recognized`, xóa `flutter/bin/cache/engine-dart-sdk.stamp` rồi chạy `flutter --version`; nếu `pub get` thất bại trong sandbox, đặt `PUB_CACHE` sang thư mục ghi được.

## Harness / cách làm việc với Claude
- Tài liệu và UI viết tiếng Việt; trả lời và comment nghiệp vụ bằng tiếng Việt, tên code/identifier bằng tiếng Anh.
- Trước khi sửa, đọc file liên quan; thay đổi nhỏ, đúng phạm vi yêu cầu, không refactor ngoài ý muốn.
- Mỗi việc xong cần có kiểm chứng (test hoặc chạy thật) và ghi theo ID checklist (vd. A03) trong commit/PR.
- Không commit secret, key, file `.env`; ảnh/tài liệu lớn nên cân nhắc Git LFS (nhiều ảnh trong `sceam/` >6 MB).
- Hành động khó hoàn tác (push, xóa, force) phải hỏi trước. Remote: `https://github.com/asctechsoft/app-runing.git`, nhánh `main`.
