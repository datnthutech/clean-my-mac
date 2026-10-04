# Phát hành (Release)

Tài liệu cho người duy trì dự án: cách tạo một bản phát hành có file cài đặt cho **macOS** và **Windows**, cách kiểm tra, và cách xử lý khi có sự cố.

## 1. Tổng quan

```
git push origin v1.0.0            (đẩy một tag bắt đầu bằng "v")
        │
        ▼
GitHub Actions → workflow "Release" (.github/workflows/release.yml)
        │
        ├─ job macOS  (macos-15)  : kiểm tra bản dịch → test → build universal → ký ad-hoc → DMG
        │                           → tạo GitHub Release (+ ghi chú) và đính DMG + .sha256
        └─ job Windows (x64, ARM64): (chờ job macOS) → test (x64) → dotnet publish self-contained
                                    → zip + .sha256 → đính vào cùng Release
```

Kết quả là một trang Release với các file:

| File | Dùng cho |
|---|---|
| `CleanMyMac-<phiên bản>-macOS.dmg` | macOS 13+, Apple silicon và Intel |
| `CleanMyMac-<phiên bản>-windows-x64.zip` | Windows 10 1809+ / 11, Intel/AMD |
| `CleanMyMac-<phiên bản>-windows-ARM64.zip` | Windows 10 1809+ / 11, ARM64 |
| `<từng file>.sha256` | Kiểm tra toàn vẹn |

> `<phiên bản>` là tên tag bỏ chữ `v`, ví dụ tag `v1.0.0-beta.2` cho `1.0.0-beta.2`.
> Release `v1.0.0-beta.1` được tạo bằng workflow đời đầu nên đặt tên cũ (`CleanMyMac-1.0.0-beta.1.dmg`, không có `.sha256`, chưa đánh dấu pre-release).

Hai job chạy **tuần tự** để job macOS tạo Release trước, tránh hai job cùng tạo một Release một lúc.

## 2. Phát hành một phiên bản

### Trước khi tạo tag
1. Gộp mọi thay đổi vào `main` và chờ **CI xanh** trên `main` (4 job: test Linux, macOS, Windows x64, Windows ARM64).
2. Cập nhật [CHANGELOG.md](../CHANGELOG.md): chuyển mục *Chưa phát hành* thành mục của phiên bản mới.
3. Chọn số phiên bản theo dạng `vMAJOR.MINOR.PATCH`. Muốn **bản thử nghiệm** thì thêm hậu tố sau dấu gạch: `v1.1.0-beta.1`, `v1.1.0-rc.1`.

### Tạo tag (chạy trên máy có quyền ghi repo)
```bash
git fetch origin
git tag v1.0.0 origin/main        # bản chính thức, gắn vào đúng commit mới nhất của main
git push origin v1.0.0
```

> ⚠️ **Tag phải trỏ vào commit có workflow mới nhất.** GitHub chạy file `release.yml` đúng ở commit được gắn tag. Nếu gắn tag vào commit cũ (như `v1.0.0-beta.1` đã gắn vào commit trước khi workflow được cải tiến) thì Release sẽ được build bằng workflow cũ. Dùng `origin/main` như lệnh trên là an toàn.

Tag có dấu `-` (ví dụ `v1.1.0-beta.1`) được đăng là **Pre-release** tự động; tag không có dấu `-` là bản chính thức.

