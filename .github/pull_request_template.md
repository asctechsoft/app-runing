## Checklist ID
<!-- vd. G03, G04 — theo STRIDE_Todo_Code_End_to_End.docx -->

## Thay đổi
-

## Kiểm chứng
- [ ] `flutter analyze` / `flutter test` (mobile) pass; đổi schema Firestore thì đã cập nhật `firestore.rules`, `firestore.indexes.json` và `docs/firestore-schema.md`
- [ ] Đã xử lý empty / loading / error / permission state liên quan
- [ ] Không nút giả, không báo thành công khi chưa có xác nhận
- [ ] Không log token, mật khẩu, tọa độ
- [ ] Bằng chứng chạy thật (ảnh/video/log đã che dữ liệu) nếu liên quan GPS/cảm biến

## Ghi chú cho reviewer
