# ADR 0001 — Chọn stack STRIDE (A02, A05)

- Trạng thái: Đã chấp nhận (chủ sản phẩm chốt ngày 2026-10-17)
- Phạm vi: Toàn bộ P0 + P1 (xem [scope.md](../scope.md))

## Bối cảnh
Tài liệu nguồn yêu cầu: đếm bước nền, ghi GPS khi khóa màn hình, bản đồ, local database offline-first, auth, sync, và các module P1 (Explore, thiết bị, interval, live sharing). Máy dev hiện có Flutter 3.38.9 (Dart 3.10.8), Android SDK 36, Node 22; chưa có PostgreSQL/Docker.

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
| Backend | Next.js 15 (route handlers) + Prisma + PostgreSQL | Khớp bộ agent BE/Prisma sẵn có. Local/test dùng SQLite qua cùng schema Prisma; production đổi `provider = "postgresql"`. |
| Auth | Email/password tự quản (argon2/bcrypt + JWT access ngắn + refresh token xoay vòng). Apple/Google: interface có sẵn, **ẩn** cho tới khi có client ID. | Không có tài khoản provider lúc này; không ship nút giả. |
| Object storage | Interface `StorageDriver`; local disk cho dev, S3-compatible cho production | Chưa chọn nhà cung cấp. |
| Push/crash | Chưa chọn; interface logger có redaction | Không đưa SDK chưa duyệt. |

Phiên bản khóa bằng `pubspec.lock` và `package-lock.json` trong repo.

## Rủi ro
- **Tile OSM công cộng** có usage policy giới hạn, không dành cho app thương mại lưu lượng lớn → trước G5 phải chuyển sang provider trả phí (MapTiler/Stadia/Mapbox) hoặc tự host; URL tile để trong config môi trường.
- Ghi GPS nền và đếm bước nền **chưa được kiểm chứng trên máy thật** (A03, A04). G0 chưa qua cho đến khi có log thực địa.
- iOS không build được trên Windows; cần máy macOS/CI macOS.
- Máy dev có Kaspersky Endpoint Security cách ly `dart.exe` → cần thêm ngoại lệ cho Flutter SDK và Pub cache.
- SQLite local khác PostgreSQL ở một số kiểu (JSON, enum); schema Prisma tránh tính năng riêng của từng DB.

## Phương án thay thế đã cân nhắc
- React Native (Expo): cần thêm toolchain; background location qua expo-task-manager. Không chọn vì Flutter đã sẵn.
- Native Kotlin + Swift: chi phí gấp đôi.
- Supabase/Firebase: nhanh nhưng cần project/key bên ngoài; giữ làm phương án nếu đội backend thiếu người.
