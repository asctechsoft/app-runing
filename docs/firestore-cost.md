# Ước lượng tải và chi phí Firestore (TM63)

Nguồn: code ở `mobile/lib/repository/`, `mobile/lib/services/application/sync_*.dart`, rules ở `firestore.rules`.
Giá mỗi lượt đọc/ghi lấy theo bảng giá hiện hành của Firebase (gói Blaze, có hạn mức miễn phí theo ngày). Tài liệu này
**chỉ đếm số thao tác** để nhân với bảng giá lúc tính ngân sách (FB06). Giá không được ghi cứng ở đây vì thay đổi theo
vùng và theo thời gian.

## Giả định (sửa khi có số liệu thật từ Analytics/Console)
| Tham số | Giá trị | Ghi chú |
|---|---|---|
| Người dùng hoạt động mỗi ngày (DAU) | 10.000 | Mục tiêu trong TM63 |
| Lần mở app/người/ngày | 3 | Home `_kick` mỗi lần mở/quay lại |
| Buổi chạy/người/ngày | 0,5 | Có GPS, ~45 phút → ~2.700 điểm → 6 chunk track (500 điểm/chunk) |
| Người có tài khoản (đồng bộ) | 60% | Khách không đọc/ghi Firestore |
| Người dùng tính năng nhóm | 30% | Ở trung bình 1 club, bật chia sẻ tiến độ 1 club |
| Lần xem feed club/người nhóm/ngày | 2 | Trang 20 bài |

## Thao tác theo luồng (mỗi lần)
| Luồng | Đọc | Ghi | Ghi chú |
|---|---|---|---|
| Đồng bộ một hoạt động có GPS | 0–1 | 1 summary + N chunk | Idempotent theo id; chunk theo sha256 nên gửi lại không nhân đôi |
| Kéo về theo cursor `serverUpdatedAt` | số document đổi | 0 | Không đổi → 0 document (vẫn tính 1 lượt đọc tối thiểu/query) |
| Mở app: đẩy số liệu nhóm (TM21/22) | 0 | 1 / club đang chia sẻ | `memberStats/{uid}`, ghi đè cả document |
| Mở app: lịch nhắc sự kiện (TM05) | 1 query + 1 / sự kiện đã đăng ký | 0 | Giới hạn `maxEventRsvpsRead` = 50 |
| Mở app: huy hiệu thử thách (TM40) | 1 + 2 / thử thách đã tham gia | 0 | Giới hạn `maxChallengeJoinsRead` = 100 |
| Trang feed club | 20 bài + 20 cheer của tôi + danh sách chặn | 0 | N+1 cheer: cân nhắc gom vào `users/{uid}/cheers` nếu chi phí cao |
| Tab Group | ≤ 200 `memberStats` | 0 | Mỗi document ≤ 62 ngày (< 10 KB) |
| Bảng xếp hạng thử thách | 50 + 2 `count()` | 0 | Aggregate `count()` tính theo lô 1.000 index entry |
| Tham gia/rời thử thách, RSVP | 2–3 | 2–3 | Transaction tăng/giảm bộ đếm |

## Ước lượng mỗi ngày (10.000 DAU)
| Hạng mục | Đọc/ngày | Ghi/ngày |
|---|---|---|
| Đồng bộ hoạt động (6.000 tài khoản × 0,5 buổi × 7 ghi) | ~6.000 | ~21.000 |
| Kéo về khi mở app (6.000 × 3 lần, đa số không đổi) | ~18.000 | 0 |
| Số liệu nhóm khi mở app (1.800 người × 3) | 0 | ~5.400 |
| Feed (1.800 × 2 × ~45) | ~162.000 | 0 |
| Tab Group / bảng xếp hạng / sự kiện (ước lượng) | ~100.000 | ~2.000 |
| **Tổng** | **~290.000** | **~28.000** |

Nặng nhất là **feed** (N+1 cheer) và **tab Group**. Nếu vượt ngân sách thì tối ưu theo thứ tự:
1. Bỏ đọc cheer từng bài, chuyển sang một danh sách cheer của tôi.
2. Ghi số liệu nhóm tối đa 1 lần/giờ, thay vì mỗi lần mở app.
3. Cache feed cục bộ.

## Hot document / bộ đếm
- `clubs/{id}.memberCount`, `challenges/{id}.participantCount` và `events/{id}.goingCount` tăng bằng transaction từ client
  (`counterStep` trong rules). Firestore chịu được khoảng 1 lần ghi/giây trên mỗi document. Club/thử thách vài trăm người thì đủ;
  sự kiện mở đăng ký cho hàng nghìn người cùng lúc thì transaction sẽ phải thử lại.
- Bộ đếm chia nhỏ (sharded counter) cần tổng hợp bằng server. Theo ADR 0003 chưa dùng Cloud Functions, nên **chưa làm**. Khi có
  Functions (TM51), chuyển các bộ đếm này sang Functions.
- Số liệu nhóm và bảng xếp hạng không ghi vào một document chung: mỗi người ghi document của mình, nên không có hot document.

## Phân trang và giới hạn (đã rà 2026-10-27)
- Mọi query danh sách trong `explore_repository.dart` đều có `limit`:
  - feed, sự kiện, tìm club: `_scan`, tối đa 5 lô × 20;
  - thành viên: 50/trang;
  - bảng xếp hạng: 50;
  - thử thách: 50;
  - tiến độ đội: 500/đội;
  - `memberStats`: 200;
  - danh sách chặn: 500;
  - club của tôi: 100;
  - `eventRsvps`: 50;
  - `challengeJoins`: 100.
- Ngoại lệ có chủ đích là **xuất dữ liệu / xóa tài khoản** (`account_repository.dart`): đọc toàn bộ dữ liệu của chính người
  dùng, chỉ chạy khi người dùng bấm.
- Index composite nằm trong `firestore.indexes.json`. Mỗi query có `where` + `orderBy` đều có index tương ứng: posts, events,
  comments, members, participants, challenges theo `clubId`.

## Việc còn lại
- Đo thật trên Console (Usage) sau khi phát hành nội bộ, so với bảng trên (R04, FB06).
- Đặt cảnh báo ngân sách (FB06) và App Check enforce (FB07) để chặn client giả gọi Firestore.
