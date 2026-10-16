# CLAUDE.md — STRIDE (app đếm bước chân và chạy bộ)

Repo hiện chỉ chứa tài liệu đặc tả và ảnh UI; **chưa có source code, build hay test**. Khi bắt đầu viết code, cập nhật mục "Lệnh" bên dưới.

## Tài liệu nguồn (đọc trước khi làm)
- `Full_luong_app_dem_buoc_chan_chay_bo.docx` — kịch bản nghiệp vụ, luồng người dùng, yêu cầu chức năng (v1.0).
- `STRIDE_Design_System_v1.docx` — màu, typography, spacing, component, hành vi UI (token HEX/font là baseline).
- `STRIDE_Todo_Code_End_to_End.docx` — checklist triển khai (ID A01…, mức P0/P1/P2, mốc G0–G5).
- `component_reference.png`, `sceam/*.png` — ảnh tham chiếu giao diện (splash, home, progress, history, settings, map). Ảnh render không phải nguồn số đo; số đo lấy từ Design System.

## Nguyên tắc sản phẩm (bắt buộc)
- Đếm bước hằng ngày và ghi buổi chạy là hai nghiệp vụ riêng.
- Chỉ ghi GPS khi người dùng chủ động bắt đầu hoạt động; không theo dõi vị trí cả ngày.
- Hoạt động mặc định riêng tư. Một người chỉ có một phiên đang ghi trên một thiết bị.
- Không giả lập dữ liệu thiếu; calo và quãng đường suy từ bước ghi rõ là "estimated". Pace thiếu dữ liệu hiển thị `—`.
- Không ship nút giả, không tự báo thành công khi chưa có xác nhận. Mọi màn cần empty/loading/error/permission state.
- Hoạt động offline-first: vào app và lưu hoạt động được khi không có mạng.

## Quy ước UI (từ Design System)
- Light theme; màn khóa khi chạy dùng nền tối riêng. Font Inter (fallback font hệ thống theo script).
- Màu chính `#137A4B`, lime `#D6F45B`, canvas `#F8FAF8`, navy logo `#102134`. Luôn dùng token, không hard-code HEX.
- Sentence case; tên tab: Home, Progress, Run, History, Profile. Body tối thiểu 16.
- Số dùng tabular numerals; lưu đơn vị gốc, đổi hiển thị theo cài đặt (km/mi).
- Logo: không kéo giãn/xoay/đổi màu; vùng an toàn tối thiểu 16%.

## Quyết định chưa chốt
Framework mobile, backend, nhà cung cấp bản đồ, auth chưa được chọn. **Không tự giả định Flutter/React Native/native hay gán phiên bản thư viện**; chọn stack qua ADR (task A02) trước khi code.

## Lệnh
Chưa có. Cập nhật mục này (build, test, lint, chạy app) khi stack được chốt.

## Harness / cách làm việc với Claude
- Tài liệu và UI viết tiếng Việt; trả lời và comment nghiệp vụ bằng tiếng Việt, tên code/identifier bằng tiếng Anh.
- Trước khi sửa, đọc file liên quan; thay đổi nhỏ, đúng phạm vi yêu cầu, không refactor ngoài ý muốn.
- Mỗi việc xong cần có kiểm chứng (test hoặc chạy thật) và ghi theo ID checklist (vd. A03) trong commit/PR.
- Không commit secret, key, file `.env`; ảnh/tài liệu lớn nên cân nhắc Git LFS (nhiều ảnh trong `sceam/` >6 MB).
- Hành động khó hoàn tác (push, xóa, force) phải hỏi trước. Remote: `https://github.com/asctechsoft/app-runing.git`, nhánh `main`.
