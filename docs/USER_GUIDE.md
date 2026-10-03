# Hướng dẫn sử dụng Clean My Mac

> Phiên bản tiếng Anh: [USER_GUIDE.en.md](USER_GUIDE.en.md). Nội dung này cũng có sẵn trong app: thanh bên › **Hướng dẫn sử dụng** (⌘?).

Clean My Mac giúp bạn biết **dung lượng ổ đĩa đang được dùng vào việc gì**, chỉ ra những thứ chiếm chỗ không cần thiết và dọn dẹp **an toàn** — mọi thứ xoá đều vào Thùng rác trước.

Yêu cầu: macOS 13 Ventura trở lên, máy Apple silicon (M1/M2/M3/M4…) hoặc Intel.

---

## 1. Cài đặt

### Cách A — Tải file DMG đã build sẵn
1. Vào trang GitHub của dự án › **Actions** › lần chạy **CI** mới nhất › mục **Artifacts** › tải `CleanMyMac-dmg` (hoặc vào **Releases** nếu đã có bản phát hành).
2. Mở file `.dmg`, kéo **Clean My Mac** vào thư mục **Applications**.
3. Lần đầu mở, macOS có thể báo *“không thể xác minh nhà phát triển”* vì app được ký cục bộ:
   - Mở **Cài đặt hệ thống › Quyền riêng tư & Bảo mật**, kéo xuống và bấm **Vẫn mở** (Open Anyway), hoặc
   - Chạy trong Terminal: `xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"`

