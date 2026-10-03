# Clean My Mac — User Guide

> Vietnamese version: [USER_GUIDE.md](USER_GUIDE.md). The same guide is built into the app: sidebar › **User Guide** (⌘?).

Clean My Mac shows **what your disk space is used for**, points out what wastes space and lets you clean up **safely** — everything you remove goes to the Trash first.

Two editions: **macOS** (13 Ventura or later, Apple silicon and Intel) and **Windows** (10 version 1809 or later and Windows 11, x64 and ARM64). Same screens and features; Windows differences are in [section 11](#11-windows-edition).

## 1. Install

**Option A — prebuilt DMG.** GitHub › **Actions** › latest **CI** run › **Artifacts** › `CleanMyMac-dmg` (or **Releases**). Open the DMG and drag the app to Applications. On first launch macOS may block an app signed locally: System Settings › Privacy & Security › **Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"`.

**Option B — build it yourself** (Xcode 15+ and Homebrew):

```bash
git clone https://github.com/datnthutech/clean-my-mac.git
cd clean-my-mac
make build   # installs XcodeGen, runs tests, builds a universal app and a DMG into build/
make run     # build and launch
```

## 2. First launch

Pick a language (Vietnamese / English / same as macOS) and grant **Full Disk Access**: System Settings › Privacy & Security › Full Disk Access › turn on Clean My Mac, then press **Check Again** (quit and reopen if needed). Without it, protected folders such as Mail and Messages are skipped. The app only reads file names and sizes and never uploads anything.

## 3. Scanning

Press **Scan All** (⌘R). Internal drives are always scanned. When external drives are connected, the app first asks which ones to include (tick them, or choose **Internal Drives Only**; **Remember my choice** skips the question next time). With no external drive connected, scanning starts right away. Plugging in a drive while the app is open offers to scan it. Cancel any time with ⌘.

## 4. Summary

- **Needs attention** — findings sorted by severity then size; **Show** jumps to the related folder, Docker page or duplicate list.
- **Drives** — usage bar per drive.
- **What the startup disk is used for** — space by category.

| Level | When |
|---|---|
| 🔴 Critical | Startup disk below 10 GB free, or any drive below 5% — the Mac may freeze (no room for swap), macOS updates (20–30 GB) fail |
| 🟠 Warning | Startup disk below 20 GB or any drive below 10%; cleanable folder ≥ 10 GB; Docker `<none>` ≥ 5 GB |
| 🔵 Tip | Cleanable folders ≥ 1 GB, duplicate names, Docker `<none>` images |
| 🟢 Healthy | Everything else |

Thresholds are editable in Settings.

## 5. Drive details

- **Categories** — space by purpose plus well-known folders worth checking (DerivedData, simulators, caches, Trash, iOS backups, node_modules, Downloads, Homebrew cache).
- **Folders** — treemap + list sorted largest first. Double-click to open, use the path bar to go back, right-click for Show in Finder / Quick Look / Move to Trash.
- **Large Files** — the biggest files (100 MB+ by default).

The grey part of the usage bar is *System data & unreadable* (APFS snapshots, swap, protected folders).

## 6. Duplicate file names

After all selected drives are scanned, files with the same name (case-insensitive, Unicode-normalized) are grouped across drives, sorted by space freed when keeping only the newest copy. node_modules, .git, build folders, app bundles, ~/Library and system folders and files under 1 MB are skipped by default. **Same name does not mean same content** — use Quick Look first. The app never lets you remove every copy in a group.

## 7. Docker

Four strict steps: (1) is Docker installed? — if not, nothing runs; (2) is it running? — if not, **Open Docker** then **Check Again**; (3) list `<none>` (dangling) images, build cache and `Docker.raw` size; (4) remove the selected images after confirmation. Images are removed without `--force`, so anything used by a container is kept. `Docker.raw` may not shrink immediately.

## 8. Deleting & restoring

Everything goes to the Trash after a confirmation dialog. Restore with right-click › **Put Back** in the Trash. System folders, your home, Desktop, Documents, Downloads, Library, drive roots and the app itself are locked. The **Deletion Log** lists everything the app removed.

## 9. Shortcuts

⌘R Scan All · ⌘. Cancel · ⌘, Settings · ⌘? User Guide · double-click: open folder / Quick Look file.

## 10. FAQ

- *Totals differ from About This Mac?* macOS also counts APFS snapshots, swap and purgeable space, shown as “System data & unreadable”.
- *Network drives?* Skipped — scanning over the network is too slow.
- *Does the app use the network?* No.

## 11. Windows edition

Same 6 screens, severity levels and Vietnamese/English UI. Requires **Windows 10 version 1809 (build 17763) or later, or Windows 11**, on x64 or ARM64. No .NET or other runtime to install.

**Install:** GitHub › **Actions** › latest **CI** run › **Artifacts** › `CleanMyMac-windows-x64` (Intel/AMD) or `CleanMyMac-windows-ARM64` (or **Releases**). Unzip anywhere and run `CleanMyMac.exe`. Windows SmartScreen may warn because the build is not commercially signed: **More info** › **Run anyway**. To build it yourself: install .NET SDK 8 and run `dotnet publish windows/src/CleanMyMac.App -c Release -r win-x64 -p:Platform=x64`.

| | macOS | Windows |
|---|---|---|
| Protected folders | Full Disk Access | **Restart as administrator** button (optional; without it some system folders are skipped) |
| Startup disk | Macintosh HD | Windows drive (usually C:) |
| Deleting | Trash | Recycle Bin; **USB sticks and memory cards have no Recycle Bin**, so the app warns clearly and asks before deleting permanently |
| Opening files | Show in Finder / Quick Look | Show in Explorer / Open |
| Well-known folders | DerivedData, simulators… | Windows temp, Windows Update cache, `Windows.old`, Recycle Bin, browser caches, `node_modules`, NuGet/npm caches… |
| Sizes | Allocated size | "Size on disk"; hard links (WinSxS) counted once; junctions/symlinks not followed |
| Docker | Docker Desktop, OrbStack… | Docker Desktop (WSL 2); the `.vhdx` disk does not shrink automatically |
| GB thresholds | Startup disk only | Windows drive only |

External drives (USB, external SSD, memory cards) appear when connected and are still confirmed before scanning.
