# Clean My Mac — Kế hoạch dự án (macOS và Windows)

## 1. Mục tiêu

Giúp người dùng **macOS và Windows** **nắm rõ dung lượng đã dùng, dùng cho mục đích gì**, và dọn dẹp an toàn.
Giao diện chia theo **từng ổ đĩa** (ổ trong + ổ rời đang kết nối).

### Yêu cầu bắt buộc
- Quét **nhanh** và **chính xác**.
- Danh sách sắp xếp theo dung lượng **lớn → nhỏ**.
- Tìm **file trùng tên** sau khi quét xong toàn bộ.
- Quét **Docker image `<none>`** (dangling) — chỉ khi máy có Docker.
- **Gợi ý / cảnh báo** dung lượng trống thấp gây lag máy.
- **Tóm tắt ngắn gọn theo mức độ nghiêm trọng**.

### Quyết định đã chốt
| Hạng mục | Quyết định |
|---|---|
| Phiên bản macOS | **macOS 13 Ventura → macOS 27**, Universal (Intel + Apple Silicon) |
| Phiên bản Windows | **Windows 10 1809 (build 17763) trở lên và Windows 11**, x64 và ARM64 |
| Công nghệ | macOS: Swift + SwiftUI (native). Windows: C# / .NET 8 + WinUI 3, self-contained |
| Cấu trúc repo | Một repo, tách thư mục theo hệ điều hành: `App/` + `Packages/DiskKit` (macOS), `windows/` (Windows) |
| File trùng | **Chỉ cần trùng tên** |
| Xoá file | Cho phép — **chuyển vào Thùng rác**, có xác nhận |
| Ngôn ngữ | **Tiếng Việt + English** |
| Ổ rời | Phát hiện trước, **hỏi xác nhận** rồi mới quét |
| Docker | **Kiểm tra cài đặt + daemon** trước, rồi mới quét / dọn |
| Phát hành | GitHub Release khi đẩy tag `v*`: macOS `.dmg` (hiện ký ad-hoc), Windows `.zip` portable x64 và ARM64 (hiện chưa ký, chưa có `Setup.exe`). Không qua App Store / Microsoft Store vì cần quét toàn đĩa. Xem [RELEASING.md](RELEASING.md) |
| Xoá file | macOS: Thùng rác. Windows: Thùng rác; USB/thẻ nhớ không có → cảnh báo đỏ và xoá vĩnh viễn nếu người dùng đồng ý |

---

## 2. Tính năng chi tiết

