# ADR 0002 — Dùng chung base ASC (asc_common + dsp_base)

- Trạng thái: Đã áp dụng (2026-10-22), thay phần "Firebase/Auth" của ADR 0001 về phiên bản thư viện.
- Phạm vi: `mobile/` (STRIDE). Cùng base với app smart_drink (Aqua Mind).

## Bối cảnh
Các app của ASC Tech Soft dùng chung hai package: `asc_common` (UI primitives, localization XML, prefs, permission, device,
logging, flavor) và `dsp_base` (Firebase core/Analytics/Crashlytics/App Check/Remote Config + AdMob + consent). Mục tiêu: hai
project có cùng hạ tầng, cấu trúc build tự động và vòng đời khởi động để bảo trì một chỗ.

## Quyết định
| Hạng mục | Lựa chọn |
|---|---|
| Nguồn base | Git submodule: `asc_common/` (gốc repo) và `mobile/dsp_base/`; pubspec dùng `path`. Cùng commit với smart_drink. |
| State/Navigation | **Giữ Riverpod + go_router** (156 file hiện có, ADR 0001). Base dùng GetX như hạ tầng nội bộ: `Get.put` service, `.tr`. Không có `GetMaterialApp`. |
| Firebase | Hạ về họ 4.x để khớp `dsp_base` (`firebase_core ^4`, `firebase_auth ^6`, `cloud_firestore ^6`). Không sửa `dsp_base` để nâng 5.x vì sẽ lệch smart_drink. |
| permission_handler | `^13.0.2` (asc_common yêu cầu) → `compileSdk = 37`. |
| Quảng cáo | Chưa dùng. Không gọi `DspAdsController.start` (sẽ bật UMP/GDPR + AdMob). Manifest vẫn khai AdMob app ID (mặc định ID test) vì plugin crash khi thiếu. |
| Flavor | `alpha` (không quảng cáo), `dev`, `product`, `claude` — khớp `AscBuildFlavor`. Cùng `applicationId` nên một `google-services.json` dùng cho mọi flavor. |
| Build tự động | `mobile/build.py` + `mobile/tool/` (APK → Firebase App Distribution, Telegram/email). Secret chỉ từ biến môi trường. |
| Localization | `AscLocale` (XML kiểu Android, `lib/xml_strings/values*`) cấu hình sẵn; UI hiện còn chuỗi cứng, chuyển dần sang `.tr`. |

## Hệ quả
- `build_helper.py`/`translate.py` trong `dsp_base` chưa được commit lên remote của base (mới chỉ staged ở máy dev) nên được đặt
  trong `mobile/tool/` để repo tự đủ. Khi base commit chính thức thì cân nhắc dùng lại bản của base.
- Sửa base phải làm ở repo gốc của base rồi cập nhật con trỏ submodule ở cả hai app.
- `flutter run` bắt buộc `--flavor`.
- Đổi ngôn ngữ lúc chạy chưa cập nhật giao diện ngay (app Riverpod không có `GetMaterialApp` để rebuild): áp dụng ở lần mở sau.

## Rủi ro / việc còn lại
- Bản `product` cần AdMob app ID thật (`-PADMOB_APP_ID=...`) nếu bật quảng cáo, và khóa upload (`debug_keystore.properties` → `productKeyPath`) để ký phát hành.
- App Check cần đăng ký Play Integrity / debug token trong Firebase console trước khi bật enforce.
- iOS: chưa có `GoogleService-Info.plist` và chưa cấu hình scheme/flavor; Firebase bị bỏ qua trên iOS.
- Token Telegram và mật khẩu email từng nằm trong file build cũ của smart_drink/dsp_base: nên thu hồi và tạo lại.