### Theo dõi và kiểm tra
1. Mở **Actions › Release**: cả 3 job (macOS, Windows x64, Windows ARM64) phải xanh. Thường chỉ mất vài phút (lần chạy đầu tiên của `v1.0.0-beta.1`, khi các job chạy song song, mất khoảng 2 phút; bản tuần tự hiện tại thêm bước test Windows nên lâu hơn một chút).
2. Mở **Releases** › bản mới nhất › kéo xuống **Assets** (bấm *Show all assets* nếu bị thu gọn): phải có đủ 3 file cài đặt và 3 file `.sha256`.
3. (Khuyến nghị) Tải về và thử trên máy thật theo [hướng dẫn sử dụng](USER_GUIDE.md#1-tải-về-và-cài-đặt). Các mục chưa được kiểm thử tự động nằm ở [PLAN.md](PLAN.md#8-hạn-chế-đã-biết-và-hướng-phát-triển-tiếp-theo).
4. Sửa ghi chú Release nếu cần (nút **Edit** trên trang Release).

## 3. Số phiên bản

| Nơi dùng | Giá trị với tag `v1.0.0-beta.2` |
|---|---|
| Tên file | `1.0.0-beta.2` |
| macOS `CFBundleShortVersionString` | `1.0.0` (chỉ phần số; macOS không chấp nhận hậu tố) |
| macOS `CFBundleVersion` (build) | số thứ tự lần chạy workflow |
| Windows (`Version`) | `1.0.0-beta.2` |

Phiên bản mặc định khi build thường (không qua tag) là `1.0.0` trong `project.yml` và `Directory.Build.props`.

## 4. Bản dựng thử không cần tag

Mỗi lần push, workflow **CI** build cả hai bản và đăng file ở **Actions › CI › Artifacts** (`CleanMyMac-dmg`, `CleanMyMac-windows-x64`, `CleanMyMac-windows-ARM64`, và ảnh chụp màn hình). Artifacts được GitHub bọc thêm một lớp zip và tự hết hạn; dùng để thử nội bộ, không dùng để phân phối.

## 5. Xử lý sự cố

| Tình huống | Cách xử lý |
|---|---|
| Một job lỗi do mạng/runner | Vào lần chạy › **Re-run failed jobs**. |
| Lỗi thật trong code hoặc workflow | Sửa trên `main`, **xoá Release và tag lỗi**, rồi tạo lại tag mới (xem dưới). Không nên tái sử dụng cùng tên tag khi đã có người tải. |
| Release không có đủ file | Mở lần chạy Release, xem job nào lỗi; sửa rồi **Re-run**. Job Windows chỉ chạy khi job macOS thành công. |
| Muốn thu hồi một bản | Trang Release › **Delete**; sau đó xoá tag. |

Xoá tag (cần quyền ghi repo):
```bash
git push origin :refs/tags/v1.0.0-beta.2   # xoá tag trên GitHub
git tag -d v1.0.0-beta.2                   # xoá tag trên máy
```
(Xoá Release trên trang GitHub trước.)

## 6. Ký số và notarize (chưa bật)

Các bản hiện tại **chưa ký số thương mại**, nên lần đầu mở hệ điều hành sẽ cảnh báo (Gatekeeper trên macOS, SmartScreen trên Windows). Cách vượt qua đã có trong hướng dẫn sử dụng.

| Nền tảng | Hiện trạng | Để bỏ cảnh báo |
|---|---|---|
| macOS | Ký ad-hoc (`codesign --sign -`) | Cần tài khoản **Apple Developer** (Developer ID). `scripts/build.sh` đã hỗ trợ biến `SIGN_IDENTITY` và `NOTARY_PROFILE`; còn thiếu: nạp chứng chỉ và thông tin notarize từ *GitHub Secrets* vào workflow `release.yml` |
| Windows | Không ký | Cần chứng chỉ ký code (OV/EV) hoặc dịch vụ ký như Azure Trusted Signing, rồi thêm bước ký (`signtool`) vào workflow trước khi zip |

## 7. Trình cài đặt Windows (chưa có)

Bản Windows hiện là **zip portable** (giải nén và chạy). Hướng bổ sung nếu cần trình cài đặt: Inno Setup (một file `Setup.exe` có lối tắt Start Menu và mục gỡ cài đặt) hoặc MSIX (cần ký số). Xem [PLAN.md](PLAN.md#8-hạn-chế-đã-biết-và-hướng-phát-triển-tiếp-theo).

## 8. Quyền cần có

- Đẩy tag cần **quyền ghi** vào repo.
- Workflow khai báo `permissions: contents: write` để tạo Release và đính file bằng `GITHUB_TOKEN`; không cần secret nào khác ở cấu hình hiện tại.
- Tên "CleanMyMac" là thương hiệu của MacPaw; nên đổi tên trước khi phát hành rộng rãi (xem [README](../README.md#trạng-thái-và-hạn-chế)).
