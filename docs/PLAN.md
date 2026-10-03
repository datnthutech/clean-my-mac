# Clean My Mac — Kế hoạch dự án (bản chốt)

## 1. Mục tiêu

Giúp người dùng macOS **nắm rõ dung lượng đã dùng, dùng cho mục đích gì**, và dọn dẹp an toàn.
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
| Công nghệ | Swift + SwiftUI (native) |
| File trùng | **Chỉ cần trùng tên** |
| Xoá file | Cho phép — **chuyển vào Thùng rác**, có xác nhận |
| Ngôn ngữ | **Tiếng Việt + English** |
| Ổ rời | Phát hiện trước, **hỏi xác nhận** rồi mới quét |
| Docker | **Kiểm tra cài đặt + daemon** trước, rồi mới quét / dọn |
| Phát hành | DMG ký + notarize (không qua App Store vì sandbox chặn quét toàn đĩa) |

---

## 2. Tính năng chi tiết

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
- `NavigationSplitView` (sidebar ổ đĩa + công cụ / nội dung chính).
- Hỗ trợ Light / Dark mode.
- Màn hình chào lần đầu: giới thiệu + hướng dẫn cấp Full Disk Access.

---

## 4. Kiến trúc & cấu trúc ứng dụng

Chi tiết: [ARCHITECTURE.md](ARCHITECTURE.md). Tóm tắt:

| Tầng | Thư mục | Trách nhiệm |
|---|---|---|
| Giao diện | `App/Sources/Views/` | Mỗi màn hình một thư mục (Sidebar, Summary, Drive, Duplicates, Docker, Log, Help, Settings, Onboarding, Common) |
| Trạng thái | `App/Sources/State/` | `AppState` — nguồn dữ liệu duy nhất, điều phối quét / Docker / xoá; `AppSettings` — tuỳ chọn |
| Ngôn ngữ | `App/Sources/Localization/`, `App/Resources/{vi,en}.lproj` | Tra chuỗi theo ngôn ngữ đang chọn, đổi ngay |
| Logic | `Packages/DiskKit/` | Volumes · Scanner · Analysis · Docker · Health · Trash · Layout · System — không phụ thuộc UI, có unit test |
| Build | `project.yml`, `Makefile`, `scripts/`, `.github/workflows/` | Sinh project, test, build universal, DMG, CI, Release |

## 4b. Hướng dẫn sử dụng

- **Trong app**: mục *Hướng dẫn sử dụng* ở thanh bên (⌘?) — 9 chủ đề, song ngữ, có nút mở Cài đặt hệ thống cho Full Disk Access.
- **Tài liệu**: [USER_GUIDE.md](USER_GUIDE.md) (Tiếng Việt), [USER_GUIDE.en.md](USER_GUIDE.en.md) (English) — cài đặt, quét, đọc mức độ, từng màn hình, xoá & khôi phục, phím tắt, FAQ.
- **Lần mở đầu**: màn hình chào giới thiệu tính năng, chọn ngôn ngữ, hướng dẫn cấp Full Disk Access.

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
| 7 | Icon, build universal, DMG, CI/Release tự động, hướng dẫn sử dụng | ✅ (ký Developer ID + notarize: cần tài khoản Apple Developer) |

## 6. Kiểm thử
- **Unit test (DiskKit):** tính dung lượng (hardlink, sparse), phân loại, gom trùng tên (hoa/thường, NFC/NFD), ngưỡng cảnh báo, parse output Docker, danh sách chặn xoá.
- **CI:** build + test trên GitHub Actions `macos` runner cho mỗi push.
- **Kiểm thử thủ công trên máy Mac thật** (do người dùng thực hiện): giao diện, Full Disk Access, cắm/rút ổ rời, Docker Desktop / OrbStack.

> Lưu ý: môi trường phát triển hiện tại là Linux, không có Xcode — code được build/test qua CI macOS; phần chạy thử giao diện cần thực hiện trên máy Mac.

## 7. Rủi ro
| Rủi ro | Giảm thiểu |
|---|---|
| Thiếu Full Disk Access → kết quả thiếu | Onboarding + banner cảnh báo + đánh dấu thư mục không đọc được |
| Trùng tên ≠ trùng nội dung → user xoá nhầm | Ghi chú rõ trên UI, chỉ vào Thùng rác, khôi phục được |
| Khác biệt API giữa macOS 13 và 27 | Kiểm tra `#available`, CI build với SDK mới nhất, deployment target 13.0 |
| Docker.raw không nhỏ lại sau khi dọn | Giải thích trên UI |
| Ổ rời lớn / chậm (HDD, USB 2.0) | Hỏi trước khi quét, hiển thị tiến trình, huỷ được |
