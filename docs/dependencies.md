# Phụ thuộc bị ghim và quy trình nâng (X06)

STRIDE dùng chung base với các app ASC (`mobile/dsp_base`, `asc_common` — ADR 0002). Các gói dưới đây phải cùng **họ phiên bản**
với base; Dependabot (`.github/dependabot.yml`) bỏ qua bản major của chúng.

| Gói | Ràng buộc hiện tại | Vì sao ghim | Nâng khi |
|---|---|---|---|
| `firebase_core` | `^4.0.0` | `dsp_base` dùng `firebase_core ^4` (Analytics, App Check, Crashlytics, Remote Config) | `dsp_base` nâng họ Firebase |
| `firebase_auth` | `^6.0.0` | cùng họ BoM với `firebase_core ^4` | như trên |
| `cloud_firestore` | `^6.0.0` | cùng họ BoM với `firebase_core ^4` | như trên |
| `fake_cloud_firestore` (dev) | `^4.4.0` | bản 4.x đi với `cloud_firestore` 6.x; chỉ dùng trong test | nâng cùng lúc với `cloud_firestore` |
| `permission_handler` | `^13.0.2` | `asc_common` khai `^13.0.2` | `asc_common` nâng |
| `get` | `^4.7.2` | hạ tầng của base (`Get.put`, `.tr`) | base nâng |

Gói nền của STRIDE (đổi cần cập nhật ADR 0001): Flutter 3.47.x, `flutter_riverpod`, `go_router`, `sqflite`, `flutter_map`.

## Quy trình nâng base
1. Sửa ở repo gốc của `dsp_base` / `asc_common`, chạy test của **mọi app** dùng base (STRIDE, smart_drink).
2. Cập nhật con trỏ submodule ở **cả hai app** cùng lúc.
3. Ở STRIDE: nâng ràng buộc trong `mobile/pubspec.yaml`, `flutter pub get`, `flutter analyze`, `flutter test`, build `alpha` thử.
4. Định kỳ hằng tháng: `flutter pub outdated` trong `mobile/` để xem gói có bản mới.
