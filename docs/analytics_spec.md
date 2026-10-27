# Đặc tả analytics (Q06)

Nguồn sự thật: `mobile/lib/utils/analytics.dart` (cổng duy nhất), `mobile/lib/utils/route_analytics.dart` (screen_view tự động).
Sink: Firebase Analytics qua `dsp_base` (`DspAnalytics`); không có Firebase → no-op (offline-first).

## Quy tắc
- **Không** đưa vào tên/tham số: id người dùng/hoạt động/câu lạc bộ, email, tọa độ, nội dung người dùng nhập.
- Tên event: 1–40 ký tự, `^[A-Za-z][A-Za-z0-9_]*$`, không bắt đầu `firebase_`/`google_`/`ga_`, không trùng tên dành riêng
  (danh sách `_reservedNames` trong `analytics.dart`; ví dụ `app_background` từng bị từ chối → dùng `stride_background`).
- Tham số chỉ là **chuỗi** (GA4 custom dimension bỏ qua số) — `_log` có `assert`.
- Thêm event mới: thêm hàm trong `Analytics`, cập nhật bảng dưới, kiểm trên DebugView (`adb shell setprop debug.firebase.analytics.app <applicationId>`).

## Danh sách event

| Event | Tham số | Khi nào | Nơi gọi | Mục đích |
|---|---|---|---|---|
| `app_open` | `first_open`: `true`/`false` | Mở app lạnh, tại splash | `StartupScreen` | Tỷ lệ mở lần đầu / quay lại |
| `stride_foreground` | — | App quay lại foreground | `AppLifecycle` | Phiên sử dụng |
| `stride_background` | — | App xuống background | `AppLifecycle` | Phiên sử dụng |
| `screen_view` | `firebase_screen`: **mẫu** đường dẫn (`/home/activity/:id`) | Mỗi lần đổi route, kể cả đổi tab | `RouteAnalytics` | Phễu màn hình; không rò id |
| `language_screen_view` | `source`: `first_run` \| `settings` | Mở màn chọn ngôn ngữ | `LanguageSelectionScreen` | Tỷ lệ người dùng thấy màn ngôn ngữ |
| `language_select` | `code`: `vi_VN`… hoặc `system`; `source`: `first_run` \| `settings` \| `system_default` | Chọn ngôn ngữ | `LanguageSelectionScreen` | Ngôn ngữ ưu tiên, quyết định thứ tự dịch (L01) |
| `club_create` | `visibility`: `public` \| `private` | Tạo club thành công | `CreateClubScreen` | Mức dùng tính năng nhóm (TM01) |
| `club_invite_share` | — | Bấm "Gửi lời mời" (mở bảng chia sẻ mã) | `ClubDetailScreen` | Đầu phễu *mời → vào nhóm* (TM03) |
| `club_join` | `via`: `public` \| `request` \| `invite_code` | Vào club / gửi yêu cầu thành công | `ClubsScreen`, `ClubDetailScreen` | Cuối phễu mời; tỷ lệ vào bằng mã |
| `challenge_join` | `metric`: `distance` \| `count` \| `time` | Tham gia thử thách thành công | `ChallengeDetailScreen` | Loại thử thách được quan tâm |
| `leaderboard_view` | — | Mở bảng xếp hạng thử thách | `ChallengeLeaderboardScreen` | Mức quan tâm bảng xếp hạng (TM30) |
| `streak_milestone` | `days`: `3`/`7`/`14`/`30`/`60`/`100`/`365` | Chuỗi cá nhân vượt một mốc trong lúc dùng app | `HomeScreen` | Giữ chân người dùng (TM20) |
| `badge_earned` | `kind`: `first5k`/`first10k`/`firstHalf`/`total100km`/`total500km`/`streak7`/`streak30`/`streak100`/`challenge` | Lần đầu thấy huy hiệu mới (Home) | `HomeScreen` | Giữ chân, mốc người dùng đạt (TM40) |

## Đề xuất chưa làm (cần Product duyệt trước khi thêm)
Theo checklist TM76: `group_run_start` (TM10) — thêm khi các tính năng tương ứng được làm. Phễu
*mời → cài app → vào nhóm* cần link mời (X25) để đo bước "cài".
Theo X11: khi có màn đồng ý thu thập dữ liệu, mọi event trên chỉ gửi sau khi người dùng đồng ý ở EEA/UK.

## Kiểm chứng
- Test tự động: `test/core/base_infra_test.dart` (tên dành riêng, sink thay thế, event nhóm TM76).
- Thủ công: DebugView trên bản `dev`, xác nhận không có tham số chứa id/tọa độ. **Chưa làm** (cần máy thật + Firebase Console).