### Cách B — Tự build trên máy Mac của bạn
Cần Xcode 15 trở lên (tải từ App Store) và [Homebrew](https://brew.sh).

```bash
git clone https://github.com/datnthutech/clean-my-mac.git
cd clean-my-mac
make build        # tự cài XcodeGen, chạy test, build app universal và tạo DMG
make run          # build xong mở app luôn
```

Kết quả nằm trong thư mục `build/`: `Clean My Mac.app` và `CleanMyMac-<phiên bản>.dmg`.
Muốn sửa code trong Xcode: `make open`.

---

## 2. Lần mở đầu tiên

Màn hình chào giới thiệu các tính năng và cho bạn chọn ngôn ngữ (**Tiếng Việt** / **English** / theo macOS).

### Cấp quyền Full Disk Access (khuyến nghị)
macOS bảo vệ một số thư mục như Mail, Tin nhắn, Safari và dữ liệu của ứng dụng khác. Không có quyền này, app sẽ bỏ qua các thư mục đó nên kết quả chưa đầy đủ.

1. Bấm **Mở Cài đặt hệ thống** (hoặc tự mở **Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Toàn quyền truy cập ổ đĩa**).
2. Bật **Clean My Mac**. Nếu chưa có trong danh sách, bấm **+** và chọn app trong thư mục Applications.
3. Quay lại app, bấm **Kiểm tra lại**. Nếu vẫn báo *Chưa cấp*, thoát app (⌘Q) rồi mở lại.

> App chỉ đọc **tên và dung lượng** file. Không có dữ liệu nào được gửi ra ngoài.

---

## 3. Giao diện

```
┌────────────────┬──────────────────────────────────────────────┐
│ TỔNG QUAN      │                                              │
│  Tóm tắt       │        Nội dung của mục đang chọn            │
│ Ổ ĐĨA          │                                              │
│  Macintosh HD ●│                                              │
│  Samsung T7   ●│                                              │
│ CÔNG CỤ        │                                              │
│  File trùng tên│                                              │
│  Docker        │                                              │
│  Nhật ký xoá   │                                              │
│ ỨNG DỤNG       │                                              │
│  Hướng dẫn     │                                              │
│  Cài đặt       │                         [Quét tất cả] (⌘R)   │
└────────────────┴──────────────────────────────────────────────┘
```

- Mỗi ổ đĩa có **chấm màu** cho biết tình trạng dung lượng trống: 🔴 Nghiêm trọng · 🟠 Cảnh báo · 🟢 Ổn.
- Ổ rời (USB, SSD gắn ngoài, thẻ SD) tự xuất hiện khi cắm và biến mất khi rút.

---

## 4. Quét ổ đĩa

Bấm **Quét tất cả** (⌘R) ở góc trên bên phải.

1. App luôn quét **ổ khởi động** và các ổ trong khác.
2. Nếu đang cắm **ổ rời**, app hiện hộp thoại *“Phát hiện N ổ đĩa rời — bạn có muốn quét luôn không?”*:
   - Tick chọn ổ muốn quét rồi bấm **Quét các ổ đã chọn**, hoặc bấm **Chỉ quét ổ trong**.
   - Chọn **Ghi nhớ lựa chọn** để lần sau không hỏi lại (đổi trong **Cài đặt › Ổ rời khi bấm “Quét tất cả”**).
   - Không có ổ rời nào → app quét luôn, không hỏi.
3. Thẻ tiến trình ở cuối cửa sổ hiển thị ổ đang quét, số file, dung lượng, thời gian và thư mục hiện tại. Bấm **Huỷ quét** (⌘.) bất cứ lúc nào.
4. Cắm ổ mới khi app đang mở → app hỏi *“Đã kết nối ổ X — Quét ngay?”*.

Muốn quét riêng một ổ: chọn ổ đó ở thanh bên › **Quét ổ này** / **Quét lại**.

---

## 5. Màn hình Tóm tắt

Gồm 3 phần:

1. **Cần chú ý** — danh sách ngắn gọn, xếp theo mức độ nghiêm trọng rồi theo dung lượng. Bấm **Xem** để đi thẳng tới thư mục / Docker / danh sách trùng tên liên quan.
2. **Ổ đĩa** — thẻ từng ổ với thanh dung lượng, dung lượng trống, định dạng và loại ổ.
3. **Ổ khởi động dùng cho việc gì** — thanh màu theo phân loại (Ứng dụng, Lập trình, Ảnh & Video, Tài liệu, Cache…).

### Ý nghĩa các mức độ

| Mức | Khi nào | Ảnh hưởng |
|---|---|---|
| 🔴 **Nghiêm trọng** | Ổ khởi động còn dưới **10 GB**, hoặc bất kỳ ổ nào còn dưới **5%** | Máy dễ lag, treo do thiếu chỗ cho bộ nhớ swap; không cài được bản cập nhật macOS (thường cần 20–30 GB) |
| 🟠 **Cảnh báo** | Ổ khởi động còn dưới **20 GB**, hoặc dưới **10%**; thư mục rác ≥ 10 GB; Docker `<none>` ≥ 5 GB | SSD ghi chậm hơn, snapshot Time Machine cục bộ bị xoá, app nặng chạy chậm |
| 🔵 **Gợi ý** | Thư mục có thể dọn ≥ 1 GB (DerivedData, cache, Thùng rác…), có file trùng tên, có image Docker `<none>` | Có thể giải phóng thêm dung lượng |
| 🟢 **Ổn** | Còn lại | — |

Các ngưỡng này là khuyến nghị kinh nghiệm, chỉnh được trong **Cài đặt › Cảnh báo dung lượng trống**. Ngưỡng GB chỉ áp dụng cho ổ khởi động (vì macOS cần chỗ ở đó); ngưỡng % áp dụng cho mọi ổ.

---

## 6. Chi tiết một ổ đĩa

Chọn ổ ở thanh bên. Đầu trang là thanh dung lượng chia màu theo phân loại; phần xám là **Dữ liệu hệ thống & không đọc được** (snapshot APFS, swap, thư mục được macOS bảo vệ).

### Tab “Phân loại”
- Dung lượng theo mục đích sử dụng, kèm phần trăm.
- **Thư mục lớn nên kiểm tra**: Xcode DerivedData, iOS Simulator, cache ứng dụng, Thùng rác, bản sao lưu iPhone, `node_modules`, Downloads, cache Homebrew… Bấm **Xem** để mở thư mục đó trong tab Thư mục.

### Tab “Thư mục”
- Bên trái là **treemap**: mỗi ô là một thư mục/file, diện tích tỉ lệ với dung lượng.
- Bên phải là **danh sách xếp từ lớn đến nhỏ** (đổi sang Tên / Ngày sửa ở ô **Sắp xếp**).
- **Nháy đúp** để mở thư mục; bấm đường dẫn phía trên để quay lại.
- **Chuột phải** → Mở / Mở trong Finder / Xem nhanh / Chuyển vào Thùng rác. Chọn nhiều mục bằng ⌘ hoặc ⇧.

### Tab “File lớn”
- Những file lớn nhất trên ổ (mặc định từ 100 MB, đổi trong Cài đặt), kèm ngày sửa.
- Nháy đúp để Xem nhanh; chọn rồi bấm **Chuyển vào Thùng rác**.

---

## 7. File trùng tên

Sau khi quét xong **tất cả** các ổ đã chọn, app gom các file **cùng tên** (không phân biệt hoa/thường và cách mã hoá dấu tiếng Việt) trên mọi ổ.

- Cột trái: các nhóm, xếp theo dung lượng giải phóng được nếu chỉ giữ lại bản **mới nhất**.
- Cột phải: các bản của nhóm đang chọn — đường dẫn, ổ đĩa, ngày sửa, dung lượng. Bản mới nhất được gắn nhãn **Mới nhất** và mặc định không được tick.
- Nút 👁 để Xem nhanh, 🔍 để mở trong Finder.
- **Chọn tất cả trừ bản mới nhất** → **Chuyển N file vào Thùng rác**. App không cho xoá hết mọi bản trong một nhóm.

Tuỳ chọn phía trên:
- *Bỏ qua node_modules, .git, thư mục build* (mặc định bật)
- *Bỏ qua Library & hệ thống* (mặc định bật)
- *Tối thiểu*: bỏ qua file nhỏ hơn 1 MB (mặc định)

> ⚠️ **Trùng tên không có nghĩa là trùng nội dung.** Luôn Xem nhanh từng bản trước khi xoá.

---

## 8. Docker

App làm theo **4 bước**, mỗi bước chỉ chạy khi bước trước thành công:

1. **Đã cài Docker chưa?** — tìm lệnh `docker` (Docker Desktop, OrbStack, Colima, Rancher Desktop, Homebrew). Nếu chưa cài: hiện *“Máy chưa cài Docker”* và **không chạy lệnh nào**.
2. **Docker có đang chạy không?** — nếu chưa: hiện *“Docker đã cài nhưng chưa chạy”* + nút **Mở Docker**. Mở xong bấm **Kiểm tra lại**.
3. **Quét** — liệt kê image `<none>` (dangling: phần thừa sau mỗi lần build lại, không container nào dùng), tổng dung lượng image, build cache và file ổ ảo `Docker.raw`.
4. **Dọn** — tick image muốn xoá → **Xoá N image** → xác nhận.

An toàn: image được xoá bằng `docker image rm` **không** kèm `--force`, nên image đang được container sử dụng sẽ không bị xoá.

Lưu ý: với Docker Desktop, file `Docker.raw` có thể **không nhỏ lại ngay** sau khi xoá image — đây là hành vi của Docker, không phải lỗi của app.

---

## 9. Xoá & khôi phục

- Mọi thao tác xoá đều **chuyển vào Thùng rác** (ổ rời dùng Thùng rác riêng của ổ đó) và luôn có **hộp thoại xác nhận** hiển thị số mục và tổng dung lượng.
- **Khôi phục**: mở Thùng rác › chuột phải vào file › **Đưa trở lại**.
- Dung lượng chỉ thực sự được giải phóng sau khi bạn **dọn sạch Thùng rác**.
- Các vị trí **bị khoá, không thể xoá**: `/System`, `/Library`, `/usr`, `/bin`, `/private`…, thư mục người dùng, Desktop, Documents, Downloads, Library, thư mục gốc của mỗi ổ và chính app.
- **Nhật ký xoá** (thanh bên) lưu mọi thứ app đã dọn: thời gian, đường dẫn, dung lượng.

---

## 10. Cài đặt

| Mục | Ý nghĩa |
|---|---|
| Ngôn ngữ | Tiếng Việt / English / theo macOS — đổi ngay, không cần mở lại app |
| Ổ rời khi bấm “Quét tất cả” | Luôn hỏi / Luôn quét / Không quét |
| Ngưỡng file lớn | Kích thước tối thiểu để vào tab File lớn |
| Cảnh báo dung lượng trống | 4 ngưỡng Nghiêm trọng / Cảnh báo (GB cho ổ khởi động, % cho mọi ổ) |
| Quyền truy cập | Trạng thái Full Disk Access + nút mở Cài đặt hệ thống |
| Thông tin | Phiên bản, hiện lại màn hình chào, khôi phục mặc định |

---

## 11. Phím tắt

| Phím | Chức năng |
|---|---|
| ⌘R | Quét tất cả |
| ⌘. | Huỷ quét |
| ⌘, | Cài đặt |
| ⌘? | Hướng dẫn sử dụng |
| Nháy đúp | Mở thư mục / Xem nhanh file |
| Space (trong Xem nhanh) | Đóng xem nhanh |

---

## 12. Câu hỏi thường gặp

**Vì sao tổng dung lượng khác với “Giới thiệu về máy Mac này › Dung lượng”?**
macOS tính cả snapshot APFS, swap và dung lượng *purgeable* — những thứ không liệt kê được thành file. App hiển thị phần này là *Dữ liệu hệ thống & không đọc được*. Dung lượng trống mà app dùng là con số giống Finder.

**Quét có làm chậm máy không?**
App đọc thư mục song song và chỉ đọc thông tin file (không đọc nội dung), nên thường chỉ mất từ vài chục giây đến vài phút tuỳ số lượng file. Có thể huỷ bất cứ lúc nào.

**Vì sao một số thư mục có biểu tượng ổ khoá?**
Thư mục đó được macOS bảo vệ. Cấp Full Disk Access để đọc được phần lớn, phần còn lại là của hệ thống và không nên đụng vào.

**Ổ mạng (NAS, SMB) có được quét không?**
Không. Ổ mạng bị bỏ qua vì quét qua mạng rất chậm.

**App có gửi dữ liệu đi đâu không?**
Không. App không kết nối mạng.
