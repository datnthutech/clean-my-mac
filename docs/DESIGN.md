# Thiết kế giao diện

Mẫu thiết kế chi tiết (6 màn hình, có thể phóng to/thu nhỏ và để lại bình luận):
**https://claude.ai/artifact/SrnoYTUQTpu9VbmCPEiELa**

Ảnh chụp app thật (CI tự chạy app trên macOS 15 và chụp lại sau khi quét):

![Tóm tắt](screenshot-summary.jpg)

## Nguyên tắc

- **Giao diện native macOS**: SwiftUI `NavigationSplitView`, font hệ thống (SF Pro), hỗ trợ Light/Dark mode tự động, phím tắt chuẩn.
- **Chia theo ổ đĩa**: thanh bên liệt kê từng ổ (ổ khởi động, ổ trong khác, ổ rời) với chấm màu tình trạng. Ổ rời tự hiện khi cắm, tự ẩn khi rút.
- **Mức độ bằng màu + chữ**: Nghiêm trọng (đỏ), Cảnh báo (cam), Gợi ý (xanh dương), Ổn (xanh lá). Màu luôn đi kèm nhãn chữ để người mù màu vẫn đọc được.
- **Lớn trước, nhỏ sau**: mọi danh sách mặc định sắp xếp dung lượng giảm dần.
- **An toàn trước**: mọi thao tác xoá có hộp thoại xác nhận và chỉ chuyển vào Thùng rác.

## Các màn hình

| # | Màn hình | Nội dung chính |
|---|---|---|
| 1 | **Tóm tắt** | Danh sách “Cần chú ý” theo mức độ, thẻ từng ổ đĩa, thanh “dùng cho việc gì” của ổ khởi động |
| 2 | **Chi tiết ổ đĩa** | Thanh dung lượng theo phân loại; 3 tab: Phân loại · Thư mục (treemap + danh sách) · File lớn |
| 3 | **File trùng tên** | Cột nhóm (xếp theo dung lượng giải phóng được) + chi tiết từng bản, đánh dấu bản mới nhất |
| 4 | **Docker** | Thanh 4 bước (cài đặt → đang chạy → quét → dọn), ô thống kê, danh sách image `<none>` |
| 5 | **Xác nhận ổ rời & tiến trình quét** | Hộp thoại chọn ổ rời, thẻ tiến trình (số file, dung lượng, thời gian, huỷ) |
| 6 | **Hướng dẫn sử dụng** | Mục lục bên trái, nội dung bên phải, đổi ngôn ngữ ngay tại chỗ |

Ngoài ra trong app còn có: Nhật ký xoá, Cài đặt, màn hình chào lần đầu (Onboarding), hộp thoại xác nhận chuyển vào Thùng rác.

## Bảng màu

| Vai trò | Màu |
|---|---|
| Nhấn (accent) | `#0A5CD4` |
| Nghiêm trọng | `#C4261C` |
| Cảnh báo | `#C25400` |
| Ổn | `#1F7A3B` |
| Ứng dụng / Lập trình / Ảnh & Video / Tài liệu / Cache | `#2F5FC4` / `#6B45C2` / `#B8620F` / `#1F7F70` / `#6C717A` |

Toàn bộ màu nằm trong `App/Sources/Views/Common/Theme.swift`.
