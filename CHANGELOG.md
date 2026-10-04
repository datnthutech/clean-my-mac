# Nhật ký thay đổi / Changelog

Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/); phiên bản theo [SemVer](https://semver.org/lang/vi/).
Cách phát hành: [docs/RELEASING.md](docs/RELEASING.md).

## [Chưa phát hành]

### Thêm
- Quy trình Release mới: hai job chạy tuần tự (macOS rồi Windows) để không tranh nhau tạo Release; tên file theo phiên bản (`CleanMyMac-<phiên bản>-macOS.dmg`, `…-windows-x64.zip`, `…-windows-ARM64.zip`); kèm file `.sha256`; có ghi chú cài đặt; tag có dấu `-` tự đánh dấu **Pre-release**.
- `docs/RELEASING.md` (cách phát hành và xử lý sự cố), `CHANGELOG.md`.

### Thay đổi
- Hướng dẫn sử dụng (`docs/USER_GUIDE.md`, `docs/USER_GUIDE.en.md`) viết lại thành một tài liệu thống nhất cho **macOS và Windows**: cách tải đúng file ở trang Releases, cài đặt từng hệ điều hành, so sánh khác biệt, xử lý sự cố, vị trí dữ liệu và gỡ cài đặt.
- README, `ARCHITECTURE.md`, `DESIGN.md`, `PLAN.md` cập nhật cho hai bản và quy trình phát hành.
- Chuỗi trợ giúp trong app (bản Windows): sửa câu FAQ về SmartScreen (không có trình cài đặt) và thêm câu hỏi "cài đặt/gỡ cài đặt".

## [1.0.0-beta.1] — 2026-10-03

Bản thử nghiệm đầu tiên, có cả macOS và Windows.

### Thêm
- **macOS** (SwiftUI, macOS 13+, Apple silicon và Intel): chia theo từng ổ đĩa; hỏi xác nhận trước khi quét ổ rời; quét song song, dung lượng thực chiếm; danh sách lớn → nhỏ, treemap, file lớn; phân loại theo mục đích sử dụng và thư mục đáng chú ý; file trùng tên; Docker 4 bước (image `<none>`); cảnh báo theo 3 mức độ; xoá vào Thùng rác có xác nhận, khoá thư mục hệ thống, nhật ký xoá; song ngữ Việt/Anh; hướng dẫn sử dụng trong app.
- **Windows** (WinUI 3, Windows 10 1809+ và Windows 11, x64 và ARM64, self-contained): cùng 6 màn hình và tính năng; quét bằng API đọc thư mục hàng loạt của Windows, hard link tính một lần; thư mục đáng chú ý của Windows; nút Khởi động lại với quyền Admin; xoá vào Thùng rác và cảnh báo riêng với USB/thẻ nhớ (không có Thùng rác).
- Menu bên trái luôn hiện trên mọi trang; mọi trang cuộn thay vì tràn ra ngoài cửa sổ; lỗi một trang không làm mất menu.
- CI: test và build cả hai bản, chạy thử app trên macOS 15 và Windows Server 2025 (mở từng trang, quét thật, chụp màn hình); Release khi đẩy tag `v*`.

### Hạn chế đã biết
- Bản dựng chưa ký số (Gatekeeper/SmartScreen sẽ cảnh báo lần đầu mở). Bản Windows là zip portable, chưa có `Setup.exe`.
- Chưa kiểm thử trên thiết bị thật: USB/SSD rời, Windows 10 1809, máy ARM64, macOS 13/14/26.
- Bản Windows chưa có phím tắt riêng và chưa có menu chuột phải.
- Release này dùng workflow đời đầu: chưa có file `.sha256` và chưa được đánh dấu pre-release.