> Phần này mô tả theo bản macOS (bản đầu tiên). Bản Windows có cùng tính năng; những chỗ khác (quyền Admin thay Full Disk Access, Thùng rác của Windows, đường dẫn thư mục, phím tắt) xem [hướng dẫn sử dụng, mục 13](USER_GUIDE.md#13-khác-biệt-giữa-bản-macos-và-windows) và [DESIGN.md](DESIGN.md).

### 2.1 Quản lý ổ đĩa
- Liệt kê volume đang mount: tên, loại (trong / rời / USB), định dạng (APFS, HFS+, exFAT…), tổng / đã dùng / còn trống.
- Dung lượng trống lấy theo `volumeAvailableCapacityForImportantUsage` (khớp với Finder, tính cả phần purgeable của APFS).
- Theo dõi **cắm / rút ổ realtime** (NSWorkspace mount/unmount notifications) → sidebar tự cập nhật.
- Bỏ qua ổ mạng (SMB/AFP/NFS) và ổ chỉ đọc của hệ thống.

### 2.2 Luồng xác nhận quét ổ rời
```
Bấm "Quét"
   │
   ├─ Kiểm tra có ổ rời nào đang kết nối? (volumeIsInternal == false, không phải ổ mạng)
   │     ├─ KHÔNG có → chỉ quét ổ trong, không hỏi gì.
   │     └─ CÓ → hiện hộp thoại:
   │           "Phát hiện 2 ổ rời. Bạn có muốn quét luôn không?"
   │           [✓] Samsung T7 (1 TB)   [✓] USB Kingston (64 GB)
   │           [Chỉ quét ổ trong]  [Quét các ổ đã chọn]
   │
   └─ Cắm ổ mới khi app đang mở → thông báo nhỏ: "Đã kết nối ổ X — Quét ngay?"
```

### 2.3 Bộ quét (Scanner)
- **Nhanh:** dùng `getattrlistbulk` (đọc metadata hàng loạt) + quét song song nhiều thư mục (Swift Concurrency, giới hạn số luồng theo số nhân CPU).
- **Chính xác:**
  - Dùng **dung lượng thực chiếm trên đĩa** (allocated size), không dùng kích thước logic.
  - Không đếm trùng **hardlink** (theo inode) và **firmlink** (`/System/Volumes/Data`).
  - Không đi theo symlink; không vượt sang volume khác.
- Hiển thị tiến trình realtime (số file, dung lượng, thư mục đang quét), **huỷ được** giữa chừng.
- Yêu cầu **Full Disk Access**: màn hình hướng dẫn cấp quyền + cảnh báo nếu thiếu (kết quả sẽ không đầy đủ).
- Mục tiêu hiệu năng: ~1 triệu file < 60 giây trên SSD nội bộ; RAM < 500 MB.

### 2.4 Danh sách theo dung lượng
- Cây thư mục + danh sách file, **sắp xếp lớn → nhỏ** (đổi được sang tên / ngày sửa).
- Treemap trực quan, click để đi sâu vào thư mục.
- Tab **File lớn**: Top N file lớn nhất (mặc định ≥ 100 MB).
- Hành động: Mở trong Finder, Xem nhanh (Quick Look), Chuyển vào Thùng rác.

### 2.5 Phân loại "dùng cho mục đích gì"
| Nhóm | Ví dụ |
|---|---|
| Ứng dụng | `/Applications`, `~/Applications` |
| Tài liệu | pdf, doc, xls, key, pages… |
| Ảnh / Video | jpg, heic, png, mov, mp4, Photos Library |
| Nhạc | mp3, m4a, flac |
| Nén / Bộ cài | zip, dmg, pkg, rar |
| Dev | Xcode DerivedData, Simulators, `node_modules`, Homebrew cache, Gradle/CocoaPods |
| Cache | `~/Library/Caches`, cache trình duyệt |
| Sao lưu iOS | `~/Library/Application Support/MobileSync/Backup` |
| Mail / Tin nhắn | `~/Library/Mail`, `~/Library/Messages` |
| Thùng rác | `~/.Trash`, `.Trashes` của ổ rời |
| Docker | Docker.raw / OrbStack / Colima data |
| Khác | Phần còn lại |

Hiển thị dung lượng + % từng nhóm (biểu đồ thanh / donut).

### 2.6 File trùng tên
- Chạy **sau khi quét xong toàn bộ** các ổ đã chọn.
- So khớp tên: **không phân biệt hoa/thường** và **chuẩn hoá Unicode (NFC)** — quan trọng với tên file tiếng Việt (macOS lưu dạng NFD).
- Loại trừ mặc định (bật/tắt trong Cài đặt): `node_modules`, `.git`, bên trong gói `.app`/`.bundle`, thư mục hệ thống, file nhỏ hơn 1 MB (tuỳ chỉnh được).
- Kết quả: mỗi nhóm = 1 tên file + danh sách đường dẫn, kích thước, ngày sửa, ổ đĩa.
- Sắp xếp nhóm theo **tổng dung lượng có thể giải phóng** (tổng − bản lớn nhất) lớn → nhỏ.
- Ghi chú trên UI: *"Trùng tên không đảm bảo trùng nội dung — hãy kiểm tra trước khi xoá."*

### 2.7 Docker — luồng kiểm tra bắt buộc
```
Bước 1: Docker đã cài chưa?
   Tìm `docker` tại: /usr/local/bin, /opt/homebrew/bin, ~/.orbstack/bin,
   /Applications/Docker.app/Contents/Resources/bin  (app GUI không có PATH của Terminal)
   ├─ KHÔNG → Tab Docker hiển thị "Máy chưa cài Docker" — dừng, không chạy lệnh nào.
   └─ CÓ ↓
Bước 2: Docker daemon có đang chạy? (`docker info`, timeout 5s)
   ├─ KHÔNG → "Docker đã cài nhưng chưa chạy" + nút [Mở Docker Desktop] — dừng.
   └─ CÓ ↓
Bước 3: Quét
   - Image <none> (dangling):  docker images -f dangling=true
   - Image không container nào dùng (thông tin thêm)
   - Build cache, tổng quan:   docker system df
Bước 4: Dọn (có xác nhận)
   - Xoá từng image đã chọn: docker image rm <id>
   - Hoặc xoá tất cả <none>:  docker image prune -f
```
- Lưu ý hiển thị: với Docker Desktop, file `Docker.raw` **không nhỏ lại ngay** sau khi xoá image.
- Không bao giờ xoá image đang được container sử dụng.

### 2.8 Cảnh báo dung lượng & Tóm tắt mức độ
| Mức | Điều kiện | Thông điệp gợi ý |
|---|---|---|
| 🔴 Nghiêm trọng | Trống < 10 GB **hoặc** < 5% | Máy có thể lag/treo do thiếu chỗ cho swap; không cài được bản cập nhật macOS (cần ~20–30 GB) |
| 🟠 Cảnh báo | Trống < 20 GB **hoặc** < 10% | SSD ghi chậm hơn, snapshot Time Machine cục bộ bị xoá, ứng dụng nặng chạy chậm |
| 🟢 Ổn | Còn lại | Dung lượng khoẻ mạnh |

Thẻ **Tóm tắt** sau mỗi lần quét, ví dụ:
> 🔴 Macintosh HD chỉ còn 8 GB (3%) — nguy cơ lag máy
> 🟠 Docker: 12 image `<none>` chiếm 6.4 GB
> 🟠 Thùng rác chiếm 4.1 GB
> 🔵 37 nhóm file trùng tên — có thể giải phóng ~2.3 GB
> 🔵 Xcode DerivedData chiếm 15 GB

Mỗi dòng có nút **[Xem]** dẫn tới tab liên quan. Ngưỡng là khuyến nghị kinh nghiệm, chỉnh được trong Cài đặt.

### 2.9 Xoá an toàn
- Luôn dùng `FileManager.trashItem` → vào Thùng rác (ổ rời dùng `.Trashes` riêng của ổ đó), khôi phục được bằng "Put Back" trong Finder.
- Hộp thoại xác nhận: số mục + tổng dung lượng.
- **Chặn xoá**: `/System`, `/usr`, `/bin`, `/sbin`, `/Library` hệ thống, chính app này, thư mục gốc của volume.
- Lưu nhật ký các mục đã xoá (xem lại trong app).

### 2.10 Đa ngôn ngữ
- String Catalog (`Localizable.xcstrings`): **vi** + **en**.
- Mặc định theo ngôn ngữ hệ thống; đổi được trong Cài đặt.
- Định dạng dung lượng / số / ngày theo locale (`ByteCountFormatter`, `FormatStyle`).

---

## 3. Giao diện

**Mẫu thiết kế đầy đủ (6 màn hình):** https://claude.ai/artifact/SrnoYTUQTpu9VbmCPEiELa — mô tả chi tiết trong [DESIGN.md](DESIGN.md).

1. Tóm tắt · 2. Chi tiết ổ đĩa (Phân loại / Thư mục + Treemap / File lớn) · 3. File trùng tên · 4. Docker · 5. Xác nhận ổ rời & tiến trình quét · 6. Hướng dẫn sử dụng

```
┌──────────────────┬────────────────────────────────────────────────┐
│ Ổ ĐĨA            │  Macintosh HD          🟠 Còn 14 GB (5%)          │
│ 💻 Macintosh HD 🟠│  ███████████████████░  242 / 256 GB   [Quét]     │
│ 💾 Samsung T7  🟢 ├────────────────────────────────────────────────┤
│ 🔌 USB 64GB    🟢 │  Tóm tắt | Phân loại | File lớn | Trùng tên | 🐳  │
│──────────────────│                                                │
│ CÔNG CỤ          │  ┌── Treemap ──────────┐  ┌── Danh sách ↓ ─────┐ │
│ 🐳 Docker        │  │                     │  │ Library    82.1 GB │ │
│ 🗑 Đã xoá        │  │                     │  │ Developer  40.3 GB │ │
│ ⚙️ Cài đặt        │  └─────────────────────┘  │ Movies     22.7 GB │ │
└──────────────────┴────────────────────────────────────────────────┘
```
- macOS: `NavigationSplitView` (sidebar ổ đĩa + công cụ / nội dung chính), Light / Dark mode, màn hình chào hướng dẫn cấp Full Disk Access.
- Windows: `NavigationView` (ngăn trái luôn mở), giao diện Fluent / Mica, màn hình chào có nút Khởi động lại với quyền Admin.
- Cả hai: menu luôn hiện trên mọi trang, trang cuộn thay vì tràn viền. Đối chiếu chi tiết ở [DESIGN.md](DESIGN.md).

---

## 4. Kiến trúc & cấu trúc ứng dụng

Chi tiết: [ARCHITECTURE.md](ARCHITECTURE.md). Tóm tắt:

| Tầng | Thư mục | Trách nhiệm |
|---|---|---|
| Giao diện | `App/Sources/Views/` | Mỗi màn hình một thư mục (Sidebar, Summary, Drive, Duplicates, Docker, Log, Help, Settings, Onboarding, Common) |
| Trạng thái | `App/Sources/State/` | `AppState` — nguồn dữ liệu duy nhất, điều phối quét / Docker / xoá; `AppSettings` — tuỳ chọn |
| Ngôn ngữ | `App/Sources/Localization/`, `App/Resources/{vi,en}.lproj` | Tra chuỗi theo ngôn ngữ đang chọn, đổi ngay |
| Logic | `Packages/DiskKit/` | Volumes · Scanner · Analysis · Docker · Health · Trash · Layout · System — không phụ thuộc UI, có unit test |
| Logic (Windows) | `windows/src/DiskKit.Core/` | Bản C# của cùng các mô-đun, thêm đọc thư mục hàng loạt của Windows, Recycle Bin, phát hiện USB; có unit test chạy được trên mọi hệ điều hành |
| Giao diện (Windows) | `windows/src/CleanMyMac.App/` | WinUI 3: `MainWindow`, `State/`, `Pages/`, `UI/`, `Localization/` (nạp chung file `.strings` của macOS) |
| Build | `project.yml`, `Makefile`, `scripts/`, `global.json`, `.github/workflows/` | Sinh project, test, build universal + DMG, publish Windows, CI, Release |

## 4b. Hướng dẫn sử dụng

- **Trong app**: mục *Hướng dẫn sử dụng* ở menu bên trái (macOS: ⌘?) — 9 chủ đề, song ngữ; macOS có nút mở Cài đặt hệ thống cho Full Disk Access, Windows có nút Khởi động lại với quyền Admin.
- **Tài liệu**: [USER_GUIDE.md](USER_GUIDE.md) (Tiếng Việt), [USER_GUIDE.en.md](USER_GUIDE.en.md) (English) — thống nhất cho cả macOS và Windows: tải đúng file ở trang Releases, cài đặt từng hệ điều hành, quét, mức độ cảnh báo, từng màn hình, xoá và khôi phục, phím tắt, khác biệt giữa hai bản, xử lý sự cố, dữ liệu và gỡ cài đặt, FAQ.
- **Dành cho người duy trì**: [RELEASING.md](RELEASING.md), [ARCHITECTURE.md](ARCHITECTURE.md), [CHANGELOG.md](../CHANGELOG.md).
- **Lần mở đầu**: màn hình chào giới thiệu tính năng, chọn ngôn ngữ, hướng dẫn cấp quyền.

## 5. Lộ trình & trạng thái

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Khung dự án: XcodeGen, DiskKit, CI, vi/en | ✅ |
| 1 | Ổ đĩa, mount/unmount realtime, cảnh báo dung lượng, sidebar, xác nhận ổ rời | ✅ |
| 2 | Scanner nhanh + chính xác, tiến trình, huỷ, Full Disk Access, danh sách lớn → nhỏ, treemap, File lớn | ✅ |
| 3 | Phân loại theo mục đích sử dụng + thư mục đáng chú ý | ✅ |
| 4 | File trùng tên | ✅ |
| 5 | Docker 4 bước | ✅ |
| 6 | Tóm tắt mức độ, xoá vào Thùng rác + chặn + nhật ký, Cài đặt | ✅ |
| 7 | Icon, build universal, DMG, CI/Release tự động, hướng dẫn sử dụng (macOS) | ✅ (ký Developer ID + notarize: cần tài khoản Apple Developer) |
| 8 | **Bản Windows** (WinUI 3, Windows 10 1809+, x64 & ARM64): logic C#, đủ 6 trang, CI build + chạy thử | ✅ |
| 9 | Sửa lỗi giao diện: tràn viền (Trùng tên), menu luôn hiện trên mọi trang (cả hai bản) | ✅ |
| 10 | **Phát hành `v1.0.0-beta.1`** (GitHub Release: DMG + zip Windows x64/ARM64) và cải tiến workflow Release (tuần tự, checksum, ghi chú, pre-release) | ✅ |
| 11 | Tài liệu hợp nhất macOS + Windows, RELEASING.md, CHANGELOG.md | ✅ |

## 6. Kiểm thử

- **Unit test macOS** (`Packages/DiskKit/Tests`, 35 test): tính dung lượng (hardlink, symlink, thiết bị khác), phân loại, gom trùng tên (hoa/thường, NFC/NFD), ngưỡng cảnh báo, parse output Docker, danh sách chặn xoá, treemap, so khớp bộ đọc `getattrlistbulk` với `lstat`. Chạy trên macOS và Linux (`make test-linux`).
- **Unit test Windows** (`windows/tests`, 29 test case): cùng các nhóm trên, thêm bộ đọc thư mục Windows (so khớp với bộ đọc .NET, hard link chỉ đếm một lần) và `TrashGuard` với đường dẫn Windows. Chạy trên Windows và Linux.
- **Kiểm tra bản dịch** (`scripts/check_localization.py`): mọi khoá dùng trong code của **cả hai app** có đủ ở tiếng Việt và tiếng Anh, số `%@` khớp nhau.
- **CI** (`ci.yml`, mỗi lần push): test Linux; build macOS universal + DMG; build Windows x64 và ARM64. **Chạy thử app thật** trên macOS 15 và Windows Server 2025: mở từng trang (kể cả khi chưa quét), quét hệ thống thật, chụp màn hình, thất bại nếu app thoát bất thường. Ảnh chụp giúp kiểm tra menu luôn hiện và không tràn viền.
- **Chưa có kiểm thử tự động** cho: cắm/rút ổ rời thật, xoá file thật vào Thùng rác, xoá image Docker thật, hộp thoại ổ rời, giao diện từng thao tác bấm/nháy đúp. Phần này cần thử thủ công trên máy thật (xem mục 8).

## 7. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Thiếu quyền đọc thư mục bảo vệ (🍎 Full Disk Access, 🪟 Admin) → kết quả thiếu | Màn hình chào, banner/gợi ý, đánh dấu vùng "không đọc được", nút mở Cài đặt / khởi động lại với quyền Admin |
| Trùng tên ≠ trùng nội dung → user xoá nhầm | Ghi chú rõ trên UI, không cho xoá hết mọi bản, chỉ vào Thùng rác, khôi phục được |
| Khác biệt API giữa các bản hệ điều hành | macOS: `#available`, deployment target 13.0, CI SDK mới. Windows: nhắm Windows 10 1809, bộ đọc thư mục có bản dự phòng .NET |
| Docker.raw / `.vhdx` không nhỏ lại sau khi dọn | Giải thích trên UI và trong hướng dẫn |
| Ổ rời lớn / chậm (HDD, USB 2.0) | Hỏi trước khi quét, hiển thị tiến trình, huỷ được |
| 🪟 Xoá trên USB/thẻ nhớ (không có Thùng rác) là xoá vĩnh viễn | Cảnh báo đỏ + nút "Xoá vĩnh viễn" trong hộp thoại; **chưa kiểm thử trên thiết bị thật** |
| Bản dựng chưa ký số → cảnh báo Gatekeeper/SmartScreen | Hướng dẫn vượt qua trong tài liệu và ghi chú Release; lộ trình ký số ở mục 8 |
| Tag gắn nhầm vào commit cũ → Release dùng workflow cũ | Dùng `git tag vX origin/main`; xem [RELEASING.md](RELEASING.md) |
| Tên "CleanMyMac" là thương hiệu của MacPaw | Đổi tên trước khi phát hành công khai (xem README) |

## 8. Hạn chế đã biết và hướng phát triển tiếp theo

**Hiện trạng:** bản beta `v1.0.0-beta.1` đã phát hành, có đủ file cho macOS và Windows. Dưới đây là những việc còn thiếu; thứ tự là **đề xuất**, chưa phải cam kết.

### Cần làm trước khi phát hành rộng rãi
1. **Thử trên thiết bị thật** và ghi lại kết quả: cắm USB/SSD rời (cả hai hệ điều hành), xoá file thật trên USB (Windows), Docker có image `<none>`, Windows 10 bản 1809, máy ARM64, macOS 13/14/26.
2. **Đổi tên** sản phẩm (tránh trùng thương hiệu MacPaw) và thêm file **`LICENSE`**.
3. **Ký số**: Apple Developer ID + notarize (macOS), chứng chỉ ký code (Windows) rồi nối vào `release.yml` — xem [RELEASING.md](RELEASING.md#6-ký-số-và-notarize-chưa-bật).
4. **Trình cài đặt Windows** (`Setup.exe` bằng Inno Setup hoặc MSIX): lối tắt Start Menu, mục gỡ cài đặt. Hiện chỉ có zip portable.

### Cải thiện trải nghiệm
5. Bản Windows: **phím tắt** và **menu chuột phải** cho bằng bản macOS; thêm mục "Hiện màn hình chào" trong Cài đặt.
6. **Tự kiểm tra bản mới** (hoặc ít nhất nhắc khi có bản mới).
7. So khớp **nội dung** (băm file) bên cạnh so khớp tên, để giảm nhầm lẫn khi tìm file trùng (hiện chỉ so tên theo yêu cầu ban đầu).
8. Thêm ngôn ngữ khác (cấu trúc chuỗi đã sẵn sàng).
9. Dọn thêm Docker: build cache, volume không dùng (hiện chỉ xoá image `<none>`).

### Hạ tầng
10. Chạy thử trên nhiều phiên bản hệ điều hành trong CI (macOS 13/14, Windows 10), nếu runner hỗ trợ.
11. Test giao diện tự động cho các luồng bấm nút (xác nhận ổ rời, xác nhận xoá).
