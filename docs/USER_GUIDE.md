# Hướng dẫn sử dụng Clean My Mac

> English: [USER_GUIDE.en.md](USER_GUIDE.en.md) · Hướng dẫn này cũng có sẵn trong app: mục **Hướng dẫn sử dụng** ở menu bên trái (macOS: ⌘?).

Clean My Mac giúp bạn **biết dung lượng ổ đĩa đang được dùng vào việc gì**, chỉ ra những thứ chiếm chỗ không cần thiết và dọn dẹp **an toàn**: mọi thứ xoá đều vào Thùng rác trước, không xoá vĩnh viễn khi chưa hỏi.

Có **hai bản** với giao diện và tính năng giống nhau. Những chỗ khác nhau được ghi rõ bằng 🍎 (macOS) và 🪟 (Windows); tổng hợp ở [mục 13](#13-khác-biệt-giữa-bản-macos-và-windows).

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Hệ điều hành | macOS 13 Ventura trở lên | Windows 10 phiên bản 1809 (build 17763) trở lên, Windows 11 |
| Máy | Apple silicon và Intel | x64 (Intel/AMD) và ARM64 |
| File cài đặt | `.dmg` (kéo vào Applications) | `.zip` bản **portable**: giải nén rồi chạy `CleanMyMac.exe` (không có `Setup.exe`) |
| Quyền để quét đầy đủ | Full Disk Access | Chạy với quyền Admin (không bắt buộc) |

![Màn hình Tóm tắt trên macOS](screenshot-summary.jpg)

---

## Mục lục

1. [Tải về và cài đặt](#1-tải-về-và-cài-đặt)
2. [Mở lần đầu và cấp quyền](#2-mở-lần-đầu-và-cấp-quyền)
3. [Giao diện](#3-giao-diện)
4. [Quét ổ đĩa](#4-quét-ổ-đĩa)
5. [Màn hình Tóm tắt và mức độ cảnh báo](#5-màn-hình-tóm-tắt-và-mức-độ-cảnh-báo)
6. [Chi tiết một ổ đĩa](#6-chi-tiết-một-ổ-đĩa)
7. [File trùng tên](#7-file-trùng-tên)
8. [Docker](#8-docker)
9. [Xoá và khôi phục](#9-xoá-và-khôi-phục)
10. [Nhật ký xoá](#10-nhật-ký-xoá)
11. [Cài đặt](#11-cài-đặt)
12. [Phím tắt và thao tác](#12-phím-tắt-và-thao-tác)
13. [Khác biệt giữa bản macOS và Windows](#13-khác-biệt-giữa-bản-macos-và-windows)
14. [Xử lý sự cố](#14-xử-lý-sự-cố)
15. [Dữ liệu của app và cách gỡ cài đặt](#15-dữ-liệu-của-app-và-cách-gỡ-cài-đặt)
16. [Câu hỏi thường gặp](#16-câu-hỏi-thường-gặp)

---

## 1. Tải về và cài đặt

### 1.1 Lấy file ở đâu

**Cách chính: trang Releases.** Vào <https://github.com/datnthutech/clean-my-mac/releases>, mở bản mới nhất (bản thử nghiệm có nhãn **Pre-release**), kéo xuống phần **Assets**.

> ⚠️ Phần **Assets** thường bị thu gọn. Nếu chỉ thấy *Source code (zip)* và *Source code (tar.gz)* thì bấm **Show all … assets**. Hai mục *Source code* là **mã nguồn**, không chạy được và **không chứa** `.dmg` hay `.exe`.

Các file cần tải:

| Hệ điều hành | File (bản phát hành mới) | Bản beta.1 đặt tên cũ |
|---|---|---|
| 🍎 macOS | `CleanMyMac-<phiên bản>-macOS.dmg` | `CleanMyMac-1.0.0-beta.1.dmg` |
| 🪟 Windows x64 | `CleanMyMac-<phiên bản>-windows-x64.zip` | `CleanMyMac-1.0.0-beta.1-windows-x64.zip` |
| 🪟 Windows ARM64 | `CleanMyMac-<phiên bản>-windows-ARM64.zip` | `CleanMyMac-1.0.0-beta.1-windows-ARM64.zip` |
| Kiểm tra toàn vẹn | `<tên file>.sha256` đi kèm từng file | (chưa có) |

**Cách phụ: bản dựng thử từ CI.** Vào [Actions](https://github.com/datnthutech/clean-my-mac/actions) › lần chạy **CI** mới nhất › mục **Artifacts** (cần đăng nhập GitHub): `CleanMyMac-dmg`, `CleanMyMac-windows-x64`, `CleanMyMac-windows-ARM64`. GitHub **bọc thêm một lớp zip** bên ngoài, nên phải giải nén hai lần mới ra `.dmg` hoặc `.zip` Windows. File này tự hết hạn sau một thời gian.

**Kiểm tra file tải về không bị lỗi** (tuỳ chọn, khi có file `.sha256`):
- 🍎 `shasum -a 256 tên-file.dmg`
- 🪟 PowerShell: `Get-FileHash tên-file.zip -Algorithm SHA256`

So chuỗi kết quả với nội dung file `.sha256`.

### 1.2 🍎 Cài trên macOS

1. Mở file `.dmg`, kéo **Clean My Mac** vào thư mục **Applications**.
2. Mở app từ Applications. App được ký ad-hoc (chưa có Developer ID), nên macOS sẽ chặn lần đầu với thông báo *"Apple không thể kiểm tra…"*:
   - Mở **Cài đặt hệ thống › Quyền riêng tư & Bảo mật**, kéo xuống mục *Bảo mật*, bấm **Vẫn mở** (Open Anyway) và nhập mật khẩu; hoặc
   - Chạy trong Terminal: `xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"`
   - (macOS 13–14) cũng có thể chuột phải app › **Mở** › **Mở**
3. Một file `.dmg` dùng được cho cả máy Apple silicon lẫn Intel (universal).

### 1.3 🪟 Cài trên Windows

Bản Windows hiện là **bản portable**: không có trình cài đặt `Setup.exe`, không ghi vào Registry hay Program Files. Cài = giải nén; gỡ = xoá thư mục.

1. **Chọn đúng bản:** mở **Cài đặt › Hệ thống › Giới thiệu**, xem *Loại hệ thống*. Có chữ *x64-based* → tải bản **x64**; có chữ *ARM-based* → tải bản **ARM64**. Kiểm tra phiên bản Windows: nhấn `Win + R`, gõ `winver` (cần từ **1809**, build 17763 trở lên).
2. (Khuyến nghị) Chuột phải file `.zip` › **Properties** › tick **Unblock** › OK. Bước này giúp Windows không hỏi cảnh báo cho từng file trong thư mục.
3. Chuột phải file `.zip` › **Extract All…** vào một thư mục cố định, ví dụ `C:\Tools\CleanMyMac`.
   > ❗ Phải **giải nén toàn bộ**. Chạy `CleanMyMac.exe` ngay trong cửa sổ xem zip hoặc chép riêng file `.exe` ra chỗ khác sẽ lỗi, vì app cần các file đi cùng trong thư mục (khoảng 65 MB, đã gồm sẵn runtime, không cần cài .NET).
4. Mở thư mục vừa giải nén, chạy **`CleanMyMac.exe`**.
5. Nếu hiện *"Windows protected your PC"* (SmartScreen): bấm **More info** (Thông tin thêm) › **Run anyway** (Vẫn chạy). Lý do: app chưa ký bằng chứng chỉ ký code thương mại.
6. Tạo lối tắt: chuột phải `CleanMyMac.exe` › **Show more options** › **Send to › Desktop (create shortcut)**, hoặc **Pin to Start**.

### 1.4 Tự build từ mã nguồn

- 🍎 Cần Xcode 15+ và Homebrew: `make build` (tự cài XcodeGen, chạy test, build universal, tạo DMG vào thư mục `build/`); `make run` để build và mở app; `make open` để mở trong Xcode.
- 🪟 Cần .NET SDK 8 trên Windows (Visual Studio không bắt buộc; file `global.json` ở gốc repo ghim SDK 8):
  ```powershell
  dotnet publish windows/src/CleanMyMac.App/CleanMyMac.App.csproj -c Release -r win-x64 -p:Platform=x64 -o windows/artifacts/win-x64
  ```
  Dùng `-r win-arm64 -p:Platform=ARM64` cho máy ARM64. Chạy `windows/artifacts/win-x64/CleanMyMac.exe`.

Chi tiết cho người phát triển: [ARCHITECTURE.md](ARCHITECTURE.md), cách phát hành: [RELEASING.md](RELEASING.md).

---

## 2. Mở lần đầu và cấp quyền

Lần đầu mở, app hiện **màn hình chào**: giới thiệu tính năng, chọn **ngôn ngữ** (Tiếng Việt / English / theo hệ điều hành) và hướng dẫn cấp quyền. Có thể đổi ngôn ngữ bất cứ lúc nào, hiệu lực ngay, không cần mở lại app.

### 🍎 Full Disk Access (khuyến nghị)
macOS bảo vệ một số thư mục (Mail, Tin nhắn, Safari, dữ liệu của ứng dụng khác). Không có quyền này app **bỏ qua** các thư mục đó nên kết quả thiếu.

1. Bấm **Mở Cài đặt hệ thống** (hoặc vào **Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Toàn quyền truy cập ổ đĩa**).
2. Bật **Clean My Mac**. Chưa thấy trong danh sách thì bấm **+** và chọn app trong Applications.
3. Quay lại app, bấm **Kiểm tra lại**. Nếu vẫn báo *Chưa cấp*, thoát app (⌘Q) rồi mở lại.

### 🪟 Quyền Admin (không bắt buộc)
Với tài khoản thường, Windows không cho liệt kê một số thư mục (`Windows`, hồ sơ người dùng khác, `System Volume Information`…). App **bỏ qua** các thư mục đó, tổng dung lượng trông nhỏ hơn thực tế và màn Tóm tắt có gợi ý *"N thư mục bị bỏ qua"*.

- Bấm **Khởi động lại với quyền Admin** (ở màn hình chào, **Cài đặt › Quyền truy cập**, hoặc **Hướng dẫn › Quyền Admin**) và đồng ý hộp thoại UAC. App tự mở lại với toàn quyền; cài đặt được giữ nguyên.
- Không dùng Admin vẫn xài được mọi tính năng, chỉ là kết quả không đầy đủ.

> App chỉ đọc **tên và dung lượng** file, không đọc nội dung và **không kết nối mạng**.

---

## 3. Giao diện

Cả hai bản đều có **menu bên trái** và **nội dung** bên phải:

```
┌────────────────┬──────────────────────────────────────────────┐
│ TỔNG QUAN      │                                              │
│  Tóm tắt       │        Nội dung của mục đang chọn            │
│ Ổ ĐĨA          │                                              │
│  Ổ khởi động ● │                                              │
│  Ổ rời        ●│                                              │
│ CÔNG CỤ        │                                              │
│  File trùng tên│                                              │
│  Docker        │                                              │
│  Nhật ký xoá   │                                              │
│ ỨNG DỤNG       │                                              │
│  Hướng dẫn     │                                              │
│  Cài đặt       │                                              │
└────────────────┴──────────────────────────────────────────────┘
```

- **Menu luôn hiện trên mọi trang**, kể cả khi trang chưa có dữ liệu hoặc gặp lỗi. Lỗi ở một trang chỉ hiện trong vùng nội dung.
- Mỗi ổ đĩa có **chấm màu** tình trạng dung lượng trống: 🔴 Nghiêm trọng · 🟠 Cảnh báo · 🟢 Ổn.
- Ổ rời (USB, SSD gắn ngoài, thẻ nhớ) tự xuất hiện khi cắm và biến mất khi rút. 🍎 cập nhật ngay; 🪟 kiểm tra mỗi khoảng 3 giây.
- Cửa sổ quá nhỏ thì trang **cuộn ngang/dọc** thay vì tràn ra ngoài.
- Nút **Quét tất cả**: 🍎 ở góc trên bên phải (và menu File, ⌘R); 🪟 ở đầu menu bên trái. Khi đang quét nút đổi thành **Huỷ quét**.
- 🍎 Hỗ trợ Light/Dark mode. 🪟 Dùng giao diện Fluent của Windows 11 (hiệu ứng Mica khi hệ thống hỗ trợ), chạy được trên Windows 10.

![Bản Windows: các trang chụp tự động từ máy ảo Windows](screenshot-windows.jpg)

---

## 4. Quét ổ đĩa

Bấm **Quét tất cả**.

1. App luôn quét **ổ khởi động** (🍎 Macintosh HD, 🪟 ổ cài Windows, thường là C:) và các **ổ trong** khác.
2. Nếu đang cắm **ổ rời**, app hiện hộp thoại *"Phát hiện N ổ đĩa rời — bạn có muốn quét luôn không?"*:
   - Tick ổ muốn quét rồi bấm **Quét các ổ đã chọn**, hoặc bấm **Chỉ quét ổ trong**.
   - **Ghi nhớ lựa chọn** để lần sau không hỏi lại (đổi trong **Cài đặt › Ổ rời khi bấm "Quét tất cả"**: Luôn hỏi / Luôn quét / Không quét).
   - **Không có ổ rời nào** → app quét luôn, không hỏi.
3. Thẻ tiến trình ở cuối cửa sổ hiện ổ đang quét, số file, dung lượng, thời gian và thư mục hiện tại. **Huỷ quét** bất cứ lúc nào (🍎 ⌘.).
4. Cắm ổ mới **khi app đang mở** → app hỏi *"Đã kết nối ổ X — Quét ngay?"*.
5. Muốn quét riêng một ổ: chọn ổ ở menu › **Quét ổ này** / **Quét lại**.

Quét ổ nào thì ổ đó mới có dữ liệu. File trùng tên và Docker được xử lý **sau khi quét xong** các ổ đã chọn.

Bỏ qua tự động: ổ mạng (NAS, SMB) và ổ chưa sẵn sàng; 🪟 thêm ổ đĩa quang. Không đi theo lối tắt (symlink, junction), nên không đếm trùng.

**Dung lượng hiển thị là dung lượng thực chiếm trên đĩa** (xoá file thì giải phóng đúng chừng đó). Hard link chỉ tính một lần (🪟 rất nhiều trong `Windows\WinSxS`). Ví dụ tham khảo: trên máy ảo CI, quét khoảng 1,9 triệu file mất khoảng 1 phút; HDD hoặc USB 2.0 chậm hơn nhiều.

---

## 5. Màn hình Tóm tắt và mức độ cảnh báo

Gồm 3 phần:

1. **Cần chú ý**: danh sách ngắn xếp theo mức độ, rồi theo dung lượng. Bấm **Xem** để đi thẳng tới thư mục, Docker hoặc danh sách trùng tên liên quan.
2. **Ổ đĩa**: thẻ từng ổ với thanh dung lượng, dung lượng trống, định dạng, loại ổ.
3. **Ổ khởi động dùng cho việc gì**: thanh màu theo phân loại (Ứng dụng, Lập trình, Ảnh & Video, Tài liệu, Cache…).

Khi chưa quét, Tóm tắt vẫn cảnh báo dung lượng trống (không cần quét).

### Các mức độ

| Mức | Khi nào | Ảnh hưởng |
|---|---|---|
| 🔴 **Nghiêm trọng** | Ổ khởi động (🪟 ổ Windows) còn dưới **10 GB**, hoặc **bất kỳ ổ nào** còn dưới **5%** | 🍎 Máy dễ lag, treo do thiếu chỗ cho swap; không cài được bản cập nhật macOS (cần ~20–30 GB). 🪟 Windows chậm hoặc không ổn định do thiếu chỗ cho page file và file tạm; cập nhật lớn cần ~20 GB |
| 🟠 **Cảnh báo** | Ổ khởi động còn dưới **20 GB**, hoặc bất kỳ ổ nào dưới **10%**; một thư mục rác ≥ **10 GB**; Docker `<none>` ≥ **5 GB**; build cache Docker dọn được ≥ **10 GB**; 🍎 chưa cấp Full Disk Access | SSD ghi chậm hơn, snapshot/điểm khôi phục bị xoá, ứng dụng nặng chạy chậm, cập nhật có thể thất bại |
| 🔵 **Gợi ý** | Thư mục dọn được ≥ **1 GB**; Downloads ≥ **20 GB**; có file trùng tên; có image Docker `<none>`; build cache Docker dọn được ≥ **1 GB**; 🪟 có thư mục bị bỏ qua vì thiếu quyền Admin | Có thể giải phóng thêm dung lượng |
| 🟢 **Ổn** | Còn lại | — |

Ngưỡng GB chỉ áp dụng cho **ổ khởi động** (vì hệ điều hành cần chỗ trống ở đó); ngưỡng % áp dụng cho **mọi ổ**. Đây là khuyến nghị kinh nghiệm, chỉnh được trong **Cài đặt › Cảnh báo dung lượng trống**.

---

## 6. Chi tiết một ổ đĩa

Chọn ổ ở menu. Đầu trang là thanh dung lượng chia màu theo phân loại; phần **xám** là *Dữ liệu hệ thống & không đọc được* (🍎 snapshot APFS, swap; 🪟 điểm khôi phục, dữ liệu NTFS; thư mục được bảo vệ).

### Tab "Phân loại"
- Dung lượng theo **mục đích sử dụng** (Ứng dụng, Tài liệu, Ảnh & Video, Nhạc, File nén & Bộ cài, Lập trình, Cache, Sao lưu iOS, Mail, Thùng rác, Docker, Hệ thống, Khác) kèm phần trăm.
- **Thư mục lớn nên kiểm tra**: những vị trí quen thuộc thường dọn được. Bấm **Xem** để mở thư mục đó ở tab Thư mục.
  - 🍎 Xcode DerivedData và Archives, iOS Simulator, cache ứng dụng, Thùng rác, bản sao lưu iPhone, `node_modules`, Downloads, cache Homebrew.
  - 🪟 File tạm Windows và của bạn, cache Windows Update, `Windows.old`, Thùng rác, cache trình duyệt, `node_modules`, Downloads, bản sao lưu iPhone, cache NuGet/npm, cache Visual Studio.

### Tab "Thư mục"
- Bên trái là **treemap**: mỗi ô là một thư mục/file, diện tích tỉ lệ với dung lượng (tối đa 40 ô lớn nhất, phần còn lại gộp vào "Khác").
- Bên phải là **danh sách xếp từ lớn đến nhỏ**; đổi sang *Tên* hoặc *Ngày sửa* ở ô **Sắp xếp**.
- **Nháy đúp** thư mục (trong danh sách hoặc treemap) để mở; bấm đường dẫn phía trên để quay lại.
- Chọn một hoặc nhiều mục (⌘/⇧ hoặc Ctrl/Shift), rồi dùng:

| Việc | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Mở thư mục | Nháy đúp hoặc chuột phải › Mở | Nháy đúp |
| Xem file ở nơi chứa nó | Mở trong Finder | **Mở trong Explorer** (thanh nút phía dưới) |
| Xem nội dung | Xem nhanh (Quick Look) | **Mở** (mở bằng ứng dụng mặc định) |
| Xoá | Chuyển vào Thùng rác | Chuyển vào Thùng rác |
| Cách thao tác | Chuột phải hoặc thanh nút phía dưới | Thanh nút phía dưới (chưa có menu chuột phải) |

### Tab "File lớn"
Những file lớn nhất trên ổ (mặc định từ **100 MB**, tối đa 200 file; đổi ngưỡng trong Cài đặt), kèm ngày sửa. Chọn rồi dùng các nút như tab Thư mục.

---

## 7. File trùng tên

Sau khi quét xong **tất cả** các ổ đã chọn, app gom các file **cùng tên** trên mọi ổ (không phân biệt hoa/thường, và chuẩn hoá dấu tiếng Việt nên "Báo cáo.pdf" gõ sẵn hay đã lưu đều khớp).

- **Cột trái**: các nhóm, xếp theo dung lượng giải phóng được nếu chỉ giữ **bản mới nhất**.
- **Cột phải**: các bản của nhóm đang chọn (thư mục chứa, ổ đĩa, ngày sửa, dung lượng). Bản mới nhất có nhãn **Mới nhất** và mặc định **không** được tick; các bản còn lại mặc định được tick sẵn để xoá. Rê chuột lên đường dẫn để xem đầy đủ.
- Mỗi bản có nút xem nội dung (🍎 Xem nhanh, 🪟 Mở) và mở nơi chứa (🍎 Finder, 🪟 Explorer).
- **Chọn tất cả trừ bản mới nhất** rồi **Chuyển N file vào Thùng rác**. App **không cho xoá hết** mọi bản trong một nhóm.

Tuỳ chọn ở phía trên (lưu lại cho lần sau, đổi xong app tìm lại ngay):
- *Bỏ qua `node_modules`, `.git`, thư mục build* (mặc định bật).
- 🍎 *Bỏ qua Library & hệ thống* / 🪟 *Bỏ qua Windows, Program Files & AppData* (mặc định bật). Gói ứng dụng (`.app`) cũng bị bỏ qua trên Mac.
- *Tối thiểu*: bỏ qua file nhỏ hơn 1 MB (mặc định); chọn được từ *mọi kích thước* đến 1 GB.

> ⚠️ **Trùng tên không có nghĩa là trùng nội dung.** Luôn xem từng bản trước khi xoá.

---

## 8. Docker

Trang này làm theo **4 bước**, mỗi bước chỉ chạy khi bước trước thành công:

1. **Đã cài Docker chưa?** App tìm lệnh `docker` ở các vị trí thường gặp. Chưa cài → hiện *"Máy chưa cài Docker"* và **không chạy lệnh nào**.
2. **Docker có đang chạy không?** Chưa chạy → hiện *"Docker đã cài nhưng chưa chạy"* và nút **Mở Docker**. Mở xong bấm **Kiểm tra lại**.
3. **Quét**: liệt kê image `<none>` (dangling: phần thừa sau mỗi lần build lại, không container nào dùng), tổng dung lượng image, build cache và file ổ ảo của Docker.
4. **Dọn**: tick image muốn xoá › **Xoá N image** › xác nhận.

Hỗ trợ: 🍎 Docker Desktop, OrbStack, Rancher Desktop (và Colima khi lệnh `docker` nằm ở đường dẫn Homebrew thường gặp). 🪟 Docker Desktop (WSL 2), Rancher Desktop, Podman, hoặc `docker.exe` có trong PATH.

**An toàn:** image được xoá bằng `docker image rm` **không kèm `--force`**, nên image đang được container dùng sẽ không bị xoá.

**Lưu ý:** 🍎 file `Docker.raw`, 🪟 file ổ ảo `.vhdx` (WSL 2) **không tự nhỏ lại ngay** sau khi xoá image. Đây là hành vi của Docker, không phải lỗi của app.

---

## 9. Xoá và khôi phục

- Mọi thao tác xoá đều qua **hộp thoại xác nhận** hiển thị số mục và tổng dung lượng, rồi **chuyển vào Thùng rác**.
- **Khôi phục:** mở Thùng rác › chuột phải file › 🍎 **Đưa trở lại** / 🪟 **Khôi phục**.
- Dung lượng chỉ thực sự được giải phóng sau khi bạn **dọn sạch Thùng rác**.
- **Vị trí bị khoá, không thể xoá:**
  - 🍎 `/System`, `/Library`, `/usr`, `/bin`, `/private`…, thư mục người dùng, Desktop, Documents, Downloads, Library, thư mục gốc của mỗi ổ và chính app.
  - 🪟 `Windows`, `ProgramData`, `System Volume Information`, `Recovery`, `Program Files`, hồ sơ người dùng và các thư mục `Desktop`, `Documents`, `Downloads`, `AppData`…, thư mục gốc của mỗi ổ, `pagefile.sys`/`hiberfil.sys` và chính app.
- Các mục bị khoá được liệt kê trong hộp thoại xác nhận và **tự động bị bỏ qua**.

### ⚠️ Riêng Windows: USB và thẻ nhớ không có Thùng rác
Ổ USB, thẻ nhớ (ổ "removable") của Windows **không có Thùng rác**. Nếu trong danh sách xoá có mục nằm trên các ổ này, hộp thoại hiện **cảnh báo đỏ** và nút đổi thành **Xoá vĩnh viễn**: xoá xong **không khôi phục được**. Hãy kiểm tra kỹ trước khi đồng ý. (🍎 macOS dùng Thùng rác riêng của từng ổ rời nên vẫn khôi phục được.)

> Chức năng này, cũng như hộp thoại hỏi ổ rời khi cắm USB, **chưa được kiểm thử trên thiết bị USB/thẻ nhớ thật** trong bản beta (CI chỉ có máy ảo). Nếu gặp vấn đề, hãy báo qua mục Issues.

---

## 10. Nhật ký xoá

Mục **Nhật ký xoá** lưu mọi thứ app đã dọn (file, thư mục, image Docker): thời gian, đường dẫn, dung lượng (tối đa 2000 dòng gần nhất). Có nút **Mở Thùng rác** để khôi phục nhanh và **Xoá nhật ký** (không ảnh hưởng file trong Thùng rác).

---

## 11. Cài đặt

| Mục | Ý nghĩa |
|---|---|
| Ngôn ngữ | Tiếng Việt / English / theo hệ điều hành; đổi ngay |
| Ổ rời khi bấm "Quét tất cả" | Luôn hỏi / Luôn quét / Không quét |
| Ngưỡng file lớn | Dung lượng tối thiểu để vào tab File lớn (mặc định 100 MB) |
| Cảnh báo dung lượng trống | 4 ngưỡng: Nghiêm trọng và Cảnh báo, mỗi loại theo GB (chỉ ổ khởi động) và theo % (mọi ổ) |
| Quyền truy cập | 🍎 trạng thái Full Disk Access + nút mở Cài đặt hệ thống. 🪟 đang chạy với quyền nào + nút **Khởi động lại với quyền Admin** |
| Thông tin | Phiên bản, **Khôi phục mặc định**; 🍎 thêm *Hiện màn hình chào* |

Mở Cài đặt: 🍎 menu bên trái hoặc ⌘, · 🪟 mục **Cài đặt** ở cuối menu bên trái.

---

## 12. Phím tắt và thao tác

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Quét tất cả | ⌘R | Nút ở đầu menu |
| Huỷ quét | ⌘. | Nút ở đầu menu |
| Cài đặt | ⌘, | Mục **Cài đặt** ở menu |
| Hướng dẫn sử dụng | ⌘? | Mục **Hướng dẫn sử dụng** ở menu |
| Chọn nhiều mục | ⌘-click, ⇧-click | Ctrl-click, Shift-click |
| Mở thư mục | Nháy đúp | Nháy đúp |
| Menu chuột phải | Có (Mở / Finder / Xem nhanh / Thùng rác) | Chưa có |
| Trong hộp thoại | Enter = nút chính, Esc = huỷ | Enter = nút chính (mặc định là nút an toàn khi xoá), Esc = huỷ |

Bản Windows hiện chưa có phím tắt riêng; chỉ dùng phím chuẩn của Windows (Tab, Enter, Esc…).

---

## 13. Khác biệt giữa bản macOS và Windows

| Nội dung | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Ổ khởi động | Macintosh HD (đã tránh đếm trùng phần dữ liệu firmlink) | Ổ cài Windows (thường C:) |
| Quyền đọc thư mục được bảo vệ | Full Disk Access | Nút Khởi động lại với quyền Admin (không bắt buộc) |
| Cách đọc dung lượng | `getattrlistbulk` (đọc hàng loạt) | API đọc thư mục hàng loạt của Windows, kèm File ID để đếm hard link một lần |
| Xoá file | Thùng rác (ổ rời dùng Thùng rác riêng của ổ) | Thùng rác; **USB/thẻ nhớ không có Thùng rác → cảnh báo và xoá vĩnh viễn nếu bạn đồng ý** |
| Xem file | Finder, Xem nhanh | Explorer, Mở (không có Xem nhanh) |
| Thư mục đáng chú ý | Xcode, Simulator, cache, Homebrew… | File tạm Windows, Windows Update, `Windows.old`, cache trình duyệt, NuGet/npm… |
| Phát hiện ổ cắm/rút | Ngay lập tức | Kiểm tra mỗi ~3 giây |
| Docker | Docker Desktop, OrbStack… | Docker Desktop (WSL 2)…; file `.vhdx` không tự nhỏ lại |
| Phím tắt, menu chuột phải | Có | Chưa có |
| Cài đặt | `.dmg` kéo vào Applications | `.zip` portable, giải nén chạy `CleanMyMac.exe` |
| Cảnh báo lần đầu mở | Gatekeeper → **Vẫn mở** | SmartScreen → **More info › Run anyway** |

Phần còn lại (quét, phân loại, tìm file trùng tên, Docker 4 bước, mức độ cảnh báo, nhật ký xoá, song ngữ) giống nhau.

---

## 14. Xử lý sự cố

**Tải về nhưng không thấy `.dmg` hoặc `.exe`.**
- Bạn có thể đã tải *Source code (zip)*. Hãy mở **Assets** (bấm *Show all assets*) và tải đúng file ở [mục 1.1](#11-lấy-file-ở-đâu).
- 🪟 Bản Windows **không có `Setup.exe`**. File `.exe` nằm **bên trong** `.zip` sau khi giải nén toàn bộ ([mục 1.3](#13--cài-trên-windows)).
- Tải từ Actions › Artifacts thì phải giải nén **hai lần**.

**🍎 macOS báo "không thể mở" / "Apple không thể kiểm tra".** Cài đặt hệ thống › Quyền riêng tư & Bảo mật › **Vẫn mở**, hoặc dùng lệnh `xattr` ở [mục 1.2](#12--cài-trên-macos).

**🪟 SmartScreen chặn, hoặc app báo thiếu file.** Bấm *More info › Run anyway*. Nếu app không mở: chắc chắn bạn đã **giải nén toàn bộ** zip và chạy `CleanMyMac.exe` trong thư mục đó; kiểm tra Windows từ 1809 trở lên và đúng bản x64/ARM64.

**Kết quả quét nhỏ hơn dung lượng ổ đang dùng.** Phần chênh nằm ở vùng xám *Dữ liệu hệ thống & không đọc được*. Cấp 🍎 Full Disk Access / 🪟 quyền Admin để đọc thêm; phần còn lại là dữ liệu hệ thống không liệt kê thành file được.

**Không thấy ổ USB/ổ rời trong menu.** Đảm bảo ổ đã được hệ điều hành gắn (mount) và có chữ cái ổ (🪟) hoặc xuất hiện trong Finder (🍎). Ổ mạng và ổ chưa sẵn sàng bị bỏ qua (🪟 cả ổ đĩa quang). 🪟 chờ vài giây để app cập nhật.

**Không có hộp thoại hỏi ổ rời.** Kiểm tra **Cài đặt › Ổ rời khi bấm "Quét tất cả"**: nếu đang là *Luôn quét* hoặc *Không quét* (do từng tick "Ghi nhớ lựa chọn") thì app không hỏi. Đổi lại thành *Luôn hỏi*.

**Docker báo chưa cài dù đã cài.** App chỉ tìm lệnh `docker` ở vị trí thường gặp và trong PATH. Hãy mở Docker, bấm **Kiểm tra lại**. Nếu bạn cài ở chỗ khác thường, hãy thêm thư mục chứa lệnh `docker` vào PATH.

**Quét rất lâu.** Ổ HDD, USB 2.0, ổ có hàng triệu file sẽ chậm. Dùng **Huỷ quét** hoặc bỏ tick ổ đó ở hộp thoại ổ rời.

**Xoá nhầm.** Mở Thùng rác và khôi phục (xem [mục 9](#9-xoá-và-khôi-phục)). Riêng file trên USB/thẻ nhớ của Windows đã xoá vĩnh viễn thì không khôi phục được bằng app.

**Đặt lại mọi cài đặt.** **Cài đặt › Khôi phục mặc định**, hoặc xoá file cài đặt ở [mục 15](#15-dữ-liệu-của-app-và-cách-gỡ-cài-đặt).

**Báo lỗi.** Mở issue tại <https://github.com/datnthutech/clean-my-mac/issues> kèm hệ điều hành, phiên bản app (**Cài đặt › Thông tin**) và các bước tái hiện.

---

## 15. Dữ liệu của app và cách gỡ cài đặt

App lưu hai thứ, đều là file cục bộ nhỏ:

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Cài đặt | Tuỳ chọn người dùng của app (`com.datnthutech.cleanmymac`) | `%LOCALAPPDATA%\CleanMyMac\settings.json` |
| Nhật ký xoá | `~/Library/Application Support/CleanMyMac/deletion-log.json` | `%LOCALAPPDATA%\CleanMyMac\deletion-log.json` |

**Gỡ cài đặt**
- 🍎 Kéo **Clean My Mac** từ Applications vào Thùng rác. Muốn xoá cả dữ liệu: xoá thư mục `~/Library/Application Support/CleanMyMac` và chạy `defaults delete com.datnthutech.cleanmymac`.
- 🪟 Xoá thư mục bạn đã giải nén. Muốn xoá cả dữ liệu: xoá thư mục `%LOCALAPPDATA%\CleanMyMac`. App không ghi gì vào Registry.

---

## 16. Câu hỏi thường gặp

**Vì sao tổng dung lượng khác với "Giới thiệu về máy Mac này" / dung lượng ổ trong Explorer?** Hệ điều hành tính cả phần không liệt kê được thành file (🍎 snapshot APFS, swap, dung lượng purgeable; 🪟 điểm khôi phục, metadata NTFS). App hiển thị phần này là *Dữ liệu hệ thống & không đọc được*. Dung lượng trống app dùng là con số giống Finder / Explorer.

**Quét có làm chậm máy không?** App đọc thư mục song song và chỉ đọc thông tin file (không đọc nội dung), thường mất từ vài chục giây đến vài phút. Có thể huỷ bất cứ lúc nào.

**Ổ mạng (NAS, SMB) có được quét không?** Không, vì quét qua mạng rất chậm.

**App có gửi dữ liệu đi đâu không?** Không. App không kết nối mạng.

**Có tự cập nhật không?** Chưa. Tải bản mới ở trang Releases rồi thay bản cũ.

**Vì sao Mac chỉ có `.dmg` còn Windows là `.zip`?** `.dmg` là định dạng cài đặt chuẩn của macOS. Bản Windows hiện là bản portable (không cần cài). Trình cài đặt `Setup.exe` nằm trong hướng phát triển tiếp theo, xem [PLAN.md](PLAN.md).
