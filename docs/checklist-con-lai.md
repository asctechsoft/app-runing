# STRIDE — Checklist việc còn lại (giao cho người thực hiện)

Cập nhật: 2026-10-22 · Nhánh: `feat/asc-base` · Nguồn đối chiếu: `STRIDE_Todo_Code_End_to_End.docx` (92 việc, 76 đã có code + test tự động),
`STRIDE_Design_System_v1.docx`, `docs/scope.md`, `docs/adr/0001-stack.md`, `docs/adr/0002-shared-base.md`, `docs/build.md`, `CLAUDE.md`.

## 0. Cách dùng file này
- Mỗi việc có **ID**, **mức ưu tiên**, **bên làm đề xuất**, **cách nghiệm thu**. Điền vào dòng bên dưới việc khi làm: `Người: … · Hạn: … · PR: … · Bằng chứng: …`.
- Mức ưu tiên: **P0** = chặn phát hành · **P1** = cần cho "đủ phạm vi" · **P2** = nâng cao, làm sau.
- Đánh dấu `[x]` chỉ khi có bằng chứng (ảnh/video/log/PR/test). Không đánh dấu theo cảm giác.
- Quy tắc nền (không vi phạm khi làm bất kỳ việc nào): xem `CLAUDE.md` — không chữ cứng trong UI, không nút giả, offline-first, không đưa id/tọa độ vào analytics, không commit secret.
- Chạy kiểm tra trước mỗi PR: `flutter analyze` · `flutter test` · `dart format -l 160 lib test` (dùng Dart của Flutter) · `python build.py` nếu đụng build.

### Trạng thái hiện tại (để người nhận nắm nhanh)
| Hạng mục | Tình trạng |
|---|---|
| Code mobile | Có đủ luồng P0 + phần lớn P1, **389 test tự động đạt**, `flutter analyze` còn 33 cảnh báo mức *info* có từ trước |
| Backend | **Đã bỏ và đã xóa khỏi repo** (2026-10-23; quyết định 2026-10-19): dùng Firebase Auth + Cloud Firestore, không có server riêng. Mã cũ xem lịch sử git |
| Đa ngôn ngữ | Hạ tầng XML (`AscLocale`) xong; **mới có en + vi** (1.660 key, bản vi do AI dịch, chưa có người bản ngữ rà) |
| Thiết bị thật | Đã chạy thử trên Samsung SM-G996B (Android 15): tiếng Việt, bản đồ, ghi chạy, tạm dừng, Back, kết thúc. **Chưa** kiểm chứng nền/khóa màn hình/pin |
| Tính năng nhóm | Đăng nhập Google, vào/rời club, bài đăng/cổ vũ/bình luận, thử thách cá nhân: **có**. Tạo/quản lý club, mời, chuỗi nhóm, đội, bảng xếp hạng, huy hiệu, trao giải, push, chạy nhóm: **chưa** — xem **mục 4B** |
| Git | 8 commit trên `feat/asc-base` **chưa push, chưa có PR**; CI chưa chạy với cấu hình mới |

---

## 1. Việc cần làm ngay (đưa code vào `main`)
- [ ] **S01 · P0 · Dev** — Push `feat/asc-base`, mở PR vào `main`, cho CI chạy. Sửa mọi lỗi CI (dự kiến: bước `dart format --set-exit-if-changed` ở vài file cũ vì đổi lên Flutter 3.47.4; kiểm tra `submodules: recursive`, Python 3.12).
  - Nghiệm thu: CI xanh cả 2 job; APK `app-dev-debug.apk` là artifact.
- [x] **S02 · P0 · Dev** — ~~Quyết định số phận thư mục `backend/`~~ **Đã xóa** `backend/` (195 file), gỡ job `backend` khỏi CI, cập nhật `README.md`, `CLAUDE.md`, ADR 0001, `docs/scope.md`, `docs/domain-model.md`, `docs/firestore-schema.md`, comment trong code. Người: Claude · 2026-10-23.
- [x] **S03 · P1 · Dev** — ~~Cập nhật `docs/scope.md` và `docs/adr/0001-stack.md`~~ Đã cập nhật (Firebase thay backend, chuỗi qua key, logo, trạng thái 389 test). Còn lại phải làm khi có thay đổi mới: giữ hai file này đồng bộ với thực tế.
- [ ] **S04 · P1 · Dev** — Commit `.vscode/launch.json` + `tasks.json` (cấu hình chạy theo flavor) nếu cả nhóm muốn dùng chung.
- [ ] **S05 · P0 · Quản trị** — **Thu hồi và tạo lại** token Telegram bot và mật khẩu email (Gmail App Password) từng nằm trong `build_helper.py`/`build.py` của repo smart_drink/dsp_base (đã lộ). Xóa khỏi lịch sử git của các repo đó nếu có thể.
- [ ] **S06 · P1 · Dev** — Sửa 33 cảnh báo *info* của `flutter analyze` (chủ yếu `prefer_initializing_formals`, vài `deprecated_member_use`: `onReorder` → `onReorderItem`, `TickerMode.of`). Mục tiêu: `flutter analyze` sạch hoàn toàn.
- [ ] **S07 · P1 · Dev** — Nâng Gradle (8.14 → ≥ 9.1) và Android Gradle Plugin (8.11.1 → ≥ 9.0.1) theo cảnh báo của Flutter ("sẽ sớm ngừng hỗ trợ"). Chỉ làm khi base (`dsp_base`/smart_drink) cùng nâng, để hai app còn chung họ phiên bản.

---

## 2. Firebase và hạ tầng
Commit chuyển sang Firebase ghi rõ: **"Chưa kiểm chứng với Firestore thật"**.
- [ ] **FB01 · P0 · Dev/Quản trị** — Bật **Cloud Firestore** (Native mode) trong Firebase Console, project `app-runing-667b3`.
- [ ] **FB02 · P0 · Dev** — Deploy rules và indexes: `firebase deploy --only firestore:rules,firestore:indexes --project app-runing-667b3`. Ghi lại kết quả.
- [ ] **FB03 · P0 · Dev** — Viết **test cho `firestore.rules`** bằng Firebase Emulator (`@firebase/rules-unit-testing`): mỗi collection trong `docs/firestore-schema.md` cần ca "được phép" và ca "bị chặn" (người lạ đọc/ghi hoạt động của người khác, live-share chỉ người được mời đọc, `routes` chỉ Admin SDK ghi, `reports`/`feedback` chỉ tạo). Hiện **chưa có test nào**.
- [ ] **FB04 · P0 · QA** — Thử end-to-end với Firestore thật: đăng ký email, xác minh email, đặt lại mật khẩu, đăng nhập Google, đồng bộ (tạo/sửa/xóa hoạt động, xung đột hai máy, chống trùng khi thử lại), chuyển dữ liệu khách → tài khoản, xuất dữ liệu, xóa tài khoản.
- [ ] **FB05 · P1 · Dev** — Seed dữ liệu dev: chạy `node scripts/seed-firestore.mjs` (cần Admin SDK credential cục bộ, không commit). Mô tả cách chạy vào `docs/`.
- [ ] **FB06 · P0 · Dev** — **Giới hạn chi phí/lạm dụng** (Firestore không có rate limit như backend cũ): bật Firebase App Check cho Firestore, đặt budget alert, kiểm tra chỉ số đọc/ghi mỗi phiên.
- [ ] **FB07 · P0 · Dev** — **App Check**: đăng ký Play Integrity cho bản release; đăng ký debug token cho máy dev; sau khi chắc mới bật *enforce*. Hiện app bật App Check nhưng chưa enforce.
- [ ] **FB08 · P0 · Dev** — Thêm **SHA-1/SHA-256 của khóa phát hành** (và khóa upload Play) vào Firebase để Google Sign-In chạy ở bản release. Hiện mới có SHA-1 debug.
- [ ] **FB09 · P1 · Dev** — iOS: tạo app iOS trong Firebase, thêm `GoogleService-Info.plist`, cấu hình URL scheme Google Sign-In. Hiện Firebase bị bỏ qua trên iOS.
- [ ] **FB10 · P1 · Dev** — Chính sách giữ dữ liệu sau xóa tài khoản (đề xuất: xóa cứng trong 30 ngày) — chốt với Product rồi hiện thực (Cloud Function hoặc job).
- [ ] **FB11 · P1 · Dev** — Crashlytics: kiểm chứng báo lỗi lên console từ bản dev (ép một lỗi thử); thêm mapping/symbols nếu cần.
- [ ] **FB12 · P1 · Dev** — Remote Config: hiện `StrideBase.remoteConfigDefaults` rỗng. Quyết định có dùng cho feature flag (`FeatureFlags` trong `configs/env.dart`) không; nếu có, nối vào.

---

## 3. Kiểm chứng trên thiết bị thật (bắt buộc trước G0/G2)
Mỗi mục: ghi **model máy, Android/iOS version, kết quả, ảnh/video, log**. Khuyến nghị tối thiểu 3 máy Android (Samsung, Xiaomi/Oppo vì hay kill nền, Pixel) + 1 iPhone khi có.

