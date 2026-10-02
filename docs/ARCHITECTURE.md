# Kiến trúc ứng dụng

Tài liệu cho người phát triển: dự án được tổ chức thế nào, dữ liệu đi qua những đâu, và nên sửa ở chỗ nào.

## 1. Tổng quan hai tầng

```
┌──────────────────────────── App (SwiftUI, macOS 13+) ────────────────────────────┐
│  Views/        → chỉ hiển thị + gọi hành động trên AppState                        │
│  State/        → AppState (nguồn dữ liệu duy nhất), AppSettings (UserDefaults)    │
│  Localization/ → Localizer: tra chuỗi vi/en, định dạng số/ngày/dung lượng          │
└───────────────────────────────────────┬──────────────────────────────────────────┘
                                        │ gọi API thuần Swift (không phụ thuộc UI)
┌───────────────────────────────────────▼──────────────────────────────────────────┐
│                       DiskKit (Swift Package, có unit test)                       │
│  Volumes/   Scanner/   Analysis/   Docker/   Health/   Trash/   Layout/   System/ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **DiskKit** chứa toàn bộ logic: quét, phân loại, tìm trùng tên, Docker, đánh giá mức độ, xoá an toàn. Không import SwiftUI/AppKit nên test được bằng `swift test`, kể cả trên Linux.
- **App** chỉ lo giao diện và điều phối. Mọi thao tác nặng chạy trong `Task.detached`, kết quả được gán lại cho `AppState` trên main actor.

## 2. Cấu trúc thư mục

```
clean-my-mac/
├── project.yml                     # XcodeGen → sinh CleanMyMac.xcodeproj (không commit .xcodeproj)
├── Makefile                        # make build / test / open / run …
├── App/
│   ├── Sources/
│   │   ├── App/CleanMyMacApp.swift # @main, WindowGroup + Settings, menu commands (⌘R, ⌘., ⌘?)
│   │   ├── State/
│   │   │   ├── AppState.swift      # trạng thái + luồng quét, trùng tên, Docker, xoá, điều hướng
│   │   │   └── AppSettings.swift   # tuỳ chọn người dùng (ngôn ngữ, ngưỡng, ổ rời…)
│   │   ├── Localization/Localizer.swift
│   │   └── Views/
│   │       ├── RootView.swift      # NavigationSplitView + sheet/alert toàn cục
│   │       ├── Sidebar/            # danh sách ổ đĩa + công cụ
│   │       ├── Summary/            # màn Tóm tắt, FindingPresenter (finding → câu chữ)
│   │       ├── Drive/              # chi tiết ổ: Phân loại, Thư mục + Treemap, File lớn
│   │       ├── Duplicates/         # file trùng tên
│   │       ├── Docker/             # 4 bước Docker
│   │       ├── Log/                # nhật ký xoá
│   │       ├── Help/               # hướng dẫn sử dụng trong app
│   │       ├── Settings/  Onboarding/
│   │       └── Common/             # Theme (màu), Components, Sheets (xác nhận, tiến trình)
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       ├── vi.lproj/Localizable.strings
│       └── Assets.xcassets         # AppIcon (sinh bởi scripts/generate_icon.py), AccentColor
├── Packages/DiskKit/
│   ├── Sources/DiskKit/
│   │   ├── Models/      FileTree (DirectoryNode, FileEntry, ScanResult), ByteFormatter
│   │   ├── Volumes/     VolumeInfo, VolumeClassifier, VolumeService (+ ScanTarget cho từng ổ)
│   │   ├── Scanner/     DiskScanner, DirectoryReader (POSIX), BulkDirectoryReader (getattrlistbulk)
│   │   ├── Analysis/    Categorizer + Hotspot, LargeFileFinder, DuplicateFinder
│   │   ├── Docker/      CommandRunner (Process), DockerService, DockerSizeParser
│   │   ├── Health/      Severity, HealthPolicy, Finding, SummaryBuilder
│   │   ├── Trash/       TrashGuard, TrashService, DeletionLog
│   │   ├── Layout/      TreemapLayout (squarified)
│   │   └── System/      FullDiskAccess
│   └── Tests/DiskKitTests/
├── scripts/            build.sh, make_dmg.sh, check_localization.py, generate_icon.py, test_linux.sh
├── .github/workflows/  ci.yml (test + build DMG), release.yml (tag v* → GitHub Release)
└── docs/               PLAN.md, ARCHITECTURE.md, USER_GUIDE.md, USER_GUIDE.en.md, DESIGN.md
```

## 3. Luồng chính

### 3.1 Quét ("Quét tất cả")

```
scanAll()
 ├─ refreshVolumes()                       VolumeService.mountedVolumes()
 ├─ có ổ rời?  không → startScan(ổ trong)
 │             có    → theo Cài đặt: luôn hỏi → ExternalDriveSheet → resolveExternalPrompt()
 │                                     luôn quét / không quét → startScan(...)
 └─ runScans(list)  — tuần tự từng ổ:
      ScanTarget  = VolumeService.scanTarget(volume)   (thiết bị được phép, đường dẫn loại trừ)
      Task.detached:
        DiskScanner.scan()          ← N luồng đọc thư mục song song
        Categorizer.report()        ← phân loại + hotspot
        LargeFileFinder             ← top file lớn
      poller cập nhật ScanProgress mỗi 150 ms → ScanProgressCard
   sau khi xong tất cả:
      findDuplicates()  → DuplicateFinder.find(trên mọi ổ đã quét)
      refreshDocker()   → DockerService.report()
      rebuildFindings() → SummaryBuilder.findings()
