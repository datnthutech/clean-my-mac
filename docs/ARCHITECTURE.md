# Kiến trúc ứng dụng (macOS và Windows)

Tài liệu cho người phát triển: dự án được tổ chức thế nào, dữ liệu đi qua những đâu, và nên sửa ở chỗ nào.

Một repo, **hai ứng dụng gốc** (không dùng chung mã giữa hai bản, vì khác ngôn ngữ và API hệ thống), tách thư mục theo hệ điều hành và dùng **cùng kiến trúc hai tầng, cùng tên mô-đun, cùng câu chữ**:

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Giao diện | `App/` (SwiftUI) | `windows/src/CleanMyMac.App` (WinUI 3) |
| Logic (có test) | `Packages/DiskKit` (Swift) | `windows/src/DiskKit.Core` (C#) |
| Test | `Packages/DiskKit/Tests` (35) | `windows/tests/DiskKit.Core.Tests` (29) |
| Bản dịch | `App/Resources/{vi,en}.lproj` | nạp **chung** file trên + ghi đè trong `Strings/*.strings` |
| Phần cuối tài liệu này | mục 1–7 | mục 8 |

Muốn thêm hay sửa một tính năng thì thường phải sửa **cả hai** bản; bảng ở mục 7 chỉ rõ chỗ sửa.

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
├── windows/            Bản Windows (xem mục 8): src/DiskKit.Core, src/CleanMyMac.App, tests/
├── global.json         Ghim .NET SDK 8 cho bản Windows
├── scripts/            build.sh, make_dmg.sh, check_localization.py, check_docs.py, generate_icon.py, test_linux.sh, windows-smoke.ps1
├── .github/workflows/  ci.yml (test + build + chạy thử cả hai app), release.yml (tag v* → GitHub Release)
├── CHANGELOG.md        Nhật ký thay đổi
└── docs/               PLAN, ARCHITECTURE, DESIGN, RELEASING, USER_GUIDE (vi), USER_GUIDE.en, ảnh chụp màn hình
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

## 4. Mức độ nghiêm trọng (🍎 `Health.swift` · 🪟 `Health/Health.cs`)

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

### Lệnh thường dùng

| Lệnh | Việc làm |
|---|---|
| 🍎 `make build` | Cài XcodeGen nếu thiếu → kiểm tra bản dịch → `swift test` → sinh project → build Release universal (arm64 + x86_64) → ký ad-hoc → DMG trong `build/` |
| 🍎 `make open` / `make run` | Sinh project và mở trong Xcode / build rồi mở app |
| 🍎 `make test` / `make test-linux` | Test DiskKit trên Mac / trong Docker (không cần Mac) |
| 🪟 `dotnet publish windows/src/CleanMyMac.App -c Release -r win-x64 -p:Platform=x64 -o windows/artifacts/win-x64` | Build Windows self-contained (`win-arm64` + `-p:Platform=ARM64` cho ARM64); cần .NET SDK 8 trên Windows |
| 🪟 `dotnet test windows/tests/DiskKit.Core.Tests` | Test logic Windows; chạy được trên mọi hệ điều hành (test chỉ dành cho Windows tự bỏ qua ở nơi khác) |
| `python3 scripts/check_localization.py` | Kiểm tra bản dịch của cả hai app |
| `python3 scripts/check_docs.py` | Kiểm tra mọi liên kết, ảnh và neo (anchor) trong README, CHANGELOG, `docs/*.md` (chạy cả trong CI) |

### Lưu ý khi build Windows
- **`global.json` ở gốc repo ghim .NET SDK 8** để build giống hệt CI. Lần build Windows đầu tiên trên CI dùng SDK 10 cài sẵn trên runner và lỗi ở bước đóng gói; sau khi ghim SDK 8 và bật `EnableMsixTooling` (bên dưới) thì build thành công. Chưa thử SDK 10 cùng `EnableMsixTooling`. `global.json` chỉ có hiệu lực khi nằm ở thư mục chạy lệnh hoặc cao hơn, nên đặt ở gốc repo (đặt trong `windows/` thì không đủ khi chạy lệnh từ gốc).
- `CleanMyMac.App.csproj` bật `EnableMsixTooling` để `dotnet publish` chạy được mà không cần Visual Studio.
- Ứng dụng không đóng gói MSIX (`WindowsPackageType=None`) và self-contained (`WindowsAppSDKSelfContained`), nên thư mục publish chạy được ngay, không cần cài runtime. Nhắm `net8.0-windows10.0.19041.0`, tối thiểu Windows 10 1809 (`TargetPlatformMinVersion` 10.0.17763.0).
- Phần giao diện (XAML/WinUI) chỉ build được trên Windows; phần logic và test build được ở mọi nơi.

### CI (`ci.yml`, mỗi lần push)

| Job | Việc làm |
|---|---|
| `core-linux` | `swift test` (Linux) + kiểm tra bản dịch |
| `macos` | `scripts/build.sh` (test + build universal + DMG), chạy thử app: mở từng trang, quét thật, chụp màn hình; đăng `CleanMyMac-dmg` và ảnh |
| `windows` (x64, ARM64) | kiểm tra bản dịch, `dotnet test` (x64), `dotnet publish`, zip; x64 chạy thử bằng `scripts/windows-smoke.ps1` (mở 8 trang, quét thật, chụp màn hình); đăng `CleanMyMac-windows-*` và ảnh |

### Release (`release.yml`, khi đẩy tag `v*`)
Job macOS tạo GitHub Release (DMG + `.sha256` + ghi chú) rồi hai job Windows đính zip + `.sha256` vào cùng Release; tag có dấu `-` là Pre-release. Cách thực hiện, kiểm tra, xử lý sự cố, ký số: [RELEASING.md](RELEASING.md).

Ký & notarize macOS bằng tài khoản Apple Developer: đặt `SIGN_IDENTITY` và `NOTARY_PROFILE` khi chạy `scripts/build.sh` (chưa nối vào workflow).

## 7. Thêm tính năng mới — nên sửa ở đâu

| Muốn… | Sửa |
|---|---|
| Thêm loại phân loại / quy tắc thư mục | `Analysis/StorageCategory.swift` (+ màu/icon trong `Theme.swift`, chuỗi `category.*`) |
| Thêm thư mục "đáng chú ý" | `HotspotKind` + `hotspotPaths` trong `Categorizer`, chuỗi `hotspot.*` |
| Thêm loại cảnh báo trên Tóm tắt | `FindingKind` + `SummaryBuilder`, câu chữ trong `FindingPresenter` |
| Chặn thêm đường dẫn khỏi bị xoá | `TrashGuard` |
| Thêm màn hình | 🍎 `SidebarItem` + `DetailRouter` + view mới trong `Views/` · 🪟 `NavItem` + `MainWindow.Render` + `IPage` mới trong `Pages/` |
| Thêm chuỗi giao diện | 🍎 `App/Resources/{vi,en}.lproj/Localizable.strings` (🪟 dùng lại tự động) · chuỗi riêng Windows: `windows/src/CleanMyMac.App/Strings/{en,vi}.strings` · rồi chạy `scripts/check_localization.py` |
| Phần việc tương ứng ở bản Windows | `windows/src/DiskKit.Core/` (cùng tên mô-đun: Analysis, Docker, Health, Trash, Scanner, Volumes, Layout) |

## 8. Bản Windows (`windows/`)

Cùng kiến trúc hai tầng, viết bằng C# / .NET 8 + WinUI 3 (Windows App SDK 1.6, hỗ trợ Windows 10 1809+, x64 và ARM64, self-contained, không cần cài runtime).

```
windows/
├── src/DiskKit.Core/            # logic thuần, build & test được trên mọi hệ điều hành
│   ├── Models/FileTree.cs       # DirectoryNode, FileEntry, ScanResult, ByteFormatter
│   ├── Scanner/Scanner.cs       # DiskScanner (đa luồng), ManagedDirectoryReader
│   ├── Interop/WindowsBulkDirectoryReader.cs   # GetFileInformationByHandleEx: tên + size on disk + File ID hàng loạt
│   ├── Volumes/Volumes.cs       # VolumeClassifier, VolumeService (phát hiện USB qua IOCTL)
│   ├── Analysis/Analysis.cs     # Categorizer + Hotspot (đường dẫn Windows), LargeFileFinder, DuplicateFinder
│   ├── Docker/Docker.cs         # DockerService (cài đặt → chạy → quét → dọn), DockerSize
│   ├── Health/Health.cs         # HealthPolicy, SummaryBuilder
│   ├── Trash/Trash.cs           # TrashGuard, RecycleBinService (SHFileOperation), DeletionLog, Elevation
│   └── Layout/Treemap.cs        # squarified treemap
├── src/CleanMyMac.App/          # WinUI 3
│   ├── MainWindow.cs            # NavigationView (menu luôn mở, không thu gọn được) + PageHost (cuộn khi cửa sổ hẹp, trang lỗi không làm mất menu)
│   ├── State/                   # AppState (nguồn dữ liệu duy nhất), AppSettings
│   ├── Pages/                   # Summary, Drive, Duplicates, Docker, Log, Help, Settings
│   ├── UI/                      # Theme, Ui (helper dựng giao diện), DialogService, TreemapControl
│   ├── Localization/            # Localizer: đọc chung file .strings của macOS + ghi đè riêng Windows
│   └── Strings/{en,vi}.strings  # chuỗi riêng Windows
└── tests/DiskKit.Core.Tests/    # 29 test case (xUnit)
```

- **Bản dịch dùng chung**: `Localizer` nạp `App/Resources/{vi,en}.lproj/Localizable.strings` của bản macOS, rồi ghi đè bằng `Strings/*.strings` của Windows. `scripts/check_localization.py` kiểm tra cả hai app.
- **Quét**: `GetFileInformationByHandleEx(FileIdBothDirectoryInfo)` trả về dung lượng thực chiếm (AllocationSize) và File ID, nên hard link (WinSxS) chỉ tính một lần; junction/symlink (ReparsePoint) không bị đi theo.
- **Xoá**: `SHFileOperation` với cờ `FOF_ALLOWUNDO` + `FOF_WANTNUKEWARNING`; ổ không có Thùng rác (USB/thẻ nhớ) được cảnh báo riêng.
- **Menu luôn hiện**: `NavigationView.PaneClosing` bị huỷ, `IsPaneToggleButtonVisible=false`; lỗi khi dựng một trang chỉ hiện panel lỗi trong vùng nội dung; `App.UnhandledException` không để app thoát.
- **CI** (`ci.yml`, job `windows`): kiểm tra bản dịch → `dotnet test` → `dotnet publish` (x64, ARM64) → zip → chạy thử app trên 8 trang + quét thật, chụp màn hình.
- Chạy cục bộ trên Linux/macOS: `dotnet test windows/tests/DiskKit.Core.Tests` (phần logic). Giao diện chỉ build được trên Windows.
- **Hạn chế hiện tại của bản Windows:** chưa có phím tắt và menu chuột phải; chưa có `Setup.exe` (zip portable); chưa ký số; chưa kiểm thử xoá trên USB/thẻ nhớ thật. Xem [PLAN.md](PLAN.md#8-hạn-chế-đã-biết-và-hướng-phát-triển-tiếp-theo).
