# Clean My Mac

<img src="docs/icon.png" width="96" align="right" alt="">

Ứng dụng macOS giúp bạn **biết dung lượng ổ đĩa đang dùng vào việc gì** và dọn dẹp an toàn.
*A macOS app that shows what fills your disks and helps you clean up safely (Vietnamese + English).*

- 💽 **Chia theo từng ổ đĩa** — ổ khởi động, ổ trong khác và ổ rời (hỏi xác nhận trước khi quét ổ rời)
- ⚡ **Quét nhanh, chính xác** — đọc song song bằng `getattrlistbulk`, tính dung lượng thực chiếm, hardlink chỉ đếm một lần
- 📊 **Sắp xếp từ lớn đến nhỏ** — danh sách thư mục, treemap, top file lớn, dung lượng theo mục đích sử dụng
- 📄 **File trùng tên** trên mọi ổ đã quét
- 🐳 **Docker** — kiểm tra đã cài → đang chạy → quét image `<none>` → dọn có xác nhận
- 🚦 **Cảnh báo theo mức độ** — ví dụ ổ khởi động còn dưới 10 GB sẽ gây lag máy
- 🗑️ **Xoá an toàn** — chỉ chuyển vào Thùng rác, khoá thư mục hệ thống, có nhật ký
- 🖥️ **Hai bản**: macOS 13+ (Apple silicon & Intel) và **Windows 10 1809+ / Windows 11** (x64 & ARM64)
- 🌐 **Tiếng Việt & English**, đổi ngay trong app

![Màn hình Tóm tắt — ảnh chụp từ CI trên macOS 15](docs/screenshot-summary.jpg)

![Bản Windows — các trang chụp từ CI trên Windows Server 2025](docs/screenshot-windows.jpg)

## Bắt đầu

| Bạn muốn | Làm |
|---|---|
| Dùng ngay (macOS) | Tải DMG ở **Actions › CI › Artifacts** (hoặc **Releases**), kéo app vào Applications |
| Dùng ngay (Windows) | Tải `CleanMyMac-windows-x64.zip` (hoặc `ARM64`) ở **Actions › CI › Artifacts**, giải nén, chạy `CleanMyMac.exe` |
| Tự build trên Mac | `make build` (cần Xcode 15+ và Homebrew) → `build/CleanMyMac-x.y.z.dmg` |
| Mở trong Xcode | `make open` |
| Chạy test | `make test` (Mac) hoặc `make test-linux` (Docker); Windows: `dotnet test windows/tests/DiskKit.Core.Tests` |

## Tài liệu

- [Hướng dẫn sử dụng](docs/USER_GUIDE.md) · [User Guide (English)](docs/USER_GUIDE.en.md)
- [Kiến trúc & cấu trúc mã nguồn](docs/ARCHITECTURE.md)
- [Thiết kế giao diện](docs/DESIGN.md)
- [Kế hoạch dự án](docs/PLAN.md)

## Cấu trúc

```
App/               macOS: SwiftUI app (Views, State, Localization, Resources vi/en)
Packages/DiskKit/  macOS: logic thuần Swift + unit test: quét, phân loại, trùng tên, Docker, cảnh báo, xoá an toàn
windows/           Windows: WinUI 3 app (src/CleanMyMac.App) + logic C# (src/DiskKit.Core) + unit test (tests/)
scripts/           build.sh, make_dmg.sh, check_localization.py, generate_icon.py
project.yml        Cấu hình XcodeGen (sinh CleanMyMac.xcodeproj)
.github/workflows/ CI build DMG mỗi lần push · Release khi push tag v*
```