```

**Bộ quét (`DiskScanner`)**
- Một ngăn xếp công việc dùng chung + `NSCondition`; tối đa `min(2 × số nhân, 16)` luồng.
- macOS dùng `getattrlistbulk` (một lệnh gọi trả về tên, loại, dung lượng của nhiều mục) — nhanh hơn nhiều so với `lstat` từng file. Linux dùng `readdir` + `lstat`. Test `testBulkReaderMatchesPOSIXReader` bảo đảm hai cách cho cùng kết quả.
- Độ chính xác: dung lượng thực chiếm (allocated), hardlink đếm 1 lần theo (device, inode), không đi theo symlink, không vào thiết bị khác ngoài `allowedDevices`.
- Ổ khởi động: cho phép thiết bị của `/` và `/System/Volumes/Data`, loại `/System/Volumes` để không đếm trùng dữ liệu firmlink.
- Tổng dung lượng thư mục tính một lần sau khi quét (`finalize()`), các con được sắp xếp lớn → nhỏ.

### 3.2 Docker — bắt buộc đi theo thứ tự

```
status():  locateBinary()  ──không thấy──▶ .notInstalled   (không chạy lệnh nào)
              │
           docker info     ──lỗi/timeout─▶ .notRunning
              │
           .running ─▶ danglingImages() + diskUsage() + virtualDiskBytes()
xoá:       docker image rm <id>   (không --force → image đang dùng sẽ bị Docker từ chối)
```

### 3.3 Xoá an toàn

```
View → state.requestTrash(items)
        TrashGuard chia thành allowed / blocked
     → TrashConfirmSheet (số mục, tổng dung lượng, mục bị chặn)
     → performTrash: TrashService.moveToTrash (FileManager.trashItem)
        cập nhật cây (removeItem), file lớn, nhóm trùng tên, phân loại
        ghi DeletionLog (~/Library/Application Support/CleanMyMac/deletion-log.json)
```

## 4. Mức độ nghiêm trọng (`Health.swift`)

| Mức | Điều kiện mặc định |
|---|---|
| Nghiêm trọng | Ổ khởi động < 10 GB, hoặc bất kỳ ổ nào < 5% |
| Cảnh báo | Ổ khởi động < 20 GB, hoặc bất kỳ ổ nào < 10% |
| Gợi ý | Hotspot ≥ 1 GB, Docker `<none>`, nhóm trùng tên |

Hotspot ≥ 10 GB và Docker `<none>` ≥ 5 GB được nâng lên Cảnh báo. Ngưỡng GB chỉ áp dụng cho ổ khởi động.

## 5. Đa ngôn ngữ

- Chuỗi nằm trong `App/Resources/{vi,en}.lproj/Localizable.strings`.
- `Localizer.t("key", args…)` tra theo ngôn ngữ đang chọn (đổi ngay không cần khởi động lại). Tham số luôn là `%@` và truyền dạng String.
- `scripts/check_localization.py` (chạy trong CI) bảo đảm mọi key dùng trong code có đủ ở cả 2 ngôn ngữ và số placeholder khớp nhau. Khi thêm key động (ghép từ enum), bổ sung vào `DYNAMIC_KEYS` trong script.

## 6. Build & phát hành

| Lệnh | Việc làm |
|---|---|
| `make build` | Cài XcodeGen nếu thiếu → kiểm tra bản dịch → `swift test` → sinh project → build Release universal (arm64 + x86_64) → ký ad-hoc → DMG trong `build/` |
| `make open` | Sinh project và mở trong Xcode |
| `make test-linux` | Chạy test DiskKit trong Docker (không cần Mac) |
| CI (`ci.yml`) | Mỗi lần push: test trên Linux + build DMG trên máy ảo macOS, DMG tải về ở mục Artifacts |
| Release (`release.yml`) | Push tag `v1.2.3` → build DMG và đính vào GitHub Release |

Ký & notarize bằng tài khoản Apple Developer: đặt `SIGN_IDENTITY` và `NOTARY_PROFILE` khi chạy `scripts/build.sh`.

## 7. Thêm tính năng mới — nên sửa ở đâu

| Muốn… | Sửa |
|---|---|
| Thêm loại phân loại / quy tắc thư mục | `Analysis/StorageCategory.swift` (+ màu/icon trong `Theme.swift`, chuỗi `category.*`) |
| Thêm thư mục "đáng chú ý" | `HotspotKind` + `hotspotPaths` trong `Categorizer`, chuỗi `hotspot.*` |
| Thêm loại cảnh báo trên Tóm tắt | `FindingKind` + `SummaryBuilder`, câu chữ trong `FindingPresenter` |
| Chặn thêm đường dẫn khỏi bị xoá | `TrashGuard` |
| Thêm màn hình | `SidebarItem` + `DetailRouter` + view mới trong `Views/` |
