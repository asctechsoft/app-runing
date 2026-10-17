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

## Trạng thái (cập nhật 2026-10-18)

Đã có code + test tự động (mobile 337 test, backend 59 test; analyze/lint/type-check sạch):
A01 A02 A05 (tài liệu), B01–B06, C01–C06, D01–D04, E01–E06, F01–F04, G01–G10, H01–H06, I01–I07, J01–J06, K01–K03, L01–L04, M01–M07, N01 (cơ bản), Q01–Q03 (phần tự động).

**Chưa kiểm chứng — bắt buộc trên máy thật trước G0/G2:**
- A03/F05: đếm bước foreground/background, reboot, đứng yên, sai lệch so với đếm tay.
- A04/G05/Q04: ghi GPS khi khóa màn hình, cuộc gọi, tiết kiệm pin, OS kill app; chất lượng lọc GPS và ngưỡng auto pause.
- L02: ghép nối cảm biến nhịp tim BLE thật.
- Dialog quyền hệ thống, thông báo nhắc, share sheet, image picker, TTS; iOS build (cần macOS).
- Đăng nhập/sync với backend staging thật (mới test bằng mock HTTP và test tích hợp backend riêng).

**Chưa làm / hoãn:**
- K04 giáo án (flag `workout.plans` tắt), Health Connect/HealthKit (flag `steps.health` tắt), Apple/Google sign-in (flag tắt).
- Backend: mailer production, S3 storage, rate limiter/job queue phân tán (Redis), chuyển PostgreSQL + sửa cursor sync đồng thời.
- UI club: duyệt yêu cầu, phân quyền, tạo sự kiện; danh sách route đã lưu; export toàn tài khoản từ màn chi tiết.
- Chuỗi UI qua localization key (J03): string hiện nằm trong code tiếng Anh, chưa tách ARB.
- N02/N03 (giám sát, backup), N04 (web admin, P2), Q05–Q07, R01–R05 (phát hành).
- Logo: đang dùng wordmark dựng lại từ mockup; cần asset logo đã duyệt.
