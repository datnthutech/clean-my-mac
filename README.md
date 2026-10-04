# Clean My Mac

<img src="docs/icon.png" width="96" align="right" alt="">

[![CI](https://github.com/datnthutech/clean-my-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/datnthutech/clean-my-mac/actions/workflows/ci.yml)

Ứng dụng **macOS và Windows** giúp bạn **biết dung lượng ổ đĩa đang dùng vào việc gì** và dọn dẹp an toàn.
*A macOS and Windows app that shows what fills your disks and helps you clean up safely (Vietnamese + English UI).*

## Tính năng

- 💽 **Chia theo từng ổ đĩa**: ổ khởi động, ổ trong khác và ổ rời (hỏi xác nhận trước khi quét ổ rời, và chỉ hỏi khi có ổ rời)
- ⚡ **Quét nhanh, chính xác**: đọc song song, tính dung lượng thực chiếm, hard link chỉ đếm một lần, không đi theo lối tắt
- 📊 **Sắp xếp từ lớn đến nhỏ**: danh sách thư mục, treemap, top file lớn, dung lượng theo mục đích sử dụng, thư mục đáng chú ý
- 📄 **File trùng tên** trên mọi ổ đã quét
- 🐳 **Docker**: kiểm tra đã cài → đang chạy → quét image `<none>` → dọn có xác nhận
- 🚦 **Cảnh báo theo mức độ** (Nghiêm trọng / Cảnh báo / Gợi ý), ví dụ ổ hệ thống còn dưới 10 GB sẽ gây lag máy
- 🗑️ **Xoá an toàn**: chỉ chuyển vào Thùng rác, khoá thư mục hệ thống, có nhật ký xoá
- 🌐 **Tiếng Việt & English**, đổi ngay trong app · không kết nối mạng

## Tải về

Vào trang **[Releases](https://github.com/datnthutech/clean-my-mac/releases)**, mở bản mới nhất, kéo xuống **Assets**.

> ⚠️ Phần **Assets** thường bị thu gọn: bấm **Show all … assets**. Hai mục *Source code* là mã nguồn, **không** chứa file cài đặt.

| Hệ điều hành | Yêu cầu | File cần tải | Cài đặt |
|---|---|---|---|
| 🍎 **macOS** | macOS 13+ · Apple silicon và Intel | `CleanMyMac-<phiên bản>-macOS.dmg` | Mở `.dmg`, kéo app vào **Applications** |
| 🪟 **Windows** (Intel/AMD) | Windows 10 1809+ / Windows 11 · x64 | `CleanMyMac-<phiên bản>-windows-x64.zip` | **Giải nén toàn bộ** zip, chạy `CleanMyMac.exe` |
| 🪟 **Windows** (ARM64) | Windows 10 1809+ / Windows 11 · ARM64 | `CleanMyMac-<phiên bản>-windows-ARM64.zip` | Như trên |

- Bản Windows là **bản portable**: không có `Setup.exe`, cài = giải nén, gỡ = xoá thư mục.
- Lần đầu mở, macOS (Gatekeeper) hoặc Windows (SmartScreen) sẽ cảnh báo vì bản dựng chưa ký số thương mại; cách vượt qua có trong [hướng dẫn sử dụng](docs/USER_GUIDE.md#1-tải-về-và-cài-đặt).
- Mỗi file có `.sha256` đi kèm để kiểm tra toàn vẹn (các bản phát hành mới).

![Màn hình Tóm tắt trên macOS (ảnh chụp tự động từ CI, macOS 15)](docs/screenshot-summary.jpg)

![Bản Windows: các trang chụp tự động từ CI (Windows Server 2025)](docs/screenshot-windows.jpg)

## Hai bản, một thiết kế

| | macOS | Windows |
|---|---|---|
| Công nghệ | Swift 5 + SwiftUI | C# / .NET 8 + WinUI 3 (Windows App SDK) |
| Logic dùng chung về ý tưởng | `Packages/DiskKit` | `windows/src/DiskKit.Core` |
| Đọc dung lượng | `getattrlistbulk` | Đọc thư mục hàng loạt của Windows (có File ID) |
| Quyền quét đầy đủ | Full Disk Access | Chạy với quyền Admin (không bắt buộc) |
| Xoá | Thùng rác | Thùng rác (USB/thẻ nhớ không có → cảnh báo riêng) |
| Test | 35 test (Swift) | 29 test (xUnit) |

Bản dịch dùng chung: bản Windows nạp lại file `.strings` của macOS và ghi đè phần riêng. Khác biệt đầy đủ: [hướng dẫn sử dụng, mục 13](docs/USER_GUIDE.md#13-khác-biệt-giữa-bản-macos-và-windows).

## Bắt đầu nhanh

**Người dùng:** đọc [Hướng dẫn sử dụng](docs/USER_GUIDE.md) (hoặc [English](docs/USER_GUIDE.en.md)); cũng có sẵn trong app, mục *Hướng dẫn sử dụng*.

**Người phát triển:**

| Bạn muốn | Làm |
|---|---|
| 🍎 Build và tạo DMG | `make build` (cần Xcode 15+ và Homebrew) → `build/CleanMyMac-x.y.z.dmg` |
| 🍎 Mở trong Xcode / chạy | `make open` / `make run` |
| 🍎 Chạy test | `make test` (Mac), hoặc `make test-linux` (Docker, không cần Mac) |
| 🪟 Build | `dotnet publish windows/src/CleanMyMac.App -c Release -r win-x64 -p:Platform=x64 -o windows/artifacts/win-x64` (cần .NET SDK 8 trên Windows) |
| 🪟 Chạy test logic | `dotnet test windows/tests/DiskKit.Core.Tests` (chạy được trên mọi hệ điều hành) |
| Kiểm tra bản dịch | `python3 scripts/check_localization.py` (cả hai app) |
| Kiểm tra liên kết tài liệu | `python3 scripts/check_docs.py` (chạy cả trong CI) |
| Phát hành | Đẩy tag `v1.0.0` → xem [docs/RELEASING.md](docs/RELEASING.md) |

Mỗi lần push, CI build và chạy thử cả hai app (mở từng trang, quét thật, chụp màn hình).

## Tài liệu

| Tài liệu | Nội dung |
|---|---|
| [Hướng dẫn sử dụng](docs/USER_GUIDE.md) · [English](docs/USER_GUIDE.en.md) | Tải về, cài đặt, từng màn hình, xoá và khôi phục, xử lý sự cố, gỡ cài đặt (macOS và Windows) |
| [Kiến trúc](docs/ARCHITECTURE.md) | Cấu trúc mã nguồn, luồng dữ liệu, build, nên sửa ở đâu khi thêm tính năng |
| [Phát hành](docs/RELEASING.md) | Cách tạo Release, kiểm tra, xử lý sự cố, ký số |
| [Thiết kế giao diện](docs/DESIGN.md) | Nguyên tắc, màn hình, bảng màu, khác biệt macOS/Windows |
| [Kế hoạch](docs/PLAN.md) | Mục tiêu, quyết định đã chốt, trạng thái, hạn chế và hướng tiếp theo |
| [Nhật ký thay đổi](CHANGELOG.md) | Thay đổi theo từng phiên bản |

Mẫu thiết kế tương tác (6 màn hình): <https://claude.ai/artifact/SrnoYTUQTpu9VbmCPEiELa> (riêng tư, chỉ xem được khi chủ sở hữu chia sẻ).

## Cấu trúc

```
App/                macOS: SwiftUI app (Views, State, Localization, Resources vi/en)
Packages/DiskKit/   macOS: logic thuần Swift + unit test (quét, phân loại, trùng tên, Docker, cảnh báo, xoá an toàn)
windows/            Windows: WinUI 3 app (src/CleanMyMac.App) + logic C# (src/DiskKit.Core) + unit test (tests/)
scripts/            build.sh, make_dmg.sh, check_localization.py, check_docs.py, generate_icon.py, windows-smoke.ps1, test_linux.sh
docs/               Tài liệu (hướng dẫn, kiến trúc, thiết kế, kế hoạch, phát hành)
project.yml         Cấu hình XcodeGen (sinh CleanMyMac.xcodeproj)
global.json         Ghim .NET SDK 8 cho bản Windows
.github/workflows/  ci.yml (test + build + chạy thử cả hai app) · release.yml (tag v* → GitHub Release)
```

## Trạng thái và hạn chế

Hiện là **bản beta** (`v1.0.0-beta.1`):

- **Chưa kiểm thử trên thiết bị thật** (CI chỉ có máy ảo): cắm USB/SSD rời, xoá file thật trên USB (Windows), Windows 10 bản 1809, máy ARM64, macOS 13/14/26. Đã kiểm thử tự động trên macOS 15 và Windows Server 2025.
- **Chưa ký số thương mại**: Gatekeeper/SmartScreen cảnh báo lần đầu mở. **Windows chưa có `Setup.exe`** (zip portable).
- Bản Windows **chưa có phím tắt** và **chưa có menu chuột phải**.
- **Chưa tự cập nhật**; **chưa chọn giấy phép** (cần thêm file `LICENSE` trước khi phát hành rộng rãi).
- **Tên "CleanMyMac" là thương hiệu của MacPaw.** Nên đổi tên trước khi phát hành công khai: `project.yml`, thư mục/dự án `windows/src/CleanMyMac.App`, và khoá `app.name` trong các file `.strings`.

Chi tiết và hướng phát triển tiếp theo: [docs/PLAN.md](docs/PLAN.md#8-hạn-chế-đã-biết-và-hướng-phát-triển-tiếp-theo).

## Báo lỗi

Mở issue tại <https://github.com/datnthutech/clean-my-mac/issues> kèm hệ điều hành, phiên bản app (**Cài đặt › Thông tin**) và các bước tái hiện.