| ID | Mức | Việc | Nghiệm thu |
|---|---|---|---|
| A03 / F05 | P0 | Đếm bước: foreground, background, khởi động lại máy, đứng yên, so với đếm tay 100/500/1000 bước | Sai lệch ≤ ngưỡng đội chốt (đề xuất ≤ 10%); bước không nhảy/âm sau reboot |
| A04 / G05 / Q04 | P0 | Ghi GPS khi **khóa màn hình**, có cuộc gọi đến, bật tiết kiệm pin, tối ưu pin của hãng (Xiaomi/Oppo/Huawei), OS kill app giữa chừng | Lộ trình liên tục, không mất >N giây; foreground service + notification hiển thị; hồi phục đúng sau kill |
| G04 | P0 | Chất lượng lọc GPS và ngưỡng auto-pause ngoài trời (đi bộ, chạy, đứng chờ đèn đỏ, đường hầm/nhà cao tầng) | Quãng đường sai số chấp nhận được; không auto-pause nhầm |
| G07 | P0 | Pause thủ công **không** tự resume; auto-pause tự resume khi di chuyển | Đúng kịch bản trong `STRIDE_Design_System_v1.docx` mục chạy |
| L02 | P1 | Ghép nối cảm biến nhịp tim BLE thật (chuẩn Heart Rate Service 0x180D), mất kết nối giữa chừng, kết nối lại | Hiển thị nhịp tim, ghi vào hoạt động, không crash khi mất sóng |
| Q04 | P0 | Dialog quyền hệ thống (vị trí chính xác/xấp xỉ, **vị trí nền**, nhận diện hoạt động, thông báo, Bluetooth) ở từng trạng thái: cho phép/từ chối/từ chối vĩnh viễn/đổi trong Cài đặt | Luôn có đường thoát và nút "Mở Cài đặt"; không kẹt |
| Q04 | P0 | Thông báo nhắc nhở (đúng giờ, sau reboot, Doze, múi giờ đổi), share sheet, image picker, TTS (giọng đọc mốc km) | Chạy đúng trên ≥ 3 máy |
| Q05 | P0 | **Phiên dài** 3–5 giờ: pin, bộ nhớ, dung lượng DB, độ mượt UI, không rò bộ nhớ | Pin tụt ≤ ngưỡng đội chốt/giờ; app không bị OS thu hồi |
| Q06 | P0 | Module mở rộng end-to-end: interval, indoor run, devices, explore (clubs/challenges/routes), live sharing | Mỗi luồng chạy từ đầu đến cuối với Firestore thật |
| Q07 | P0 | UAT theo kịch bản người dùng trong `Full_luong_app_dem_buoc_chan_chay_bo.docx` | Biên bản UAT có chữ ký Product |
| — | P1 | Mạng yếu / mất mạng giữa buổi chạy / chuyển Wi-Fi ↔ 4G / **mạng chặn tên miền bản đồ** (đã gặp: router trả `127.0.0.1` cho `openstreetmap.org`) | Ghi chạy không gián đoạn; bản đồ tự dùng nguồn dự phòng; có thông báo rõ khi không tải được nền |
| — | P1 | Máy màn hình nhỏ (< 5.5"), màn hình lớn/gập/tablet, cỡ chữ hệ thống 200%, chế độ tối của hệ điều hành | Không tràn chữ, không mất nút (xem mục 8) |

---

## 4. Tính năng chưa làm / hoãn
- [ ] **F01 · P1 · Dev** — **K04 Giáo án và lịch tập** (cờ `workout.plans` đang tắt). Cần nội dung giáo án được Product duyệt. Khi bật: danh sách giáo án, chi tiết, lịch tuần, bắt đầu từ giáo án, theo dõi tiến độ.
- [ ] **F02 · P1 · Dev** — **Health Connect (Android) / HealthKit (iOS)** nhập bước (cờ `steps.health` tắt). Cần spike trên máy thật (F02), ưu tiên nguồn dữ liệu (đã có `step_source_priority.dart`), xử lý trùng với cảm biến.
- [ ] **F03 · P1 · Dev** — Đăng nhập **Apple** (cờ `auth.apple` tắt, cần client ID) — bắt buộc nếu phát hành iOS có đăng nhập bên thứ ba.
- [ ] **F04 · P1 · Dev** — UI câu lạc bộ: **duyệt yêu cầu tham gia, phân quyền (owner/admin/member), tạo sự kiện**. → Đã mở rộng chi tiết ở **mục 4B** (TM01–TM06); làm theo mục 4B, mục này chỉ để đối chiếu checklist gốc.
- [ ] **F05 · P1 · Dev** — Màn **danh sách tuyến đã lưu** (đã có collection `users/{uid}/savedRoutes`).
- [ ] **F06 · P1 · Dev** — **Xuất toàn bộ dữ liệu tài khoản** từ màn chi tiết (hiện chỉ xuất theo hoạt động).
- [ ] **F07 · P1 · Dev** — Quản lý **thiết bị** nâng cao: nhớ nhiều cảm biến, ưu tiên thiết bị, ghi chú pin yếu.
- [ ] **F08 · P2 · Dev** — Web admin vận hành (N04) — ngoài phạm vi đợt này.
- [ ] **N02 · P0 · Dev/Ops** — Giám sát chất lượng hệ thống: dashboard Crashlytics/Analytics, cảnh báo tỷ lệ crash, độ trễ đồng bộ, lỗi quyền.
- [ ] **N03 · P0 · Dev/Ops** — Sao lưu, khôi phục và **migration**: kế hoạch export Firestore định kỳ; migration schema SQLite cục bộ (`app_database.dart`) có test nâng cấp từ mọi phiên bản cũ.
- [ ] **F09 · P1 · Dev** — Cân nhắc **lưu phiên chạy dở khi app bị thu hồi lúc đang tạm dừng** và nhắc người dùng (đã có recovery, cần kiểm chứng thật — xem mục 3).
- [ ] **F10 · P1 · Product** — Quyết định còn mở trong `docs/scope.md`: công thức calo (`met-v1`), tiêu chí kỷ lục (1 km/5 km), danh sách thiết bị test, **nhà cung cấp tile production**.

---

## 4B. Chạy theo nhóm/đội: chia sẻ nhóm, chuỗi (streak), thử thách đội, trao giải
Mục tiêu sản phẩm: **thúc đẩy mọi người chạy cùng nhau** — tạo nhóm, rủ bạn bè, duy trì chuỗi hằng ngày (cá nhân và nhóm), chạy theo đội, bảng xếp hạng, huy hiệu và trao giải.
Mã ID của mục này: `TM` (Team). Mọi việc đều phải tuân theo quy tắc nền ở mục 0 (không chữ cứng, offline-first, quyền riêng tư mặc định "chỉ mình tôi", không đưa id/tọa độ vào analytics) và mục 6–8 (đa ngôn ngữ, animation, điểm chạm).

### 4B.1 Hiện trạng (đã đối chiếu code + `firestore.rules`, 2026-10-23)
| Khả năng | Có chưa | Chi tiết thực tế |
|---|---|---|
| Đăng nhập Google | **Có** (code) | Firebase Auth + Google Sign-In, cờ `auth.google`. Máy dev đã đăng nhập được. **Chưa** kiểm chứng bản release (cần SHA-1/SHA-256 khóa phát hành, mục FB08) và iOS (cần `GoogleService-Info.plist`) |
| Câu lạc bộ: tìm, vào, rời | **Có** | `searchClubs`, `myClubs`, `requestJoin` (club công khai vào ngay, club riêng chờ duyệt), `leaveClub` |
| Câu lạc bộ: bài đăng, cổ vũ, bình luận, báo cáo, chặn | **Có** | Bài đăng chỉ là **chữ**; cheer, comment, report, block đã có |
| Sự kiện: xem + RSVP | **Có** | `rsvp`. Rules cho thành viên tạo sự kiện nhưng **chưa có UI tạo sự kiện** |
| **Tạo câu lạc bộ trong app** | **Chưa** | `firestore.rules`: `clubs … allow create, delete: if false` → hiện chỉ seed bằng Admin SDK. Người dùng **không thể tự tạo nhóm** |
| Quản lý thành viên (danh sách, duyệt yêu cầu, phân quyền, xóa/cấm) | **Chưa** | Rules: `members/{uid} allow update: if false` nên không đổi được vai trò/trạng thái; chưa có UI |
| Mời bạn bè (link, mã, QR) | **Chưa** | Không có deep link/invite code |
| Chia sẻ buổi chạy vào nhóm | **Chưa** | Bài đăng không đính kèm hoạt động; chưa có "thẻ buổi chạy" trong feed |
| Mục tiêu chung của nhóm | **Chưa** | Chỉ có mục tiêu cá nhân (`goals`) |
| Chuỗi (streak) | **Một phần** | Chỉ có "Your week streak" **cá nhân** ở Home (7 chấm ngày đạt mục tiêu **bước**, `home_logic.dart`). **Chưa có** chuỗi ngày liên tiếp (hiện tại/dài nhất), chưa có "ngày bảo lưu" (freeze), **chưa có chuỗi nhóm** |
| Thử thách: xem, tham gia, rời, tiến độ cá nhân | **Có** | Tiến độ tính ở **client** từ hoạt động cục bộ rồi ghi `progressValue` (dễ bị gian lận) |
| Tạo thử thách trong app | **Chưa** | Rules: `challenges … allow create, delete: if false` → chỉ Admin seed |
| Bảng xếp hạng | **Chưa có UI** | Có cờ `leaderboardOptIn` (mặc định `false`) và rule đọc, nhưng **không có màn bảng xếp hạng** |
| Chạy theo đội (đội A vs đội B) | **Chưa** | Không có `teamId`, không có điểm đội |
| Huy hiệu / giải thưởng / trao giải | **Chưa** | Có trường `badgeKey` trong model và seed (`dev-badge`) nhưng **không có hệ thống huy hiệu, màn hình, logic trao**. Chỉ có kỷ lục cá nhân (`records`) |
| Chạy cùng nhau thời gian thực | **Một phần** | Chỉ có **live sharing một chiều**: chủ buổi chạy → tối đa 20 người xem (chọn theo email), chỉ lưu điểm mới nhất, hạn 1/2/4 giờ hoặc hết buổi chạy. **Chưa có** "phiên chạy nhóm" (cùng bắt đầu, cùng thấy nhau, đếm ngược chung, tổng quãng đường nhóm) |
| Thông báo đẩy (push) cho nhóm | **Chưa** | Chỉ có thông báo cục bộ (nhắc nhở) và hộp thư trong app. Chưa có FCM, chưa lưu token thiết bị |
| Cloud Functions / xử lý phía server | **Chưa** | Không có. Mọi thứ chạy ở client + rules |

**Kết luận:** luồng "đăng nhập → lập nhóm → rủ bạn → chạy hằng ngày giữ chuỗi → thi đội → nhận giải" mới có **đoạn đầu** (đăng nhập, vào/rời nhóm có sẵn, đăng bài, thử thách cá nhân). Phần tạo/quản lý nhóm, mời, chuỗi, đội, bảng xếp hạng, huy hiệu, trao giải, push và chạy nhóm thời gian thực **chưa được làm**.

### 4B.2 Câu hỏi Product phải chốt trước khi làm (ảnh hưởng thiết kế dữ liệu)
- [ ] **TM00 · P0 · Product** — Trả lời và ghi vào `docs/` (ADR mới) các điểm sau:
  1. **"Nhóm" là gì?** Giữ *Club* (cộng đồng, nhiều người) và thêm *Đội* (team) nhỏ bên trong thử thách? Hay thêm khái niệm "Crew" 2–30 người rủ nhau chạy hằng ngày? Giới hạn số thành viên, số nhóm mỗi người, ai được tạo nhóm (mọi người hay cần đủ điều kiện).
  2. **Chuỗi tính thế nào?** Ngày đạt = đạt mục tiêu **bước**, hay có **hoạt động chạy/đi bộ** tối thiểu (X km hoặc Y phút), hay một trong hai? Có "ngày bảo lưu" (freeze) không, bao nhiêu lần/tháng? Chuỗi nhóm: *tất cả* hay *≥ K%* thành viên đạt mỗi ngày? Mất chuỗi có khôi phục không?
  3. **Điểm thi đội = gì?** Tổng km, trung bình mỗi người (công bằng khi đội khác quân số), số ngày hoạt động, tổng thời gian? Chia đội thế nào (tự chọn, ngẫu nhiên cân bằng theo năng lực)? Có cho đổi đội giữa kỳ?
  4. **Giải thưởng gì?** Chỉ huy hiệu/danh hiệu số, hay **vật phẩm/voucher/tiền thật**? Nếu thật: ai tài trợ, quy trình nhận, điều khoản, pháp lý (khuyến mại, thuế, độ tuổi, hạn chế vùng), chính sách App Store/Google Play về giải thưởng.
  5. **Hoạt động nào được tính vào nhóm?** Cả `run`, `walk`, `indoorRun` (indoor là ước lượng từ bước)? Hoạt động riêng tư (`onlyMe`) có được **đóng góp số liệu** vào nhóm không (đề xuất: cần bật "đóng góp cho nhóm" riêng, khác với "công khai")?
  6. **Chống gian lận mức nào?** Chỉ hoạt động có GPS thật? Chặn tốc độ bất hợp lý (đi xe)? Chặn vị trí giả (`isMocked`)? Ai xử lý khiếu nại?
  7. **Có chấp nhận Cloud Functions không?** Bạn đã quyết định "không cần backend". Phần lớn tính năng nhóm (tổng hợp điểm công bằng, push, chống gian lận, đếm thành viên chịu tải) làm **an toàn** cần mã phía server (Cloud Functions, gói Blaze, vẫn là serverless). Nếu không chấp nhận: chỉ làm bản "tin cậy client" (dễ gian lận, không push theo sự kiện) — ghi rõ giới hạn.
  8. **Có cần chat nhóm không?** (Chi phí kiểm duyệt cao; đề xuất không làm chat đầy đủ ở đợt này, dùng bài đăng + bình luận có sẵn.)

### 4B.3 Gói A — Tạo và quản lý nhóm (nền tảng, làm đầu tiên)
- [ ] **TM01 · P0 · Dev** — **Tạo câu lạc bộ** trong app: form (tên 3–40 ký tự, mô tả ≤ 300, vùng, công khai/riêng tư, ảnh đại diện tùy chọn), tạo `clubs/{id}` + `members/{uid}` vai trò `owner` bằng một thao tác nguyên tử (batch/transaction), `nameLower` để tìm kiếm. **Phải sửa `firestore.rules`** (hiện `create: false`): chỉ cho tạo khi `ownerId == auth.uid`, kiểm tra độ dài/giá trị hợp lệ, giới hạn số club mỗi người (cần Functions hoặc đếm trong rules), chống spam.
  - Nghiệm thu: tạo được club, mình là owner, hiện trong "Câu lạc bộ của tôi"; rules test chặn tạo club thay người khác/dữ liệu sai.
- [ ] **TM02 · P0 · Dev** — **Quản lý thành viên**: danh sách thành viên (phân trang, tìm), **duyệt/từ chối yêu cầu** (club riêng), phân quyền (owner/admin/member), xóa/cấm thành viên, chuyển quyền chủ, owner muốn rời phải chuyển quyền hoặc giải tán. Sửa rules (`members update: false` hiện chặn mọi thay đổi): owner/admin được sửa `status`/`role` theo quy tắc; không tự nâng quyền; admin không xóa owner.
- [ ] **TM03 · P0 · Dev** — **Mời bạn bè**: link mời `https://…/club/<id>?code=<mã>` (Android App Links / iOS Universal Links; không dùng Firebase Dynamic Links vì đã ngừng), mã mời + QR, nút chia sẻ (`share_plus`), mời theo email (có `userLookup`), mã có hạn/thu hồi/giới hạn lượt. **Người chưa cài app**: mở trang cầu nối → cửa hàng → sau khi cài và đăng nhập tự vào đúng club (Android Install Referrer; iOS cần giải pháp khác). Màn "Lời mời" khi mở link: xem club, nút Tham gia.
- [ ] **TM04 · P1 · Dev** — Sửa thông tin club, **nội quy**, ghim bài, ảnh đại diện/ảnh bìa (cần Firebase Storage + rules storage — hiện chưa dùng), xóa/giải tán club (xóa dữ liệu liên quan, thông báo thành viên).
- [ ] **TM05 · P1 · Dev** — **Sự kiện chạy chung**: tạo/sửa/hủy (thời gian + múi giờ, địa điểm, liên kết `routes`, giới hạn người), RSVP đã có; **nhắc trước 1 ngày/1 giờ** (thông báo cục bộ theo múi giờ), danh sách người tham gia, xuất lịch `.ics`, hiển thị đếm ngược trên Home khi sự kiện sắp diễn ra. (Rules đã cho thành viên tạo; thiếu UI + kiểm tra quyền admin.)
- [ ] **TM06 · P1 · Dev** — **Chia sẻ buổi chạy vào nhóm**: sau khi lưu có nút "Đăng vào câu lạc bộ" (chọn club, hoặc tự động theo cài đặt). Thẻ hoạt động trong feed: loại, quãng đường, thời gian, pace, ảnh bản đồ **ẩn điểm đầu/cuối** theo quyền riêng tư, cheer + comment. Chỉ chia sẻ khi người dùng chủ động/đồng ý (liên quan TM60).
- [ ] **TM07 · P2 · Dev** — Chat nhóm thời gian thực (chỉ khi Product chốt ở TM00.8): kiểm duyệt, giới hạn, chi phí đọc/ghi.

### 4B.4 Gói B — Chuỗi (streak) và mục tiêu nhóm
- [ ] **TM20 · P0 · Dev** — **Chuỗi cá nhân đầy đủ**: số ngày liên tiếp hiện tại + dài nhất, hiển thị ở Home/Profile/Progress; quy tắc "ngày đạt" theo TM00.2; múi giờ địa phương (`tzId`), qua nửa đêm, đổi múi giờ, xóa/sửa hoạt động, đổi mục tiêu giữa chừng, **dữ liệu thiếu không phá chuỗi** (không giả lập — theo nguyên tắc sản phẩm); tính được **offline**, lưu `users/{uid}/stats/streak` và tự tính lại từ dữ liệu khi lệch. Có **ngày bảo lưu** nếu Product chọn. Hiện chỉ có 7 chấm của tuần (`computeWeekStreak`).
  - Nghiệm thu: bộ test biên (qua nửa đêm, DST, đổi múi giờ, xóa hoạt động, offline→online), UI có trạng thái rỗng/lỗi.
- [ ] **TM21 · P1 · Dev** — **Chuỗi nhóm**: nhóm giữ chuỗi nếu mỗi ngày đạt điều kiện nhóm (theo TM00.2); hiển thị "Chuỗi X ngày của nhóm" + ai chưa hoàn thành hôm nay (tùy chọn ẩn tên để tránh áp lực); nhắc nhẹ cuối ngày; lịch sử chuỗi.
- [ ] **TM22 · P1 · Dev** — **Mục tiêu nhóm** hằng ngày/tuần/tháng: thanh tiến độ chung (tổng km/bước/số buổi), đóng góp từng người (tùy chọn hiển thị), chu kỳ đặt lại theo `weekStart`, lịch sử các kỳ, khi đạt có chúc mừng (xem animation mục 7, **một lần**).
- [ ] **TM23 · P0 · Dev/Kiến trúc** — **Quyết định nơi tính số liệu nhóm**: (a) client tự ghi `progressValue` (hiện tại, dễ gian lận, lệch khi offline) hay (b) **Cloud Function** trigger khi `users/{uid}/activities` đổi → cập nhật `clubs/{id}/stats/{kỳ}` và bảng xếp hạng (an toàn, idempotent, xử lý sửa/xóa qua `revision`/`deletedAt`). Ghi ADR. Nếu chọn (b) xem TM51.
- [ ] **TM24 · P0 · Dev/Product** — **Quy tắc hoạt động hợp lệ cho nhóm/thử thách**: loại hoạt động; có GPS thật hay indoor ước lượng (nhãn *estimated*, có tính điểm không); thời gian/quãng tối thiểu; tốc độ tối đa hợp lý theo loại (chống đi xe); hoạt động `onlyMe` chỉ tính khi bật "đóng góp cho nhóm"; hoạt động đồng bộ trễ sau khi offline tính theo `startedAt`, không theo lúc upload. Viết thành hàm thuần có test (như `utils/calc/`).

### 4B.5 Gói C — Thử thách, đội thi và bảng xếp hạng
- [ ] **TM30 · P0 · Dev** — **Màn bảng xếp hạng** cho thử thách và club (tuần/tháng/toàn thời gian): top N + **vị trí của tôi**, phân trang, cập nhật gần thời gian thực, **quy tắc đồng hạng** (ai đạt mốc trước), tôn trọng `leaderboardOptIn` (hiện mặc định `false` → khi tham gia hỏi rõ có hiện tên không; cho phép biệt danh), ẩn người bị chặn/bị cấm, nút báo cáo. Cần index Firestore (`participants` sắp theo `progressValue` giảm dần) → thêm vào `firestore.indexes.json`.
- [ ] **TM31 · P1 · Dev** — **Tạo thử thách trong app** cho owner/admin club (hiện `create: false`): chọn loại (quãng đường/số buổi/thời gian/chuỗi), mục tiêu, thời gian bắt đầu-kết thúc + múi giờ, loại hoạt động hợp lệ (TM24), huy hiệu thưởng, mô tả quy tắc; mẫu có sẵn (30 ngày chạy, 100 km trong tháng, chuỗi 7 ngày); xem trước, sửa trước khi bắt đầu, hủy.
- [ ] **TM32 · P1 · Dev** — **Chế độ đội (đội vs đội)**: tạo đội (tên, màu/logo), chia đội (tự chọn / ngẫu nhiên cân bằng), điểm đội theo TM00.3 (chuẩn hóa khi khác quân số), xếp hạng đội, đóng băng danh sách đội trước hạn (quy tắc rời/vào giữa kỳ). Thêm `teamId` vào participant, subcollection `teams`.
- [ ] **TM33 · P0 · Dev** — **Vòng đời thử thách**: sắp diễn ra → đang diễn ra → **thời gian chờ đồng bộ (grace period)** → kết thúc/khóa → trao giải. Ca đặc biệt cần test: hoạt động ghi **offline** đồng bộ sau hạn, múi giờ khác nhau giữa người tham gia và thử thách (`tzId`), sửa/xóa hoạt động sau khi kết thúc, người rời/bị cấm giữa kỳ, hai thiết bị cùng tài khoản.
- [ ] **TM34 · P1 · Dev** — Thông báo thử thách: sắp bắt đầu/kết thúc, bị vượt hạng, đạt mốc 25/50/75/100%, có kết quả (cần TM50).

### 4B.6 Gói D — Huy hiệu, danh hiệu, trao giải
- [ ] **TM40 · P1 · Dev/Design** — **Hệ thống huy hiệu**: định nghĩa (key, tên/mô tả đa ngôn ngữ, icon, điều kiện, độ hiếm); loại: hoàn thành thử thách (dùng `badgeKey` có sẵn), mốc cá nhân (5K đầu, 100 km, chuỗi 7/30/100 ngày), mốc nhóm. Lưu `users/{uid}/badges/{id}` (`earnedAt`, nguồn) **idempotent** (không trao hai lần); **Tủ huy hiệu** ở Hồ sơ/Records, màn chi tiết, chia sẻ ảnh, **animation nhận huy hiệu** (xem mục 7, tắt khi giảm chuyển động) + haptic, thông báo. Cần bộ icon/illustration từ Design.
- [ ] **TM41 · P1 · Dev** — **Trao giải thử thách**: màn *Kết quả* (podium top 3 cá nhân, đội thắng, giải hạng mục: nhiều km nhất, chuỗi dài nhất, tiến bộ nhiều nhất), thời điểm trao sau grace period, chia sẻ ảnh kết quả, **khiếu nại/phúc khảo**, thu hồi giải khi phát hiện gian lận (kèm thông báo).
- [ ] **TM42 · P0 (nếu có giải thật) · Product/Pháp chế/Dev** — **Giải thưởng thật** (voucher, quà, tiền): quy trình nhận (thu thập địa chỉ/email = dữ liệu cá nhân, xin đồng ý, lưu tối thiểu, xóa sau khi giao), người tổ chức/tài trợ hiển thị rõ, **điều khoản** (cách chọn người thắng, hạn nhận), tuân thủ pháp luật khuyến mại/thuế/độ tuổi/vùng, **chính sách App Store/Google Play** về giải thưởng và cá cược. Chỉ làm sau khi trả lời TM00.4.
- [ ] **TM43 · P2 · Dev/Product** — Điểm/XP và cấp bậc: giới hạn điểm mỗi ngày và nhắc nghỉ để **không khuyến khích chạy quá sức** (an toàn sức khỏe).
- [ ] **TM44 · P2 · Dev** — Danh hiệu cho club (hoạt động nhất tháng, tiến bộ nhất).

### 4B.7 Gói E — Chạy cùng nhau thời gian thực
- [ ] **TM10 · P1 · Dev** — **Phiên chạy nhóm (group run)**: người tạo mở phiên từ club/sự kiện → mời thành viên → mỗi người vẫn ghi buổi chạy **riêng** nhưng gắn `groupRunId`; màn nhóm hiển thị vị trí/tiến độ các thành viên (mở rộng live sharing hiện có từ 1→n thành n↔n), **đếm ngược đồng bộ** (dùng giờ server), trạng thái từng người (sẵn sàng/đang chạy/xong), **tổng quãng đường nhóm**. Giới hạn số người; chỉ chia sẻ trong phiên và cần đồng ý rõ ràng; dừng chia sẻ khi kết thúc. **Chi phí/pin:** mỗi người chỉ ghi điểm mới nhất (đã có mô hình `lastPoint` ghi đè) và giãn tần suất 5–10 giây.
- [ ] **TM11 · P1 · Dev** — **Rủ chạy**: nút "Rủ cả nhóm chạy hôm nay" gửi push (cần TM50/TM51); "X đang chạy — tham gia?" mở thẳng phiên nhóm.
- [ ] **TM12 · P2 · Dev** — Cổ vũ thời gian thực trong lúc chạy (nhận cheer → rung/âm ngắn, tắt được); giọng đọc "Linh vừa xong 5 km" (theo ngôn ngữ app, xem L07); luôn có chữ thay thế.
- [ ] **TM13 · P2 · Dev** — Chạy "cùng nhau từ xa": mục tiêu chung trong ngày dù ở nơi khác nhau — dùng TM22.

### 4B.8 Gói F — Thông báo đẩy và nhắc (hạ tầng cho mọi tính năng nhóm)
- [ ] **TM50 · P0 · Dev** — **FCM**: thêm `firebase_messaging` (kiểm tra khớp họ Firebase 4.x của `dsp_base`), xin quyền thông báo (Android 13+/iOS), lưu token `users/{uid}/devices/{deviceId}` và **xóa khi đăng xuất**, kênh thông báo Android theo loại (nhóm, thử thách, nhắc nhở), bấm thông báo → deep link đúng màn, tùy chọn bật/tắt từng loại ở Hồ sơ, **thông báo theo ngôn ngữ người dùng**, giới hạn tần suất (chống spam), giờ yên tĩnh, đồng bộ với hộp thư trong app (`notification_repository`).
- [ ] **TM51 · P0 (nếu chọn kiến trúc server) · Dev/Ops** — **Cloud Functions** (`functions/`, TypeScript, gói Blaze): tổng hợp điểm khi hoạt động đổi (TM23), kết thúc thử thách + trao huy hiệu, gửi push, dọn dữ liệu, bộ đếm chịu tải (sharded counter thay cho `memberCount`/`participantCount` ghi từ client — dễ tranh chấp ở nhóm lớn). Test bằng Emulator, CI deploy, giám sát lỗi và chi phí, cảnh báo ngân sách.
- [ ] **TM52 · P1 · Dev** — **Nhắc giữ chuỗi**: "Hôm nay bạn chưa đạt mục tiêu, còn X giờ để giữ chuỗi" (thông báo cục bộ theo múi giờ, **không nhắc nếu đã đạt**, tôn trọng giờ yên tĩnh); nhắc nhóm nhẹ nhàng, không tạo áp lực/xấu hổ.

### 4B.9 Gói G — Quyền riêng tư, an toàn, chống lạm dụng (bắt buộc với tính năng xã hội)
- [ ] **TM60 · P0 · Dev/Product** — **Quyền riêng tư nhóm**: mặc định `onlyMe`; "đóng góp cho nhóm" là lựa chọn riêng và hiển thị rõ ai thấy gì; thành viên chỉ thấy số liệu tổng hợp nếu chọn; ẩn điểm đầu/cuối trên bản đồ chia sẻ; rời nhóm → tùy chọn xóa đóng góp; **xóa tài khoản** → gỡ khỏi bảng xếp hạng/nhóm; người dưới tuổi quy định. Cập nhật chính sách quyền riêng tư và Data Safety.
- [ ] **TM61 · P0 · Dev/Ops** — **Kiểm duyệt nội dung người dùng (UGC)** — bắt buộc để qua App Store/Google Play: báo cáo (đã có `reports`), chặn (đã có), công cụ cho admin club (ẩn bài, cấm thành viên), lọc từ cấm cơ bản, giới hạn tần suất đăng bài (cần rules/Functions vì không còn server rate limit), **quy trình xử lý báo cáo** (hàng đợi, thời hạn gỡ nội dung, người phụ trách), điều khoản sử dụng.
- [ ] **TM62 · P1 · Dev** — **Chống gian lận bảng xếp hạng**: kiểm tra hợp lý (tốc độ, nhảy vị trí, lộ trình trùng), cờ "đã xác minh GPS", đánh dấu vị trí giả (`isMocked` của geolocator), ngưỡng loại, nhật ký và quy trình loại/khôi phục.
- [ ] **TM63 · P1 · Dev** — **Chịu tải và chi phí**: `memberCount`/`participantCount` đang tăng bằng transaction từ client (`counterStep` trong rules) → "hot document" ~1 ghi/giây ở nhóm lớn; dùng sharded counter/Functions; phân trang mọi danh sách; kiểm tra index; ước tính chi phí đọc/ghi với 10.000 người dùng.

### 4B.10 Luồng người dùng cần dựng (để người làm đối chiếu)
1. **Lập nhóm:** đăng nhập Google → Hồ sơ → Khám phá → Câu lạc bộ → *Tạo câu lạc bộ* → đặt tên/quy tắc → *Mời bạn bè* (link/QR/email) → bạn mở link → (cài app) → đăng nhập → vào đúng nhóm → thấy feed/sự kiện/thử thách.
2. **Thử thách tháng:** admin tạo "100 km tháng 11" (cá nhân hoặc theo đội) → thành viên nhận push → tham gia → mỗi buổi chạy lưu xong **tự cộng** vào tiến độ → xem bảng xếp hạng + tiến độ đội → đạt mốc nhận huy hiệu → hết hạn → chờ đồng bộ → màn *Kết quả* + trao giải.
3. **Chạy chung hôm nay:** thành viên bấm *Rủ cả nhóm chạy* hoặc vào sự kiện → RSVP → nhắc trước giờ → *Phiên chạy nhóm* (đếm ngược chung) → thấy nhau trên bản đồ → kết thúc → đăng thẻ chung vào feed → cheer/comment.
4. **Giữ chuỗi:** Home hiện chuỗi cá nhân + chuỗi nhóm → nhắc cuối ngày nếu chưa đạt → mất chuỗi thì thông báo nhẹ nhàng + cách bắt đầu lại/khôi phục.

**Màn hình mới cần làm** (mỗi màn: trạng thái rỗng/tải/lỗi/offline/thiếu quyền, đa ngôn ngữ, animation, điểm chạm 48 — xem mục 6–8): Tạo/sửa club · Thành viên club · Duyệt yêu cầu · Mời (link/QR) · Lời mời · Quản lý sự kiện · Tạo thử thách · Bảng xếp hạng · Tạo/xem đội · Kết quả thử thách (podium) · Tủ huy hiệu · Chi tiết huy hiệu · Chuỗi (lịch + lịch sử) · Mục tiêu nhóm · Phòng chạy nhóm · Cài đặt thông báo · Quản trị club · Hàng đợi báo cáo (nếu có công cụ nội bộ).

### 4B.11 Dữ liệu, rules, index cần bổ sung (cập nhật CÙNG LÚC ba nơi: `docs/firestore-schema.md`, `firestore.rules`, `firestore.indexes.json`)
| Thêm | Mục đích |
|---|---|
| `clubs/{id}`: `inviteCode`, `inviteExpiresAt`, `rules`, `coverUrl`, `streak {current, longest, lastDay}`, `stats` | Mời, nội quy, chuỗi và thống kê nhóm |
| `clubs/{id}/members/{uid}`: `contributesToTeam`, `teamId`, quyền sửa cho owner/admin | Phân quyền, đóng góp, đội |
| `clubs/{id}/teams/{teamId}`, `challenges/{id}/teams/{teamId}`, participant thêm `teamId` | Đội thi |
| `clubs/{id}/stats/{kỳ}` | Tổng hợp mục tiêu nhóm theo kỳ |
| `users/{uid}/stats/streak`, `users/{uid}/badges/{id}`, `users/{uid}/devices/{deviceId}` | Chuỗi cá nhân, huy hiệu, token FCM |
| `groupRuns/{id}` + `participants` | Phiên chạy nhóm |
| `awards/{id}` (+ `claims`) | Giải thưởng, nhận giải |
| `invites/{code}` | Mã mời có hạn/thu hồi |
| Index: bảng xếp hạng (`participants` theo `progressValue` giảm dần), feed (`clubId` + `createdAt`), sự kiện (`clubId` + `startsAt`), thành viên theo vai trò | Truy vấn có phân trang |
| Rules: owner/admin được sửa thành viên, tạo thử thách/sự kiện; cấm tự nâng quyền; giới hạn kích thước và tần suất; bộ đếm chỉ tăng đúng bước | Bảo mật — **mỗi quyền có test Emulator** (FB03) |

### 4B.12 Kiểm thử và nghiệm thu riêng cho nhóm
- [ ] **TM70 · P0 · QA/Dev** — Test rules bằng Emulator cho từng quyền mới (owner/admin/member/người lạ/người bị chặn): tạo club, duyệt thành viên, sửa vai trò, đăng bài, tạo thử thách, đọc bảng xếp hạng khi `leaderboardOptIn=false`, đọc live/group run.
- [ ] **TM71 · P0 · Dev** — Test thuần (không cần Firebase) cho: tính chuỗi (biên múi giờ/nửa đêm/DST/xóa-sửa), điểm đội chuẩn hóa, xếp hạng và tie-break, quy tắc hoạt động hợp lệ, vòng đời thử thách + grace period.
- [ ] **TM72 · P0 · QA** — Thử **3–5 máy thật cùng lúc** cho phiên chạy nhóm và live share: đồng bộ đếm ngược, độ trễ vị trí, mất mạng/khôi phục, pin, kill app giữa chừng.
- [ ] **TM73 · P1 · QA** — Thử **offline → online**: hoạt động ghi khi mất mạng vẫn được cộng đúng vào nhóm/thử thách, không cộng trùng.
- [ ] **TM74 · P1 · Dev** — Hiệu năng: bảng xếp hạng 1.000 người, feed club 1.000 bài, danh sách thành viên 500 người (phân trang, không giật).
- [ ] **TM75 · P0 · QA/Product** — **UAT nhóm thật**: 10 người dùng, 7 ngày liên tiếp, một thử thách ngắn + chuỗi nhóm + một buổi chạy nhóm; biên bản có chữ ký Product.
- [ ] **TM76 · P1 · Dev** — Analytics (không chứa id/tọa độ): `club_create`, `club_invite_share`, `club_join`, `challenge_join`, `leaderboard_view`, `badge_earned`, `streak_milestone`, `group_run_start`…; phễu *mời → cài → vào nhóm*. Tên event **không** trùng tên dành riêng của Firebase (xem `utils/analytics.dart`).

### 4B.13 Thứ tự làm đề xuất
| Giai đoạn | Việc | Mục tiêu |
|---|---|---|
| 0 | TM00 (chốt câu hỏi Product), TM23 (kiến trúc client hay Functions), FB01–FB04 (bật Firestore, deploy rules, test rules) | Không làm tiếp khi chưa chốt — sai nền sẽ phải làm lại dữ liệu |
| 1 — MVP nhóm | TM01, TM02 (cơ bản), TM03 (link mời), TM20 (chuỗi cá nhân), TM30 (bảng xếp hạng), TM50 (FCM), TM60, TM61, TM70, TM71 | Lập nhóm, rủ bạn, thấy nhau, giữ chuỗi, có push; đủ điều kiện qua kiểm duyệt cửa hàng |
| 2 — Thi đua | TM31, TM33, TM24, TM40 (huy hiệu), TM21–TM22 (chuỗi + mục tiêu nhóm), TM05, TM06, TM51 (Functions), TM52, TM34 | Thử thách có vòng đời, huy hiệu, mục tiêu và chuỗi nhóm, sự kiện, chia sẻ hoạt động |
| 3 — Gắn kết sâu | TM10–TM11 (chạy nhóm), TM32 (đội vs đội), TM41 (trao giải), TM62–TM63, TM42 (giải thật nếu có) | Chạy cùng thời gian thực, thi đội, trao giải, chống gian lận, chịu tải |
| 4 — Tùy chọn | TM04, TM07, TM12, TM13, TM43, TM44 | Hoàn thiện |

Ước lượng rất thô (một dev đã quen codebase, chưa gồm thiết kế/QA): Giai đoạn 1 ≈ 4–6 tuần, giai đoạn 2 ≈ 5–7 tuần, giai đoạn 3 ≈ 6–8 tuần. Cần Design cung cấp icon huy hiệu, podium, màn tạo nhóm/mời trước khi dev làm UI.

---

## 5. Bản đồ (tile)
Hiện: nguồn chính OSM công cộng, dự phòng OSM France (HOT). Cả hai chỉ phù hợp dev/lưu lượng nhỏ. CARTO đã thôi cho dùng không key (ảnh watermark "API KEY REQUIRED").
- [ ] **MAP01 · P0 · Product/Dev** — Chọn **nhà cung cấp tile production** có SLA (MapTiler, Stadia Maps, Mapbox, Thunderforest, tự host…), chốt ngân sách. Truyền URL/khóa qua `--dart-define=STRIDE_TILE_URL=…` và `STRIDE_TILE_ATTRIBUTION=…`; **không commit khóa**. Nạp khóa vào CI qua secret.
- [ ] **MAP02 · P1 · Dev** — Cache tile cục bộ (`flutter_map_cache` hoặc tương đương) để xem lại tuyến khi offline và giảm tải.
- [ ] **MAP03 · P1 · Dev** — Hiển thị **thông báo khi nền bản đồ không tải được** (hiện chỉ ghi log ở debug; người dùng chỉ thấy ô xám). Gợi ý: banner nhỏ "Bản đồ không khả dụng, vẫn đang ghi lộ trình".
- [ ] **MAP04 · P1 · Dev** — Thêm `maxNativeZoom`/`maxZoom` đúng với nhà cung cấp; kiểm tra lộ trình rất ngắn (< 20 m) không phóng quá mức.
- [ ] **MAP05 · P1 · Dev** — Đồng bộ chữ ghi công (attribution) đúng yêu cầu của nhà cung cấp mới, hiển thị ở mọi màn bản đồ (chạy, kết quả, chi tiết, chia sẻ ảnh, khám phá tuyến, live share).

---

## 6. Đa ngôn ngữ (i18n / l10n)

### 6.1 Hiện trạng
- Chuỗi nằm ở `mobile/lib/xml_strings/values/strings.xml` (en) và `values-vi/strings.xml` (vi); gọi bằng `'key'.tr` / `'key'.trArgs([...])` (`lib/utils/l10n.dart`). Quy tắc thêm chuỗi: `CLAUDE.md` mục "Chuỗi giao diện".
- `test/core/strings_xml_test.dart` kiểm tra: en/vi đủ key, placeholder `%n$s` khớp, mọi key dùng trong code tồn tại.
- Công cụ dịch hàng loạt: `python build.py translate` (`mobile/tool/translate.py`, gọi máy chủ dịch nội bộ; đổi bằng `ASC_TRANSLATE_API_URL`). Chưa chạy thử với STRIDE.

### 6.2 Ngôn ngữ cần thêm
Danh sách 16 ngôn ngữ app smart_drink đang hỗ trợ — đề xuất dùng cùng bộ để hai app đồng nhất. Mỗi dòng cần: thư mục `values-xx`, khai asset trong `pubspec.yaml`, thêm `Locale` vào `AppLocaleConfig.supportedLocales` (`configs/locale_config.dart`), dịch, rà soát bởi người bản ngữ, chụp màn hình kiểm tra.

| Ngôn ngữ | Locale | Thư mục | Chữ viết/ghi chú | Dịch | Rà bản ngữ | Test UI |
|---|---|---|---|---|---|---|
| English | `en_US` | `values` | gốc | ✅ | ✅ | ✅ |
| Tiếng Việt | `vi_VN` | `values-vi` | Latin có dấu | ✅ (AI) | [ ] | một phần |
| Français | `fr_FR` | `values-fr` | Latin | [ ] | [ ] | [ ] |
| Italiano | `it_IT` | `values-it` | Latin | [ ] | [ ] | [ ] |
| Deutsch | `de_DE` | `values-de` | Latin; **chuỗi dài** → kiểm tra tràn | [ ] | [ ] | [ ] |
| Español | `es_ES` | `values-es` | Latin | [ ] | [ ] | [ ] |
| Русский | `ru_RU` | `values-ru` | Cyrillic; **số nhiều 3 dạng** | [ ] | [ ] | [ ] |
| Português | `pt_PT` | `values-pt` | Latin (cân nhắc thêm `pt_BR`) | [ ] | [ ] | [ ] |
| Türkçe | `tr_TR` | `values-tr` | Latin (chữ i/İ) | [ ] | [ ] | [ ] |
| العربية | `ar_SA` | `values-ar` | **RTL**, chữ nối, số nhiều 6 dạng | [ ] | [ ] | [ ] |
| Bahasa Indonesia | `id_ID` | `values-id` | Latin | [ ] | [ ] | [ ] |
| فارسی | `fa_IR` | `values-fa` | **RTL**, lịch/ số Ba Tư | [ ] | [ ] | [ ] |
| 简体中文 | `zh_CN` | `values-zh-rCN` | CJK, không dấu cách, cần font | [ ] | [ ] | [ ] |
| 繁體中文 | `zh_TW` | `values-zh-rTW` | CJK | [ ] | [ ] | [ ] |
| 日本語 | `ja_JP` | `values-ja` | CJK, cần font | [ ] | [ ] | [ ] |
| 한국어 | `ko_KR` | `values-ko` | Hangul, cần font | [ ] | [ ] | [ ] |
| (tùy chọn) Thai, Hindi, Polski, Nederlands, Ukrainian… | — | — | quyết định theo thị trường | [ ] | [ ] | [ ] |

- [ ] **L01 · P0 · Dev** — Thêm từng ngôn ngữ ở bảng trên theo thứ tự ưu tiên Product chốt (đề xuất: vi → en-GB/pt/es/fr/de/id → ru/tr/it → ja/ko/zh → ar/fa).
- [ ] **L02 · P0 · Biên dịch** — **Rà soát bản vi** (hiện do AI dịch) bởi người bản ngữ: giọng văn ("bạn"), thuật ngữ chạy bộ (pace, split, interval, cadence), chuỗi ngắn trên nút, thông báo lỗi.
- [ ] **L03 · P0 · Dev** — Mỗi ngôn ngữ mới: chạy `flutter test` (test XML kiểm tra đủ key và placeholder), chụp ảnh các màn chính, kiểm tra **tràn chữ/cắt chữ** (đặc biệt `de`, `ru`, `fi`).
- [ ] **L04 · P0 · Dev** — Chuỗi **số nhiều** (`_one`/`_other` đang dùng ở vài key như `history_day_activity`, `account_sync_pending`): với `ru`, `ar`, `pl`… cần thêm dạng `few/many/zero/two`. Cân nhắc dùng `intl` `Intl.plural` hoặc thêm cơ chế chọn key theo quy tắc CLDR. Rà tất cả chỗ ghép số + danh từ.
- [ ] **L05 · P0 · Dev** — **Màn chọn ngôn ngữ** trong Hồ sơ: "Theo hệ thống" + danh sách ngôn ngữ (dùng `LanguageNames` của asc_common cho tên bản ngữ), lưu qua `AscLocale.setAppLocale`/`useSystemLocale`. Hiện **chưa có UI** nào để đổi ngôn ngữ, app chỉ theo ngôn ngữ máy.
- [ ] **L06 · P0 · Dev** — **Đổi ngôn ngữ lúc chạy phải cập nhật giao diện ngay** (hiện phải mở lại app vì app dùng Riverpod, không có `GetMaterialApp`). Gợi ý: một `localeProvider` (Riverpod) bọc `MaterialApp.router(locale: …)`, `Key` theo locale để dựng lại cây, đồng thời gọi `Intl.defaultLocale = …`.
- [ ] **L07 · P0 · Dev** — **Giọng đọc TTS** (`run_audio.dart`, `profile_logic.dart`: `setLanguage('en-US')`) theo ngôn ngữ app; nếu máy không có giọng cho ngôn ngữ đó thì lùi về tiếng Anh và báo người dùng. Rà các câu đọc (mốc km, hoàn thành mục tiêu, chuyển phase interval) cho từng ngôn ngữ.
- [ ] **L08 · P0 · Dev** — **Định dạng ngày/giờ** theo ngôn ngữ: hiện mẫu đang là mẫu tiếng Anh (`'EEEE, MMMM d, y'`) nên tiếng Việt ra "Thứ Năm, tháng 10 22, 2026". Đổi sang skeleton của `intl` (`DateFormat.yMMMMEEEEd(locale)`, `DateFormat.Hm`/`jm` theo 12/24 giờ của máy) để thứ tự đúng từng ngôn ngữ ("Thứ Năm, 22 tháng 10, 2026"). Các file: `utils/activity_format.dart`, `models/ui_models/period.dart`, `screen_home`, `screens_progress`, `screen_history`, `screen_steps`, `screens_explore`, v.v.
- [ ] **L09 · P0 · Dev** — **Định dạng số/đơn vị**: `StrideFormat.locale = 'en_US'` và `NumberFormat.decimalPattern('en_US')` ở `setup_goal_screen` đang cố định. Theo ngôn ngữ (dấu thập phân `,` ở vi/de/fr/ru…), kiểm tra **nhập số** (bàn phím, dấu thập phân locale, parse lại đúng). Đơn vị mặc định theo vùng (km/mi, kg/lb, cm/ft-in) khi onboarding.
- [ ] **L10 · P1 · Dev** — **RTL** (ar, fa): `Directionality`, đảo icon mũi tên/chevron/back, padding `EdgeInsetsDirectional`, biểu đồ và timeline, thanh tiến độ, chữ số (Latin hay Ả Rập — chốt với Product), bàn phím số. Kiểm tra tất cả màn.
- [ ] **L11 · P1 · Dev/Design** — **Font** theo chữ viết: Inter không có Ả Rập/CJK/Devanagari/Thai → khai fallback (Noto Sans Arabic/CJK/Thai…) hoặc font hệ thống; kiểm tra **chiều cao dòng** và `tabular numerals` (số timer/pace không nhảy bề rộng).
- [ ] **L12 · P1 · Dev** — Chuỗi **chưa vào key vì cố ý**, cần quyết định lại: `STRIDE` (thương hiệu — giữ), `© OpenStreetMap contributors` (attribution), mẫu `DateFormat` (xem L08), thông báo lỗi thô từ Firebase (`ApiException.message`, `error.message` từ server) — nên **map mã lỗi Firebase → key đã dịch** thay vì hiện chuỗi gốc tiếng Anh, `buildDiagnostics` (nội dung kèm phản hồi, giữ tiếng Anh cho đội hỗ trợ).
- [ ] **L13 · P1 · Dev** — Chuỗi **ghép từ nhiều mảnh** vẫn có thể sai ngữ pháp ở ngôn ngữ khác (ví dụ ghép danh từ + đơn vị + khoảng thời gian trong `progress_data.dart`, tiêu đề hoạt động theo buổi trong ngày). Rà soát và chuyển thành câu đầy đủ có placeholder.
- [ ] **L14 · P1 · Dev** — Thông báo hệ thống (**notification**, tên/mô tả kênh Android, nội dung nhắc nhở) dịch theo ngôn ngữ **tại thời điểm hiển thị**, kể cả khi lên lịch trước rồi đổi ngôn ngữ (xem `reminder_scheduler.dart`; nên lên lịch lại khi đổi ngôn ngữ).
- [ ] **L15 · P1 · Dev** — Thành phần **native** cần dịch: tên app theo ngôn ngữ (`android/app/src/main/res/values-xx/strings.xml`, `app_name`), mô tả quyền (iOS `InfoPlist.strings`: vị trí, chuyển động, Bluetooth, ảnh), splash.
- [ ] **L16 · P1 · Product** — **Hồ sơ cửa hàng** đã dịch (tên, mô tả ngắn/dài, ảnh chụp, từ khóa) cho từng ngôn ngữ phát hành; trang chính sách quyền riêng tư đa ngôn ngữ.
- [ ] **L17 · P1 · Dev** — Script kiểm tra **chuỗi cứng còn sót** chạy trong CI (quét `Text('…')`, `label:`, `title:`, `hintText:`… không đi kèm `.tr`) để không tái phát. Có thể dựa trên `test/core/strings_xml_test.dart`.
- [ ] **L18 · P2 · Dev** — Đồng bộ **bộ chuỗi chung** với smart_drink (các từ như Cancel/OK/Retry) về `asc_common` nếu hai app dùng chung thuật ngữ; đồng bộ cơ chế dịch (`translate.py`).

---

## 7. Animation và chuyển động
**Hiện trạng:** token đã có (`StrideMotion` trong `values/tokens.dart`: press 100 ms · state 180 ms · sheet 240 ms · screen 250 ms) nhưng **hầu như chưa dùng**. Có sẵn rải rác: vòng đếm ngược (`countdown_screen.dart`), tiến trình nút giữ (`buttons.dart` `HoldButton`), `AnimatedContainer` ở `selectors.dart` và onboarding. Chế độ **giảm chuyển động** (`MediaQuery.disableAnimations`) mới xử lý ở onboarding. `StaggerReveal` của asc_common chưa dùng.

### 7.1 Quy tắc chung (theo Design System mục 08)
- [ ] **M01 · P0** — Một **wrapper toàn cục** đọc `MediaQuery.disableAnimations` (và `AccessibilityFeatures`) để: rút thời lượng về 0 hoặc crossfade nhẹ, tắt confetti/pulse lặp, **không** làm thay đổi dữ liệu (timer, route vẫn cập nhật). Dùng một helper `StrideMotion.of(context)` trả thời lượng đã tính giảm chuyển động.
- [ ] **M02 · P0** — Thời lượng và kiểu: press 100 ms (không scale chữ, không làm nút nhảy vị trí) · chuyển trạng thái 180 ms (opacity/màu, tránh nhấp nháy) · sheet 240 ms (đi từ đáy, không tràn safe area) · màn hình 250 ms (dùng transition nền tảng). Đường cong chuẩn `Curves.easeOut`/`easeInOutCubic`; **không bounce** ở màn đang chạy.
- [ ] **M03 · P0** — **Không phụ thuộc animation để tính thời gian thật** (timer dùng đồng hồ đơn điệu, không dùng `AnimationController`).
- [ ] **M04 · P1** — **Skeleton** cho khối đã biết kích thước (Home, History, Progress, Activity detail); **spinner** chỉ cho tác vụ. Không nháy số 0 khi dữ liệu chưa tải; giữ bề rộng control khi loading.
- [ ] **M05 · P1** — Kiểm tra hiệu năng: 60/120 fps trên máy tầm trung, không `setState` toàn màn mỗi 500 ms ngoài vùng cần (màn ghi chạy đang dựng lại cả màn mỗi 500 ms — cân nhắc tách `ValueListenable`/`Consumer` hẹp).
- [ ] **M06 · P1** — Test tự động: widget test với `disableAnimations: true`; golden test cho các trạng thái chính.

### 7.2 Danh sách animation cần làm theo màn
| Màn / thành phần | Animation đề xuất | Ghi chú / lưu ý |
|---|---|---|
| Startup (splash) | Logo fade + scale nhẹ 250 ms, chuyển sang màn kế bằng crossfade | Không giữ lâu: chỉ đọc dữ liệu cục bộ (offline-first) |
| Onboarding (3 trang) | Trượt ngang + dot indicator co giãn, ảnh parallax nhẹ | Đã có dot; thêm giảm chuyển động |
| Chuyển tab (5 tab) | Crossfade 180 ms; icon tab đổi màu/đậm | Giữ trạng thái từng tab (đã có `StatefulShellRoute`) |
| Home — vòng bước | Vòng tiến độ **chạy từ giá trị cũ → mới** (không nhảy), số bước đếm lên (tween, số tabular) | Vượt 100% chỉ vòng dừng, số vẫn tăng |
| Home — biểu đồ giờ | Cột mọc lên (stagger ngắn); chạm cột hiện tooltip | Có danh sách thay thế cho screen reader |
| Home — đạt mục tiêu | Hiệu ứng chúc mừng **một lần**, không chặn thao tác, tắt khi giảm chuyển động | Tránh lặp confetti |
| Danh sách (History, Notifications, Clubs) | Mục vào lần lượt (stagger ≤ 40 ms/mục, tối đa ~8 mục), kéo-để-tải-lại, trượt xóa | Không animate khi tải thêm trang |
| Run prepare | Chip GPS đổi trạng thái (màu/nhãn 180 ms); bản đồ xem trước fade-in khi có tile | |
| Countdown 3-2-1 | Vòng đếm + số phóng nhẹ + rung (đã có vòng và rung) | Hủy bằng Back/nút (đã có); giảm chuyển động: chỉ đổi số |
| Live run — chỉ số | Số đổi **không nháy**, cố định bề rộng; pace `—` → giá trị mượt | Tabular numerals |
| Live run — nút Pause/Resume | Biểu tượng đổi (morph/crossfade 180 ms), nút ≥ 64 | Không dịch chuyển bố cục |
| Live run — **nhấn giữ để kết thúc** | Vòng/thanh tiến trình 800 ms, thả ra thì lùi lại | Đã có `HoldButton`; thêm haptic bắt đầu/hoàn thành |
| Live run — khóa màn hình | Lớp khóa fade 180 ms; "Giữ để mở khóa" có tiến trình | |
| Live run — bản đồ | Chấm vị trí có **halo/pulse nhẹ**, camera đi theo mượt, marker mốc km "pop" 1 lần, đường chạy vẽ liền mạch | Pulse tắt khi giảm chuyển động |
| Live run — chuyển Số liệu ↔ Bản đồ | Vuốt ngang `PageView` + segmented trượt | Đã có PageView |
| Live run — GPS yếu/mất | Banner trượt vào/ra 180 ms | Không làm giật bản đồ |
| Paused view | Huy hiệu "Đã tạm dừng" fade-in; hộp thoại kết thúc 240 ms | |
| Results | Số liệu đếm lên khi vào; đường chạy **vẽ dần** trên bản đồ (250–600 ms), cờ đích rơi vào; cúp xuất hiện | Bản đồ phải căn khớp ngay lần dựng đầu (đã sửa) |
| Save → Saved | Dấu tích "đã lưu" vẽ nét + nhãn "Waiting to sync"; không báo Synced khi chưa xác nhận | |
| Recovery | Huy hiệu khôi phục; nút bấm có loading giữ bề rộng | |
| History — lịch tháng | Đổi tháng trượt ngang; ngày được chọn phóng nhẹ | |
| Activity detail | **Hero** thẻ → chi tiết; biểu đồ vẽ dần; bản đồ fade-in; chia sẻ ảnh xem trước | |
| Progress | Chuyển Tuần/Tháng/Năm: biểu đồ biến đổi (fl_chart `duration`), thanh tóm tắt đếm lên | Giữ khung, không nhảy bố cục |
| Records | Huy hiệu kỷ lục "lấp lánh" 1 lần khi mới đạt | |
| Goals | Thanh trượt/preset chip đổi mượt; lưu xong có xác nhận | |
| Reminders | Công tắc (`AppSwitch`) trượt; thêm/xóa mục có animation | |
| Profile / Settings | Mục mở rộng/thu gọn; công tắc | |
| Explore (clubs, challenges, routes) | Bảng xếp hạng vào lần lượt; tham gia → nút đổi trạng thái; cheer (❤) bật nảy 1 lần | |
| Dialog / Bottom sheet / Snackbar | Sheet 240 ms từ đáy, dialog fade+scale 180 ms, snackbar trượt lên (giữ trên cùng nút) | Trả focus về control mở sheet khi đóng |
| Nút bấm chung | Pressed đổi sang `primaryPressed` 100 ms, **không** đổ bóng mạnh, không dịch vị trí | Xem mục 8 |
| Bộ chọn (segmented, chip, toggle) | Thanh chọn trượt, màu đổi 180 ms | Đã có `AnimatedContainer` ở `selectors.dart` |
| Màn lỗi/rỗng/quyền | Icon fade-in nhẹ, CTA rõ | Không gây chú ý quá mức |

---

## 8. Điểm chạm, phản hồi khi bấm và truy cập
**Hiện trạng:** Design System quy định vùng chạm ≥ 48×48, trạng thái default/pressed/focus/disabled/loading, nút Pause ≥ 64, giữ 800 ms để kết thúc. **Haptic mới có 4 chỗ** (`HoldButton` hoàn thành → `mediumImpact`; nhịp đếm ngược → `selectionClick`; kết thúc đếm ngược → `heavyImpact`; `_haptic()` trong engine ghi chạy → `heavyImpact`). Chưa có test tự động kiểm tra kích thước vùng chạm hay nhãn truy cập.

### 8.1 Quy tắc chung (Design System)
- [ ] **T01 · P0** — **Vùng chạm tối thiểu 48×48** cho mọi control (icon 24 + vùng chạm 48; chip cao vẽ 32–36 nhưng hit area 48; công tắc track 52×32 nhưng vùng chạm 48; cột biểu đồ mở rộng ≥ 24 ngang). Thêm **test tự động** `meetsGuideline(androidTapTargetGuideline)` + `iOSTapTargetGuideline` cho từng màn chính.
- [ ] **T02 · P0** — Trạng thái nút đủ: **default, pressed, focus, loading, disabled**. Pressed dùng `primaryPressed` (không đổ bóng mạnh), focus có viền primary 2 + cách 2 (nền primary dùng vòng tương phản kép), **loading giữ bề rộng nút và chặn gửi lặp** (đã có `OnceGuard`), disabled dùng màu disabled có tương phản đủ. Rà `buttons.dart`, `selectors.dart`, `cards.dart`.
- [ ] **T03 · P0** — **Ripple/hiệu ứng chạm** đồng nhất: mọi vùng bấm được phải có phản hồi thị giác (InkWell/`Material`), thẻ bấm được có trạng thái pressed. `GestureDetector` (không có phản hồi mặc định) hiện chỉ còn 4 chỗ — kiểm tra từng chỗ có tự vẽ trạng thái pressed chưa: `share_activity_screen.dart:242`, `buttons.dart:180` (HoldButton), `register_screen.dart:123`, `selectors.dart:29`. Còn lại dùng `InkWell`/`Material` — vẫn cần xác nhận bằng mắt trên máy thật.
- [ ] **T04 · P0** — **Chống bấm đúp/bấm lặp** cho mọi hành động có tác dụng phụ (lưu, xóa, đăng xuất, bắt đầu chạy, tham gia câu lạc bộ, gửi phản hồi). Dùng `OnceGuard` hoặc disable khi loading; test bấm hai lần liên tiếp.
- [ ] **T05 · P0** — **Chiến lược haptic thống nhất** (một `StrideHaptics` bọc `HapticFeedback`, tôn trọng cài đặt rung của người dùng và hệ thống):

  | Sự kiện | Haptic gợi ý |
  |---|---|
  | Bấm tab, chip, segmented, công tắc | `selectionClick` |
  | Bắt đầu chạy / Resume / Pause | `lightImpact` (Pause: `mediumImpact`) |
  | Nhấn giữ để kết thúc: bắt đầu giữ / hoàn thành | `selectionClick` / `heavyImpact` |
  | Nhịp đếm ngược / bắt đầu | `selectionClick` / `heavyImpact` (đã có) |
  | Đạt mốc km, đạt mục tiêu, kỷ lục mới | `mediumImpact` (rung mẫu riêng trên Android nếu có) |
  | Lưu thành công | `lightImpact` |
  | Lỗi / bị chặn | `vibrate`/`heavyImpact` + thông báo chữ |
  | Cảnh báo GPS mất / pin yếu | rung ngắn, **luôn kèm chữ** |

- [ ] **T06 · P0** — **Cài đặt rung và âm thanh** có thể tắt trong Hồ sơ → Cài đặt chạy; mọi âm thanh/rung đều có trạng thái chữ tương ứng (Design System: không bắt buộc phát âm thanh).
- [ ] **T07 · P0** — **Nút Back và cử chỉ vuốt** theo từng trạng thái ghi chạy (đã sửa: tạm dừng + Back mở hộp thoại kết thúc; đang ghi + Back chỉ nhắc; khóa màn hình bỏ qua Back; countdown Back = hủy; recovery Back nhắc chọn). **Rà toàn bộ app còn màn nào kẹt**: màn có `showBack: false`/`PopScope(canPop: false)` luôn phải có một lối ra rõ ràng bằng nút trên màn (không chỉ dựa vào Back). Viết test Back cho từng màn đó.
- [ ] **T08 · P1** — **Tên truy cập (Semantics)** cho mọi control: nút chỉ có icon, thẻ, biểu đồ (có danh sách thay thế), vòng tiến độ, bản đồ ("Run map"), tab ("Home tab"). Nội dung đã qua `.tr` — kiểm tra bản dịch có nghĩa khi đọc riêng. Kiểm thử bằng **TalkBack** và **VoiceOver**.
- [ ] **T09 · P1** — **Thứ tự focus** theo thứ tự đọc; sheet/dialog giữ focus bên trong và trả focus về control mở khi đóng. Hỗ trợ bàn phím ngoài/D-pad (Tab, Enter, Esc).
- [ ] **T10 · P1** — **Cỡ chữ hệ thống 200%** và cỡ hiển thị lớn: không tràn, không che nút, body không nhỏ hơn 16, nút vẫn ≥ 48. Test với `textScaler`.
- [ ] **T11 · P1** — **Tương phản màu** đạt WCAG AA (đặc biệt chữ `muted` #68776E trên canvas, chữ warning trên nền warning, chữ trắng trên lime). Không chỉ dùng màu để báo trạng thái (lỗi/đạt) — kèm icon/chữ.
- [ ] **T12 · P1** — **Xung đột cử chỉ**: bản đồ (kéo/zoom) bên trong màn cuộn, `PageView` ngang trong màn chạy, vuốt từ mép để Back (gesture navigation Android 10+), kéo-để-tải-lại. Kiểm tra trên máy dùng gesture navigation và 3 nút.
- [ ] **T13 · P1** — **Bàn phím**: không che trường nhập (Edit profile, Save activity ghi chú, đăng nhập/đăng ký), `textInputAction` hợp lý, loại bàn phím đúng (số cho cân nặng/chiều cao/mục tiêu), tôn trọng dấu thập phân của locale, trường mật khẩu có hiện/ẩn và nhãn mô tả.
- [ ] **T14 · P1** — **Nhấn giữ/long-press có gợi ý**: nút "Giữ để kết thúc/mở khóa" cần chỉ dẫn rõ (văn bản + tiến trình) và phương án thay thế cho người dùng không thể giữ (xác nhận bằng hộp thoại — đã có khi dùng Back).
- [ ] **T15 · P1** — **Thiết bị khác**: tablet/gập (bố cục hai cột hoặc giới hạn bề rộng nội dung), cạnh cong/đục lỗ (safe area), xoay ngang (chốt: khóa dọc hay hỗ trợ), nút điều hướng 3 nút che nút dưới cùng (đã dùng `SafeArea`).

### 8.2 Kiểm tra chạm theo màn (điền khi làm)
| Màn | Điểm chạm quan trọng cần kiểm | Trạng thái |
|---|---|---|
| Startup | Nút thử lại khi lỗi; không có vùng chạm chết | [ ] |
| Onboarding | Tiếp/Bỏ qua/Bắt đầu ≥ 48; vuốt trang; dot không bắt buộc bấm | [ ] |
| Welcome / Login / Register / Forgot / Verify email | Trường nhập, hiện/ẩn mật khẩu, Google, liên kết; chống bấm đúp | [ ] |
| Merge guest | Hai lựa chọn rõ; loading; không mất dữ liệu | [ ] |
| Setup (hồ sơ/mục tiêu/quyền) | Bộ chọn đơn vị, bước tăng/giảm số, nút cấp quyền → Cài đặt | [ ] |
| Home | Vòng bước, thẻ, "Xem chi tiết", chuông thông báo, avatar, ngày trong tuần | [ ] |
| Daily steps | Cột biểu đồ (mở rộng vùng chạm), đổi ngày, nguồn | [ ] |
| Goals | Preset chip, nhập số, lưu | [ ] |
| Notifications | Từng mục, xóa/đánh dấu đã đọc | [ ] |
| Progress / Records | Chọn kỳ (tuần/tháng/năm), bộ chọn tháng, mở danh sách hoạt động, thẻ kỷ lục | [ ] |
| History | Lọc, lịch tháng, mục hoạt động, tải thêm, trượt xóa | [ ] |
| Activity detail | Bản đồ (zoom/kéo trong màn cuộn), biểu đồ, Sửa, Chia sẻ, Xóa (xác nhận), xuất CSV/GPX | [ ] |
| Run prepare | Chọn loại hoạt động, mục tiêu, giáo án, âm thanh, live-share, nút Bắt đầu | [ ] |
| Countdown | Hủy bằng nút và Back | [ ] |
| Live run | Pause ≥ 64, Khóa, đổi tab Số liệu/Bản đồ, recenter, giữ để kết thúc, Back từng trạng thái | [ ] |
| Results / Save / Saved | Lưu, Hủy bỏ (xác nhận), thêm ảnh, quyền riêng tư, nút quay lại | [ ] |
| Recovery | Tiếp tục đoạn mới / Kết thúc & lưu / Hủy bỏ; Back nhắc | [ ] |
| Profile và các màn con | Chỉnh sửa, đơn vị, nguồn dữ liệu, thiết bị (quét/kết nối/quên), nhắc nhở, quyền riêng tư, tài khoản, trợ giúp | [ ] |
| Explore | Câu lạc bộ (tham gia, đăng bài, bình luận, cheer, chặn, báo cáo), thử thách, tuyến | [ ] |
| Live share | Chọn người xem, thời hạn, xác nhận, dừng | [ ] |

---

## 9. Chất lượng, kiểm thử và hiệu năng
- [ ] **Q01 · P0** — **Test tích hợp trên thiết bị** (`integration_test`) cho luồng chính: onboarding → chạy → tạm dừng → kết thúc → lưu → xem lịch sử; khôi phục sau khi kill app.
- [ ] **Q02 · P1** — **Golden test** cho các màn chính ở en/vi, cỡ chữ 100%/200%, sáng; (sau này RTL).
- [ ] **Q03 · P1** — Test **migration SQLite**: nâng từ mọi phiên bản schema cũ lên mới, giữ dữ liệu.
- [ ] **Q04 · P1** — Test **đồng bộ**: hai thiết bị, xung đột revision, mất mạng giữa chừng, outbox lặp (có `sync_service_test`, cần thêm với Firestore emulator).
- [ ] **Q05 · P1** — **Phân tích hiệu năng**: DevTools (frame, memory) trên màn chạy 1 giờ; kích thước APK (hiện assets `assets/images/` nạp cả thư mục — kiểm tra ảnh thừa, nén WebP).
- [ ] **Q06 · P1** — **Analytics**: viết `docs/analytics_spec.md` (danh sách event, tham số, màn hình, mục đích) như smart_drink; xác nhận không đưa id/tọa độ; kiểm chứng event lên DebugView. Đã sửa: `app_background` là tên dành riêng nên đổi `stride_background`/`stride_foreground`.
- [ ] **Q07 · P1** — **Chính sách quyền riêng tư** nhất quán với hành vi thật: chỉ ghi GPS khi người dùng bắt đầu, dữ liệu vị trí lên Firestore chỉ khi đồng bộ/live-share, quyền Bluetooth, ảnh.
- [ ] **Q08 · P1** — Bảo mật: rà `firestore.rules` (mục FB03), không lưu token vào Firestore/log (`StrideLog` đã che), kiểm tra `android:allowBackup`, `network_security_config`, obfuscate (`--obfuscate --split-debug-info`) cho bản release và lưu symbols.
- [ ] **Q09 · P2** — Đo độ phủ test (`flutter test --coverage`), đặt ngưỡng cho `controller/`, `repository/`, `utils/calc/`.

---

## 10. Phát hành (R01–R05)
- [ ] **R01 · P0 · Product/Dev** — Hồ sơ cửa hàng: tên, mô tả, ảnh chụp (theo từng ngôn ngữ), biểu tượng 512, ảnh đồ họa, danh mục, độ tuổi, **Data safety (Play)** / **Privacy nutrition label (App Store)**, giải trình quyền (**vị trí nền**, nhận diện hoạt động, thông báo, Bluetooth, camera/ảnh), URL chính sách quyền riêng tư và xóa tài khoản. Tham khảo `D:\smart_drink\docs\store_listing.md`.
- [ ] **R02 · P0 · Dev** — **Release candidate**: khóa ký phát hành (`android/debug_keystore.properties` → `productKeyPath`; **không** dùng khóa debug), `versionCode/versionName` qua `build.py`, build `python tool/build_aab.py`, bật Play App Signing, kiểm tra bản `product` không còn banner "DEV"/nhãn môi trường, AdMob ID thật chỉ khi bật quảng cáo.
- [ ] **R03 · P0 · Dev/Product** — Phát hành **có kiểm soát**: nội bộ → kín (closed testing) → mở → staged rollout (5% → 20% → 100%), cờ tính năng để tắt nhanh, kế hoạch rollback.
- [ ] **R04 · P0 · Dev** — **Theo dõi sau release**: crash-free rate, ANR, lỗi đồng bộ, đánh giá cửa hàng, chi phí Firestore, phản hồi người dùng (`feedback` collection); lịch hotfix.
- [ ] **R05 · P0 · Product** — **Chốt hoàn thành** toàn bộ phạm vi: rà lại checklist gốc `STRIDE_Todo_Code_End_to_End.docx`, mọi P0 xong có bằng chứng, các P1 còn tắt thì ẩn hoàn toàn (không nút giả).
- [ ] **R06 · P1 · Dev** — iOS: máy macOS/CI macOS, scheme + flavor, signing, `Info.plist` mô tả quyền (đã dịch), Background Modes (location), TestFlight.
- [ ] **R07 · P1 · Dev** — CI phát hành: workflow build AAB/IPA khi gắn tag, đẩy lên Firebase App Distribution/Play (secret trong CI, không trong repo). Hiện `build.py` chạy cục bộ.

---

## 11. Rủi ro và quyết định còn mở (cần người có thẩm quyền chốt)
0. **Tính năng nhóm/chuỗi/đội/giải thưởng** (mục 4B): 8 câu hỏi Product ở TM00, đặc biệt **có chấp nhận Cloud Functions hay không** và **có giải thưởng thật hay không** (kéo theo pháp lý).
1. **Nhà cung cấp bản đồ production và ngân sách** (MAP01).
2. **Danh sách ngôn ngữ phát hành đợt đầu** và thứ tự (L01).
3. **Có dùng quảng cáo không** (hiện không; nếu có phải bật UMP/GDPR và AdMob ID thật, xem `docs/adr/0002-shared-base.md`).
4. **Có giữ Riverpod + go_router hay chuyển GetX như smart_drink** (hiện giữ; GetX chỉ là hạ tầng của base).
5. Công thức calo, tiêu chí kỷ lục, chính sách giữ dữ liệu, thiết bị test thật (`docs/scope.md`).
6. Landscape: khóa dọc hay hỗ trợ.
7. Chữ số hiển thị cho ar/fa (Latin hay bản địa).

---

## 12. Định nghĩa "xong" cho mỗi việc
- Code đã review, có test (hoặc ghi rõ vì sao không test được), `flutter analyze` không thêm cảnh báo.
- Có đủ trạng thái: rỗng, đang tải, lỗi, thiếu quyền, offline.
- Chuỗi UI qua key (en + vi tối thiểu), không chữ cứng; chạy `flutter test`.
- Vùng chạm ≥ 48, có nhãn truy cập, hoạt động với giảm chuyển động và cỡ chữ 200%.
- Đã thử trên **thiết bị thật** với việc liên quan nền/GPS/cảm biến/quyền; ảnh hoặc video đính kèm PR.
- Không có secret trong diff.

## 13. Tham chiếu nhanh
| Cần gì | Ở đâu |
|---|---|
| Quy ước dự án, cấu trúc thư mục | `CLAUDE.md` |
| Build, flavor, tile, biến môi trường | `docs/build.md` |
| Quyết định kỹ thuật | `docs/adr/0001-stack.md`, `docs/adr/0002-shared-base.md` |
| Schema Firestore, rules, indexes | `docs/firestore-schema.md`, `firestore.rules`, `firestore.indexes.json` |
| Phạm vi và cờ tính năng | `docs/scope.md`, `mobile/lib/configs/env.dart` |
| Design System (màu, chữ, vùng chạm, chuyển động) | `STRIDE_Design_System_v1.docx` |
| Luồng nghiệp vụ | `Full_luong_app_dem_buoc_chan_chay_bo.docx` |
| Checklist gốc (92 việc) | `STRIDE_Todo_Code_End_to_End.docx` |
| Chuỗi đa ngôn ngữ | `mobile/lib/xml_strings/`, `mobile/tool/translate.py` |
| Token chuyển động / màu | `mobile/lib/values/tokens.dart` |
| Test chuỗi | `mobile/test/core/strings_xml_test.dart` |
| Chạy app trên máy | `flutter run --flavor dev` (xem `docs/build.md`) |
