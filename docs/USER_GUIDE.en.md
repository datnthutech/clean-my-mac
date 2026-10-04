# Clean My Mac — User Guide

> Tiếng Việt: [USER_GUIDE.md](USER_GUIDE.md) · The same guide is built into the app: **User Guide** in the left menu (macOS: ⌘?).

Clean My Mac shows **what your disk space is used for**, points out what wastes space and lets you clean up **safely**: everything you remove goes to the Trash / Recycle Bin first, and nothing is deleted permanently without asking.

There are **two editions** with the same screens and features. Differences are marked 🍎 (macOS) and 🪟 (Windows) and summarised in [section 13](#13-macos-vs-windows-at-a-glance).

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Operating system | macOS 13 Ventura or later | Windows 10 version 1809 (build 17763) or later, Windows 11 |
| Hardware | Apple silicon and Intel | x64 (Intel/AMD) and ARM64 |
| Installer file | `.dmg` (drag to Applications) | `.zip`, a **portable** build: unzip and run `CleanMyMac.exe` (there is no `Setup.exe`) |
| Permission for complete results | Full Disk Access | Run as administrator (optional) |

![Summary screen on macOS](screenshot-summary.jpg)

---

## Contents

1. [Download and install](#1-download-and-install)
2. [First launch and permissions](#2-first-launch-and-permissions)
3. [The interface](#3-the-interface)
4. [Scanning drives](#4-scanning-drives)
5. [Summary and severity levels](#5-summary-and-severity-levels)
6. [Drive details](#6-drive-details)
7. [Duplicate file names](#7-duplicate-file-names)
8. [Docker](#8-docker)
9. [Deleting and restoring](#9-deleting-and-restoring)
10. [Deletion log](#10-deletion-log)
11. [Settings](#11-settings)
12. [Shortcuts and controls](#12-shortcuts-and-controls)
13. [macOS vs Windows at a glance](#13-macos-vs-windows-at-a-glance)
14. [Troubleshooting](#14-troubleshooting)
15. [App data and uninstalling](#15-app-data-and-uninstalling)
16. [FAQ](#16-faq)

---

## 1. Download and install

### 1.1 Where to get the files

**Main way: the Releases page.** Go to <https://github.com/datnthutech/clean-my-mac/releases>, open the latest release (test builds are labelled **Pre-release**) and scroll to **Assets**.

> ⚠️ **Assets** is often collapsed. If you only see *Source code (zip)* and *Source code (tar.gz)*, click **Show all … assets**. The two *Source code* entries are the **source code**: they cannot be run and contain **no** `.dmg` or `.exe`.

| Operating system | File (new releases) | beta.1 used the old naming |
|---|---|---|
| 🍎 macOS | `CleanMyMac-<version>-macOS.dmg` | `CleanMyMac-1.0.0-beta.1.dmg` |
| 🪟 Windows x64 | `CleanMyMac-<version>-windows-x64.zip` | `CleanMyMac-1.0.0-beta.1-windows-x64.zip` |
| 🪟 Windows ARM64 | `CleanMyMac-<version>-windows-ARM64.zip` | `CleanMyMac-1.0.0-beta.1-windows-ARM64.zip` |
| Integrity check | a `<file name>.sha256` next to each file | (none) |

**Secondary way: CI test builds.** Go to [Actions](https://github.com/datnthutech/clean-my-mac/actions) › latest **CI** run › **Artifacts** (GitHub sign-in required): `CleanMyMac-dmg`, `CleanMyMac-windows-x64`, `CleanMyMac-windows-ARM64`. GitHub **wraps them in an extra zip**, so unzip twice to reach the `.dmg` or the Windows `.zip`. Artifacts expire after a while.

**Verify the download** (optional, when a `.sha256` file exists):
- 🍎 `shasum -a 256 file.dmg`
- 🪟 PowerShell: `Get-FileHash file.zip -Algorithm SHA256`

Compare the result with the contents of the `.sha256` file.

### 1.2 🍎 Install on macOS

1. Open the `.dmg` and drag **Clean My Mac** into **Applications**.
2. Open it from Applications. The app is ad-hoc signed (no Developer ID yet), so macOS blocks the first launch (*"Apple could not verify…"*):
   - Open **System Settings › Privacy & Security**, scroll to *Security* and click **Open Anyway**, then enter your password; or
   - run in Terminal: `xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"`
   - (macOS 13–14) you can also right-click the app › **Open** › **Open**
3. One `.dmg` works on both Apple silicon and Intel Macs (universal).

### 1.3 🪟 Install on Windows

The Windows edition is currently a **portable build**: there is no `Setup.exe`, nothing is written to the registry or to Program Files. Install = unzip; uninstall = delete the folder.

1. **Pick the right build:** open **Settings › System › About** and read *System type*. *x64-based* → download **x64**; *ARM-based* → download **ARM64**. To check your Windows version press `Win + R`, type `winver` (you need **1809**, build 17763 or later).
2. (Recommended) Right-click the `.zip` › **Properties** › tick **Unblock** › OK. This stops Windows prompting for every file in the folder.
3. Right-click the `.zip` › **Extract All…** to a permanent folder, for example `C:\Tools\CleanMyMac`.
   > ❗ You must **extract everything**. Running `CleanMyMac.exe` from inside the zip preview, or copying the `.exe` somewhere on its own, fails because the app needs the files next to it (about 65 MB, runtime included, no .NET install needed).
4. Open the extracted folder and run **`CleanMyMac.exe`**.
5. If *"Windows protected your PC"* (SmartScreen) appears, click **More info** › **Run anyway**. Reason: the app is not signed with a commercial code-signing certificate.
6. Make a shortcut: right-click `CleanMyMac.exe` › **Show more options** › **Send to › Desktop (create shortcut)**, or **Pin to Start**.

### 1.4 Build from source

- 🍎 Needs Xcode 15+ and Homebrew: `make build` (installs XcodeGen, runs tests, builds universal, creates the DMG in `build/`); `make run` to build and launch; `make open` for Xcode.
- 🪟 Needs the .NET 8 SDK on Windows (Visual Studio is not required; `global.json` at the repo root pins SDK 8):
  ```powershell
  dotnet publish windows/src/CleanMyMac.App/CleanMyMac.App.csproj -c Release -r win-x64 -p:Platform=x64 -o windows/artifacts/win-x64
  ```
  Use `-r win-arm64 -p:Platform=ARM64` for ARM64. Run `windows/artifacts/win-x64/CleanMyMac.exe`.

For developers: [ARCHITECTURE.md](ARCHITECTURE.md); how releases are made: [RELEASING.md](RELEASING.md).

---

## 2. First launch and permissions

On first launch the app shows a **welcome screen**: features, **language** (Vietnamese / English / same as the OS) and permission help. You can change the language any time; it applies immediately, no restart.

### 🍎 Full Disk Access (recommended)
macOS protects some folders (Mail, Messages, Safari, other apps' data). Without this permission the app **skips** them, so results are incomplete.

1. Click **Open System Settings** (or go to **System Settings › Privacy & Security › Full Disk Access**).
2. Turn on **Clean My Mac**. If it is not listed, click **+** and pick the app in Applications.
3. Return to the app and click **Check Again**. If it still says *Not granted*, quit (⌘Q) and reopen.

### 🪟 Administrator rights (optional)
As a standard user Windows does not let apps list some folders (`Windows`, other users' profiles, `System Volume Information`…). The app **skips** them, so totals look smaller than reality and the Summary shows a *"N folders were skipped"* tip.

- Click **Restart as administrator** (on the welcome screen, in **Settings › Permissions**, or **User Guide › Administrator rights**) and accept the UAC prompt. The app reopens with full access; your settings are kept.
- Everything else works without administrator rights; only the results are less complete.

> The app reads only **file names and sizes**, never contents, and **does not use the network**.

---

## 3. The interface

Both editions have a **menu on the left** and **content** on the right:

```
┌────────────────┬──────────────────────────────────────────────┐
│ OVERVIEW       │                                              │
│  Summary       │        Content of the selected item          │
│ DRIVES         │                                              │
│  Startup drive●│                                              │
│  External     ●│                                              │
│ TOOLS          │                                              │
│  Duplicate     │                                              │
│  Docker        │                                              │
│  Deletion Log  │                                              │
│ APP            │                                              │
│  User Guide    │                                              │
│  Settings      │                                              │
└────────────────┴──────────────────────────────────────────────┘
```

- **The menu is visible on every page**, even when a page has no data yet or hits an error. An error on one page appears only in the content area.
- Each drive has a **colour dot** for its free-space status: 🔴 Critical · 🟠 Warning · 🟢 Healthy.
- External drives (USB, external SSD, memory cards) appear when connected and disappear when removed. 🍎 updates instantly; 🪟 checks about every 3 seconds.
- If the window is too small the page **scrolls** instead of overflowing.
- **Scan All** button: 🍎 top right (and the File menu, ⌘R); 🪟 at the top of the left menu. While scanning it turns into **Cancel Scan**.
- 🍎 Supports Light and Dark mode. 🪟 Uses the Windows 11 Fluent look (Mica backdrop where available) and also runs on Windows 10.

![Windows edition: pages captured automatically on a Windows VM](screenshot-windows.jpg)

---

## 4. Scanning drives

Click **Scan All**.

1. The app always scans the **startup drive** (🍎 Macintosh HD, 🪟 the Windows drive, usually C:) and other **internal drives**.
2. If **external drives** are connected, a dialog asks *"N external drives detected — scan them too?"*:
   - Tick the drives to scan and click **Scan Selected**, or click **Internal Drives Only**.
   - **Remember my choice** skips the question next time (change it in **Settings › External drives on "Scan All"**: Ask every time / Always scan / Never scan).
   - **No external drive connected** → scanning starts right away, no question.
3. A progress card at the bottom shows the drive, file count, size, elapsed time and current folder. **Cancel Scan** any time (🍎 ⌘.).
4. Plug in a drive **while the app is open** → it asks *"External drive connected — scan now?"*.
5. To scan one drive: select it in the menu › **Scan This Drive** / **Rescan**.

Only scanned drives have data. Duplicate names and Docker are processed **after** the selected drives finish.

Skipped automatically: network drives (NAS, SMB) and drives that are not ready; 🪟 also optical drives. Shortcuts (symlinks, junctions) are not followed, so nothing is counted twice.

**Sizes are the space actually used on disk** (deleting a file frees exactly that much). Hard links are counted once (🪟 very common in `Windows\WinSxS`). For reference: on a CI virtual machine about 1.9 million files took roughly 1 minute; HDDs and USB 2.0 are much slower.

---

## 5. Summary and severity levels

Three parts:

1. **Needs attention**: a short list sorted by severity, then size. **Show** jumps to the related folder, Docker page or duplicate list.
2. **Drives**: a card per drive with usage bar, free space, format and kind.
3. **What the startup drive is used for**: a colour bar by category (Applications, Developer, Photos & Videos, Documents, Caches…).

Before any scan the Summary still warns about low free space (no scan needed).

| Level | When | Effect |
|---|---|---|
| 🔴 **Critical** | Startup drive (🪟 Windows drive) below **10 GB** free, or **any drive** below **5%** | 🍎 The Mac may slow down or freeze (no room for swap); macOS updates (~20–30 GB) fail. 🪟 Windows becomes slow or unstable (no room for the page file and temp files); big updates need ~20 GB |
| 🟠 **Warning** | Startup drive below **20 GB**, or any drive below **10%**; a cleanable folder ≥ **10 GB**; Docker `<none>` ≥ **5 GB**; reclaimable Docker build cache ≥ **10 GB**; 🍎 Full Disk Access missing | Slower SSD writes, snapshots/restore points purged, heavy apps lag, updates may fail |
| 🔵 **Tip** | Cleanable folder ≥ **1 GB**; Downloads ≥ **20 GB**; duplicate names found; Docker `<none>` images; reclaimable Docker build cache ≥ **1 GB**; 🪟 folders skipped for lack of administrator rights | More space can be freed |
| 🟢 **Healthy** | Everything else | — |

GB limits apply to the **startup drive** only (the OS needs room there); percentages apply to **every drive**. They are rules of thumb and can be changed in **Settings › Free space warnings**.

---

## 6. Drive details

Select a drive in the menu. At the top is a usage bar split by category; the **grey** part is *System data & unreadable* (🍎 APFS snapshots, swap; 🪟 restore points, NTFS metadata; protected folders).

### "Categories" tab
- Space by **purpose** (Applications, Documents, Photos & Videos, Music, Archives & Installers, Developer, Caches, iOS Backups, Mail, Trash, Docker, System, Other) with percentages.
- **Large folders worth checking**: well-known locations that are usually safe to clean. **Show** opens the folder in the Folders tab.
  - 🍎 Xcode DerivedData and Archives, iOS Simulators, app caches, Trash, iPhone backups, `node_modules`, Downloads, Homebrew cache.
  - 🪟 Windows and user temp files, Windows Update cache, `Windows.old`, Recycle Bin, browser caches, `node_modules`, Downloads, iPhone backups, NuGet/npm caches, Visual Studio cache.

### "Folders" tab
- Left: a **treemap**: each tile is a folder/file with area proportional to its size (the 40 largest tiles, the rest merged into "Other").
- Right: a **list sorted largest first**; switch to *Name* or *Date modified* with **Sort by**.
- **Double-click** a folder (in the list or treemap) to open it; use the path at the top to go back.
- Select one or more items (⌘/⇧ or Ctrl/Shift), then:

| Action | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Open a folder | Double-click, or right-click › Open | Double-click |
| See a file where it lives | Show in Finder | **Show in Explorer** (bottom bar) |
| Look at the content | Quick Look | **Open** (default app) |
| Delete | Move to Trash | Move to Recycle Bin |
| How | Right-click or the bottom bar | The bottom bar (no right-click menu yet) |

### "Large Files" tab
The biggest files on the drive (default **100 MB** and up, at most 200; change the threshold in Settings) with their modified date. Select and use the buttons as in the Folders tab.

---

## 7. Duplicate file names

After **all** selected drives are scanned, files with the **same name** across drives are grouped (case-insensitive, and Vietnamese accents are normalised so a typed and a stored "Báo cáo.pdf" match).

- **Left column**: groups sorted by space freed when keeping only the **newest** copy.
- **Right column**: the copies of the selected group (folder, drive, date, size). The newest copy is labelled **Newest** and is **not** ticked; the others are ticked for removal by default. Hover a path to see it in full.
- Each copy has a button to look at the content (🍎 Quick Look, 🪟 Open) and to reveal its location (🍎 Finder, 🪟 Explorer).
- **Select all except newest**, then **Move N files to Trash**. The app **never lets you remove every copy** in a group.

Options at the top (remembered; changing one searches again right away):
- *Skip `node_modules`, `.git`, build folders* (on by default).
- 🍎 *Skip Library & system* / 🪟 *Skip Windows, Program Files & AppData* (on by default). On Mac, app bundles (`.app`) are also skipped.
- *Minimum*: ignore files under 1 MB (default); from *any size* up to 1 GB.

> ⚠️ **Same name does not mean same content.** Always look at each copy before deleting.

---

## 8. Docker

The page works in **4 steps**; each runs only if the previous one succeeded:

1. **Is Docker installed?** The app looks for the `docker` command in the usual places. Not installed → *"Docker is not installed on this Mac/PC"* and **no command is run**.
2. **Is Docker running?** Not running → *"Docker is installed but not running"* with an **Open Docker** button. After it starts, click **Check Again**.
3. **Scan**: lists `<none>` (dangling) images (leftovers from rebuilding images that no container uses), total image size, build cache and Docker's virtual disk file.
4. **Clean**: tick the images to remove › **Remove N images** › confirm.

Supported: 🍎 Docker Desktop, OrbStack, Rancher Desktop (and Colima when the `docker` command sits in the usual Homebrew path). 🪟 Docker Desktop (WSL 2), Rancher Desktop, Podman, or any `docker.exe` on PATH.

**Safety:** images are removed with `docker image rm` **without `--force`**, so an image used by a container is never removed.

**Note:** 🍎 `Docker.raw`, 🪟 the `.vhdx` virtual disk (WSL 2) **does not shrink immediately** after removing images. That is Docker's behaviour, not a bug in the app.

---

## 9. Deleting and restoring

- Every delete goes through a **confirmation dialog** showing the number of items and total size, then is **moved to the Trash / Recycle Bin**.
- **Restore:** open the Trash / Recycle Bin › right-click the file › 🍎 **Put Back** / 🪟 **Restore**.
- Space is freed for good only after you **empty the Trash / Recycle Bin**.
- **Locked locations that cannot be removed:**
  - 🍎 `/System`, `/Library`, `/usr`, `/bin`, `/private`…, your home folder, Desktop, Documents, Downloads, Library, the root of each drive and the app itself.
  - 🪟 `Windows`, `ProgramData`, `System Volume Information`, `Recovery`, `Program Files`, your profile and its `Desktop`, `Documents`, `Downloads`, `AppData`…, the root of each drive, `pagefile.sys`/`hiberfil.sys` and the app itself.
- Locked items are listed in the confirmation dialog and **skipped automatically**.

### ⚠️ Windows only: USB sticks and memory cards have no Recycle Bin
Windows "removable" drives (USB sticks, memory cards) **have no Recycle Bin**. If your selection includes items on such a drive, the dialog shows a **red warning** and the button becomes **Delete permanently**: afterwards the files **cannot be restored**. Check carefully before agreeing. (🍎 macOS uses each external drive's own Trash, so those files can still be restored.)

> This behaviour, like the external-drive prompt when plugging in a USB drive, has **not been tested on real USB/memory-card hardware** in the beta (CI only has virtual machines). Please report problems in Issues.

---

## 10. Deletion log

**Deletion Log** lists everything the app removed (files, folders, Docker images): time, path, size (the latest 2000 entries). **Open Trash / Open Recycle Bin** helps you restore quickly; **Clear Log** does not affect files in the Trash.

---

## 11. Settings

| Item | Meaning |
|---|---|
| Language | Vietnamese / English / same as the OS; applies immediately |
| External drives on "Scan All" | Ask every time / Always scan / Never scan |
| Large file threshold | Minimum size for the Large Files tab (default 100 MB) |
| Free space warnings | 4 limits: Critical and Warning, each by GB (startup drive only) and by % (every drive) |
| Permissions | 🍎 Full Disk Access status + button to open System Settings. 🪟 what you are running as + **Restart as administrator** |
| About | Version, **Reset to Defaults**; 🍎 also *Show Welcome Screen* |

Open Settings: 🍎 the left menu or ⌘, · 🪟 **Settings** at the bottom of the left menu.

---

## 12. Shortcuts and controls

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Scan All | ⌘R | Button at the top of the menu |
| Cancel scan | ⌘. | Button at the top of the menu |
| Settings | ⌘, | **Settings** in the menu |
| User Guide | ⌘? | **User Guide** in the menu |
| Select several items | ⌘-click, ⇧-click | Ctrl-click, Shift-click |
| Open a folder | Double-click | Double-click |
| Right-click menu | Yes (Open / Finder / Quick Look / Trash) | Not yet |
| In dialogs | Enter = main button, Esc = cancel | Enter = main button (the safe one when deleting), Esc = cancel |

The Windows edition has no app-specific shortcuts yet; only standard Windows keys (Tab, Enter, Esc…) work.

---

## 13. macOS vs Windows at a glance

| Topic | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Startup drive | Macintosh HD (firmlinked data is not counted twice) | The Windows drive (usually C:) |
| Reading protected folders | Full Disk Access | Restart as administrator (optional) |
| How sizes are read | `getattrlistbulk` (bulk read) | Windows bulk directory API with File IDs, so hard links count once |
| Deleting | Trash (external drives use their own Trash) | Recycle Bin; **USB/memory cards have none → warning and permanent delete if you agree** |
| Viewing files | Finder, Quick Look | Explorer, Open (no Quick Look) |
| Well-known folders | Xcode, simulators, caches, Homebrew… | Windows temp, Windows Update, `Windows.old`, browser caches, NuGet/npm… |
| Drive plug/unplug | Instant | Checked every ~3 s |
| Docker | Docker Desktop, OrbStack… | Docker Desktop (WSL 2)…; `.vhdx` does not shrink |
| Shortcuts, right-click menu | Yes | Not yet |
| Install | `.dmg` drag to Applications | portable `.zip`, unzip and run `CleanMyMac.exe` |
| First-launch warning | Gatekeeper → **Open Anyway** | SmartScreen → **More info › Run anyway** |

Everything else (scanning, categories, duplicate names, the 4-step Docker flow, severity levels, deletion log, bilingual UI) is the same.

---

## 14. Troubleshooting

**I downloaded it but I see no `.dmg` or `.exe`.**
- You may have downloaded *Source code (zip)*. Open **Assets** (click *Show all assets*) and take the right file from [section 1.1](#11-where-to-get-the-files).
- 🪟 The Windows edition **has no `Setup.exe`**. The `.exe` is **inside** the `.zip` after you extract everything ([section 1.3](#13--install-on-windows)).
- From Actions › Artifacts you must unzip **twice**.

**🍎 macOS says it "can't be opened" / "Apple could not verify".** System Settings › Privacy & Security › **Open Anyway**, or the `xattr` command in [section 1.2](#12--install-on-macos).

**🪟 SmartScreen blocks it, or the app reports missing files.** Click *More info › Run anyway*. If the app will not start: make sure you **extracted everything** and run `CleanMyMac.exe` from that folder; check Windows is 1809 or later and that you took the right x64/ARM64 build.

**Results are smaller than the drive's used space.** The difference is the grey *System data & unreadable* area. Grant 🍎 Full Disk Access / 🪟 administrator rights to read more; the rest is system data that cannot be listed as files.

**An external drive is missing from the menu.** Make sure the OS has mounted it and it has a drive letter (🪟) or shows in Finder (🍎). Network drives and drives that are not ready are skipped (🪟 and optical drives too). On 🪟 wait a few seconds for the app to refresh.

**No prompt about external drives.** Check **Settings › External drives on "Scan All"**: if it is *Always scan* or *Never scan* (because you once ticked "Remember my choice") the app does not ask. Switch back to *Ask every time*.

**Docker says not installed although it is.** The app only looks for the `docker` command in the usual places and on PATH. Open Docker, click **Check Again**. If it lives somewhere unusual, add its folder to PATH.

**Scanning takes very long.** HDDs, USB 2.0 and drives with millions of files are slow. Use **Cancel Scan** or untick that drive in the external-drive dialog.

**I deleted something by mistake.** Open the Trash / Recycle Bin and restore it (see [section 9](#9-deleting-and-restoring)). Files permanently deleted from a Windows USB stick or memory card cannot be restored by the app.

**Reset all settings.** **Settings › Reset to Defaults**, or delete the settings file listed in [section 15](#15-app-data-and-uninstalling).

**Report a problem.** Open an issue at <https://github.com/datnthutech/clean-my-mac/issues> with your OS, the app version (**Settings › About**) and the steps to reproduce.

---

## 15. App data and uninstalling

The app stores two small local files:

| | 🍎 macOS | 🪟 Windows |
|---|---|---|
| Settings | The app's user defaults (`com.datnthutech.cleanmymac`) | `%LOCALAPPDATA%\CleanMyMac\settings.json` |
| Deletion log | `~/Library/Application Support/CleanMyMac/deletion-log.json` | `%LOCALAPPDATA%\CleanMyMac\deletion-log.json` |

**Uninstall**
- 🍎 Drag **Clean My Mac** from Applications to the Trash. To remove its data too: delete `~/Library/Application Support/CleanMyMac` and run `defaults delete com.datnthutech.cleanmymac`.
- 🪟 Delete the folder you extracted. To remove its data too: delete `%LOCALAPPDATA%\CleanMyMac`. The app writes nothing to the registry.

---

## 16. FAQ

**Why does the total differ from "About This Mac" / the drive size in Explorer?** The OS also counts things that cannot be listed as files (🍎 APFS snapshots, swap, purgeable space; 🪟 restore points, NTFS metadata). The app shows them as *System data & unreadable*. The free space it uses is the same figure as Finder / Explorer.

**Does scanning slow my computer down?** The app reads folders in parallel and only reads file information (not contents); it usually takes from tens of seconds to a few minutes. You can cancel any time.

**Are network drives (NAS, SMB) scanned?** No, scanning over the network is too slow.

**Does the app send data anywhere?** No. It does not use the network.

**Does it update itself?** Not yet. Download the new version from Releases and replace the old one.

**Why is the Mac file a `.dmg` but the Windows one a `.zip`?** `.dmg` is the standard macOS installer format. The Windows edition is currently portable (no install needed). A `Setup.exe` installer is on the roadmap, see [PLAN.md](PLAN.md).
