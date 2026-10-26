# ADR 0001 — Chọn stack STRIDE (A02, A05)

- Trạng thái: Đã chấp nhận (chủ sản phẩm chốt ngày 2026-10-17)
- Phạm vi: Toàn bộ P0 + P1 (xem [scope.md](../scope.md))

## Bối cảnh
Tài liệu nguồn yêu cầu: đếm bước nền, ghi GPS khi khóa màn hình, bản đồ, local database offline-first, auth, sync, và các module P1 (Explore, thiết bị, interval, live sharing). Máy dev hiện có Flutter 3.47.4 (Dart 3.13.3), Android SDK 37 (lúc chốt ADR là Flutter 3.38.9, Android SDK 36).

## Quyết định

| Lớp | Lựa chọn | Lý do |
|---|---|---|
| Mobile | Flutter (stable 3.38.x, Dart 3.10) | Một codebase Android/iOS; có plugin sensor/GPS/sqlite; toolchain đã cài. |
| State | flutter_riverpod 3 | DI + state, dễ thay fake repository trong test (C01). |
| Navigation | go_router 17 (`StatefulShellRoute`) | 5 tab giữ state riêng, deep link, route con. |
| Local DB | sqflite (+ sqflite_common_ffi cho test) | SQL tường minh, transaction, migration theo version. |
| GPS | geolocator 14 | Foreground service Android (notification), background mode iOS. |
| Bước chân | pedometer 4 (TYPE_STEP_COUNTER / CMPedometer) | Counter tích lũy; tự xử lý offset/reboot (F01). Health Connect/HealthKit là adapter bổ sung F02. |
| Bản đồ | flutter_map 8 + OpenStreetMap tiles | Không cần key khi dev; hiển thị attribution OSM bắt buộc. Production nên chuyển sang tile provider có SLA (xem Rủi ro). |
| Chart | fl_chart 1.x | Bar/line, tooltip. |
| Thông báo | flutter_local_notifications + timezone | Reminders theo local time (J02). |
| Audio cue | flutter_tts | Mốc km, chuyển phase interval (G07, K02). |
| Backend | **Không có server riêng.** App gọi thẳng Firebase: Cloud Firestore (dữ liệu đám mây) + quy tắc bảo mật `firestore.rules` | Chủ sản phẩm chốt 2026-10-19: bỏ backend Next.js/Prisma (đã xóa khỏi repo), giảm vận hành. Schema: `docs/firestore-schema.md`. |
| Auth | Firebase Auth: Google và Email/Password (project `app-runing-667b3`, Android `com.asc.app_runing`). Apple: **ẩn** (chưa có client ID). | Gửi mail xác minh/đặt lại mật khẩu do Firebase; không tự quản mật khẩu/JWT. |
| Object storage | Chưa dùng; ảnh đính kèm lưu cục bộ trên máy | Chọn nhà cung cấp khi có yêu cầu tải ảnh lên đám mây. |
| Push/crash | Chưa chọn; interface logger có redaction | Không đưa SDK chưa duyệt. |

Phiên bản khóa bằng `pubspec.lock` (mobile) trong repo; script seed dùng `scripts/package.json`. Cập nhật 2026-10-23: phiên bản Firebase/permission_handler theo base dùng chung — xem ADR 0002.

## Rủi ro
- **Tile OSM công cộng** có usage policy giới hạn, không dành cho app thương mại lưu lượng lớn → trước G5 phải chuyển sang provider trả phí (MapTiler/Stadia/Mapbox) hoặc tự host; URL tile để trong config môi trường.
- Ghi GPS nền và đếm bước nền **chưa được kiểm chứng trên máy thật** (A03, A04). G0 chưa qua cho đến khi có log thực địa.
- iOS không build được trên Windows; cần máy macOS/CI macOS.
- Máy dev có Kaspersky Endpoint Security cách ly `dart.exe` → cần thêm ngoại lệ cho Flutter SDK và Pub cache.
- **Firestore không có rate limit phía server như backend cũ** → cần App Check, budget alert và giám sát số lượt đọc/ghi; quy tắc bảo mật (`firestore.rules`) là lớp bảo vệ duy nhất nên phải có test bằng Emulator.
- Logic từng nằm ở server (kiểm tra revision, cursor đồng bộ, xuất/xóa tài khoản) nay chạy ở client: lỗi client = lỗi dữ liệu, cần test kỹ phần đồng bộ.

## Phương án thay thế đã cân nhắc
- React Native (Expo): cần thêm toolchain; background location qua expo-task-manager. Không chọn vì Flutter đã sẵn.
- Native Kotlin + Swift: chi phí gấp đôi.
- Backend riêng Next.js + Prisma + PostgreSQL: đã làm rồi bỏ (2026-10-19) vì tốn vận hành; mã nguồn xem lịch sử git (commit trước khi xóa backend).
- Supabase: tương tự Firebase; không chọn vì base chung của ASC đã dựa trên Firebase.
