# ADR 0003 — Tính năng nhóm: phạm vi và quy tắc (TM00, TM23)

- Trạng thái: Đã chốt (2026-10-27), Product trả lời 8 câu hỏi TM00 trong `docs/checklist-con-lai.md`.
- Phạm vi: mục 4B của checklist (TM01…TM75). Không đổi stack của ADR 0001/0002.

## Quyết định
| # | Câu hỏi | Chốt |
|---|---|---|
| 1 | "Nhóm" là gì | **Cả hai**: giữ *Club* (cộng đồng, nhiều người) và thêm *Đội* (team) bên trong thử thách. |
| 2 | Ngày đạt chuỗi | Đạt **một trong hai**: mục tiêu bước của ngày, **hoặc** một buổi `run`/`walk` hợp lệ ≥ **1 km hoặc ≥ 10 phút** di chuyển. |
| 2 | Bảo lưu (freeze) | Có: **2 ngày/tháng**, không dồn sang tháng sau. Ngày bảo lưu giữ chuỗi nhưng không cộng số ngày. |
| 2 | Chuỗi nhóm | Nhóm giữ chuỗi khi **tất cả** thành viên đạt trong ngày. |
| 3 | Điểm thi đội | **Trung bình mỗi người** (tổng km hợp lệ ÷ số thành viên của đội), để đội khác quân số vẫn công bằng. |
| 3 | Đổi đội | **Được** đổi đội giữa kỳ. |
| 4 | Giải thưởng | **Chỉ huy hiệu/danh hiệu số.** Không có quà, voucher hay tiền thật → TM42 không làm. |
| 5 | Hoạt động được tính | `run` và `walk` **có GPS thật**. `indoorRun` (quãng đường ước lượng từ bước) **không tính** cho chuỗi nhóm, mục tiêu nhóm, điểm hay bảng xếp hạng. |
| 5 | Hoạt động riêng tư | Tạm thời hoạt động `onlyMe` **không** đóng góp số liệu cho nhóm. |
| 6 | Chống gian lận | Chỉ hoạt động có GPS thật; **chặn tốc độ bất hợp lý** (đi xe); **chặn vị trí giả** (`isMocked`); **trưởng nhóm** xử lý khiếu nại. |
| 7 | Cloud Functions | **Chưa dùng.** Số liệu nhóm do client tính và ghi (TM23 = phương án a). |
| 8 | Chat nhóm | **Chưa làm** (TM07 hoãn). Dùng bài đăng + bình luận có sẵn. |

Ghi chú về chuỗi cá nhân (TM20): bước chân đếm cả ngày nên ngày đạt mục tiêu bước vẫn tính cho chuỗi cá nhân.
Quy tắc "chỉ GPS thật" ở câu 5–6 áp dụng cho phần **hoạt động** đóng góp vào nhóm và thử thách.

## Hệ quả
- **Tin cậy client (TM23 = a):** `progressValue`, điểm đội và chuỗi nhóm do app ghi lên Firestore. `firestore.rules` chỉ chặn
  được ghi thay người khác và giá trị sai kiểu/ngoài khoảng; không chặn được người sửa app để gửi số giả. Chấp nhận ở giai
  đoạn này vì giải thưởng chỉ là huy hiệu số. Trưởng nhóm có quyền gỡ kết quả khi có khiếu nại.
- **Không có push theo sự kiện** (bị vượt hạng, bạn vừa chạy xong…): cần server. Chỉ dùng thông báo cục bộ và hộp thư trong
  app; TM34/TM11 làm phần cục bộ, phần push chờ khi có Functions.
- **Bộ đếm** `memberCount`/`participantCount` vẫn ghi từ client (transaction); nhóm lớn có thể tranh chấp ghi — chấp nhận
  vì Club/Đội ở quy mô nhỏ lúc đầu.
- Quy tắc hoạt động hợp lệ (câu 5–6) viết thành hàm thuần có test trong `utils/calc/` (TM24), dùng chung cho chuỗi, mục tiêu,
  thử thách và đội.
- TM42 (giải thật), TM51 (Functions), TM07 (chat) đóng ở trạng thái "không làm theo ADR 0003" cho đến khi có ADR mới.

## Chưa chốt — dùng mặc định dưới đây, Product sửa nếu khác
- Giới hạn: Club tối đa 500 thành viên; Đội 2–30 người; mỗi người tham gia tối đa 10 club.
- Ai được tạo Club: mọi tài khoản đã đăng nhập (không cho khách), **tối đa 5 club/người, cách nhau ≥ 1 giờ** (đã áp dụng
  trong `firestore.rules` qua `clubQuota/{uid}`). Đội do owner/admin club hoặc người tạo thử thách lập.
- Giới hạn 500 thành viên/club và 10 club/người **chưa áp dụng** (cần bộ đếm tin cậy — rules không đếm được tài liệu).
- Mã mời (TM03): hạn 7 ngày, 50 lượt; club riêng chỉ owner/admin tạo mã; vào bằng mã thì active ngay (thay bước duyệt).
- Mất chuỗi (sau khi hết ngày bảo lưu): không khôi phục.
- Đổi đội: tối đa 1 lần mỗi thử thách và khóa 48 giờ trước khi kết thúc; điểm cũ ở lại đội cũ.
- Ngưỡng tốc độ bất hợp lý: `run` nhanh hơn 2:30/km hoặc `walk` nhanh hơn 6:00/km trên trung bình cả buổi → không tính.

## Khi nào xem lại
Khi muốn có giải thưởng thật, push theo sự kiện, chống gian lận phía server hoặc nhóm trên vài nghìn người → ADR mới về
Cloud Functions (gói Blaze), mở lại TM51.
