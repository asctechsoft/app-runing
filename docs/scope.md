# Phạm vi phát hành STRIDE (A01)

Chủ sản phẩm chốt 2026-10-17: thi công **P0 + P1**. Nền tảng: Android trước (build được trên Windows), iOS cùng codebase nhưng cần macOS để build/kiểm thử. Ngôn ngữ khởi đầu: English (UI mẫu), string qua localization; tiếng Việt bổ sung sau. Môi trường: dev / staging / production.

## Module và feature flag

| Module | Mức | Flag | Mặc định dev | Ghi chú |
|---|---|---|---|---|
| Onboarding, guest, profile setup, goals | P0 | — | bật | |
| Auth email/password + reset | P0 | `auth.email` | bật | Cần backend. |
| Sign in with Apple / Google | P0 | `auth.apple`, `auth.google` | **tắt (ẩn)** | Chưa có client ID. |
| Daily steps (sensor) | P0 | — | bật | |
| Health Connect / HealthKit import | P0 | `steps.health` | tắt | Cần spike F02 trên máy thật. |
| Run engine GPS, pause/lock/finish, recovery | P0 | — | bật | |
| History, detail, edit/delete, progress, records | P0 | — | bật | |
| Share image (hide start/finish) | P0 | — | bật | |
| Export CSV/GPX | P0 | — | bật | |
| Sync + outbox | P0 | `sync` | bật khi đăng nhập | |
| Reminders + notification inbox | P0 | `notifications.inbox` | bật | Nếu inbox tắt thì ẩn chuông. |
| Interval workouts | P1 | `workout.intervals` | bật | |
| Training plans | P1 | `workout.plans` | tắt | Cần nội dung giáo án được duyệt. |
| Devices (BLE heart rate) | P1 | `devices.ble` | bật | Chỉ cảm biến chuẩn BLE Heart Rate Service 0x180D. Không liệt kê tên đồng hồ cụ thể. |
| Indoor run | P1 | `run.indoor` | bật | Không vẽ GPS; quãng đường từ bước có nhãn estimated. |
| Explore: clubs, feed, events | P1 | `explore.clubs` | bật | Cần backend. |
| Challenges | P1 | `explore.challenges` | bật | Cần backend. |
| Discover routes | P1 | `explore.routes` | bật | Cần backend. |
| Live sharing | P1 | `live.sharing` | bật | Cần backend; mặc định tắt cho từng run. |
| Web admin | P2 | — | ngoài phạm vi đợt này | |

Mọi nút gắn với flag tắt phải **ẩn**, không hiển thị disabled giả.

## Quyết định còn mở
- Tile provider production và ngân sách (ADR 0001 · Rủi ro).
- Công thức calo: dùng MET theo pace × weight × giờ (`calorie_model = "met-v1"`), cần Product duyệt.
- Tiêu chí record: chỉ công nhận toàn buổi có distance ≥ mốc; fastest 1 km/5 km từ split nội suy trong segment liên tục (không qua gap/pause).
- Chính sách giữ dữ liệu sau xóa tài khoản (đề xuất: xóa cứng trong 30 ngày).
- Danh sách thiết bị test thật (A03/A04/Q04).
