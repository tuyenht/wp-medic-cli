<div align="center">
  <h1>🛡️ WP-Medic CLI</h1>
  <p><strong>Bộ công cụ khẩn cấp WordPress — Phát hiện mã độc, phục hồi Core, xoay vòng bảo mật & kiểm tra sức khỏe website tự động.</strong></p>
  <code>v1.4.0</code>
  <br><br>
  <a href="#introduction">Giới thiệu</a> •
  <a href="#features">Tính năng</a> •
  <a href="#installation">Cài đặt</a> •
  <a href="#usage">Sử dụng</a> •
  <a href="#how-it-works">Cách hoạt động</a> •
  <a href="#changelog">Nhật ký thay đổi</a>
</div>

---

<h2 id="introduction">🌟 Giới thiệu</h2>

**WP-Medic CLI** là bộ công cụ cấp cứu dành cho website WordPress. Khi website của bạn bị nhiễm mã độc, bị hack, hoặc gặp lỗi nghiêm trọng, chỉ cần **1 dòng lệnh** là toàn bộ hệ thống được làm sạch và khôi phục.

Không giống các công cụ quét virus thông thường (chỉ tìm và xóa file nghi ngờ), WP-Medic sử dụng phương pháp **"Phá hủy và Tái tạo" (Nuke & Pave)** — xóa sạch toàn bộ mã nguồn hệ thống và tải lại bản gốc 100% từ WordPress.org, đảm bảo không còn bất kỳ mã độc nào sót lại.

**Dữ liệu của bạn (bài viết, hình ảnh, sản phẩm, cấu hình) luôn được bảo toàn 100%.**

### Tương thích đa nền tảng
- ✅ **Plesk Obsidian** — Tối ưu nhất
- ✅ **cPanel / WHM** — Hỗ trợ
- ✅ **Linux Standalone** — Hỗ trợ (không cần Panel)
- ✅ **Imunify360** — Tự động phối hợp (nếu có cài đặt)

---

<h2 id="features">✨ Tính năng</h2>

| Tính năng | Mô tả |
|-----------|-------|
| 🧹 **Tái tạo Core tự động** | Xóa trắng `wp-admin`, `wp-includes` và tải lại bản sạch từ WordPress.org |
| 🦠 **Quét mã độc chuyên sâu** | Phát hiện & loại bỏ webshell, db.php drop-in độc hại, zip:// wrapper injection, và các payload hacker phổ biến |
| 🔐 **Xoay vòng mật khẩu** | Tự động đổi mật khẩu Database, hệ thống, đổi khóa Salts và reset mật khẩu quản trị viên |
| 🩺 **Kiểm tra sức khỏe** | Tự động kiểm tra website có sống sau khi xử lý. Nếu phát hiện lỗi → tự động rollback mật khẩu về bản cũ |
| 🛡️ **Phối hợp Imunify360** | Tự động giải trừ cảnh báo Imunify360 trước khi xử lý, tránh xung đột khóa file |
| 👤 **Kiểm tra tài khoản** | Cảnh báo và hướng dẫn đổi tên đăng nhập nguy hiểm (`admin`, `root`) sang tên an toàn |
| 🗑️ **Dọn dẹp Database** | Xóa bình luận Spam, bài đăng rác, và đóng cửa comment/pingback vĩnh viễn |
| 🔒 **Khóa cứng wp-config** | Ép quyền `chmod 400` cho `wp-config.php` sau khi hoàn tất, bảo vệ thông tin đăng nhập DB |
| 🤖 **Hỗ trợ tự động hóa** | Xuất kết quả JSON, hỗ trợ chế độ `--auto-yes` để điều khiển từ xa qua Bot/API |

---

<h2 id="installation">🚀 Cài Đặt</h2>

Truy cập SSH (quyền root) trên Server và chạy:

```bash
curl -sL https://raw.githubusercontent.com/tuyenht/wp-medic-cli/main/install.sh | bash
```

Hệ thống sẽ tự động:
1. Tải công cụ về `/usr/local/bin/wp-medic`
2. Xác minh file tải về là mã nguồn hợp lệ
3. Cài đặt gói phụ trợ (`jq`) nếu chưa có

### Yêu cầu hệ thống

| Thành phần | Yêu cầu |
|------------|---------|
| **Hệ điều hành** | AlmaLinux / Ubuntu / CentOS / Debian |
| **Quyền** | Root (bắt buộc) |
| **WP-CLI** | Cần có sẵn (Plesk cài mặc định). Nếu thiếu, một số tính năng sẽ bị hạn chế nhưng script vẫn hoạt động |
| **Panel** | Plesk / cPanel / không cần Panel — tự động phát hiện |
| **Imunify360** | Tùy chọn — nếu có sẽ tự động phối hợp |

---

<h2 id="usage">💻 Hướng Dẫn Sử Dụng</h2>

### 1. Cứu hộ 1 website
```bash
wp-medic --domain example.com
```

### 2. Chạy thử nghiệm an toàn (không xóa gì cả)
```bash
wp-medic --domain example.com --dry-run
```

### 3. Quét toàn bộ Server
```bash
wp-medic --all-domains
```

### 4. Tự động hóa hoàn toàn (không hỏi xác nhận)
```bash
wp-medic --domain example.com --auto-yes --confirm-username my_admin
```

### 5. Xuất kết quả JSON (cho Bot/API)
```bash
wp-medic --domain example.com --output json --auto-yes
```

### Tất cả tùy chọn
```
--domain <tên miền>     Xử lý 1 website cụ thể
--all-domains           Xử lý toàn bộ website WordPress trên Server
--dry-run               Chỉ phân tích, KHÔNG xóa/sửa gì
--auto-yes, -y          Bỏ qua xác nhận, chạy tự động
--confirm-username <tên> Tên đăng nhập mới (dùng với --auto-yes)
--output json           Xuất kết quả dạng JSON
--version               Hiển thị phiên bản
--help                  Hiển thị trợ giúp
```

---

<h2 id="how-it-works">⚙️ Cách Hoạt Động</h2>

WP-Medic thực hiện tuần tự **9 bước** cho mỗi website:

```
wp-medic --domain example.com
│
├── Bước 0: Phối hợp Imunify360 (nếu có)
│   └── Giải trừ cảnh báo cũ để tránh xung đột
│
├── Bước 1: Dọn dẹp Database
│   └── Xóa spam, đóng comment/pingback
│
├── Bước 2: Tái tạo Core (Nuke & Pave)
│   └── Xóa wp-admin + wp-includes → tải lại bản sạch
│
├── Bước 3: Quét mã độc chuyên sâu
│   └── Diệt webshell, db.php drop-in, zip:// injection
│
├── Bước 4: Dọn dẹp thư mục gốc (Whitelist Mode)
│   └── Chỉ giữ file WordPress chuẩn, xóa file lạ
│
├── Bước 5: Dọn Uploads & Caches
│   └── Xóa file PHP trong uploads, xóa cache cũ
│
├── Bước 6: Xoay vòng mật khẩu
│   └── Đổi mật khẩu DB, hệ thống, salts, admin WP
│
├── Bước 7: Kiểm tra sức khỏe
│   └── Kiểm tra HTTP 200 → tự động rollback nếu lỗi
│
└── Bước 8: Khóa cứng bảo mật
    └── chmod 400 wp-config.php
```

---

<h2 id="changelog">📋 Nhật Ký Thay Đổi</h2>

### v1.4.0 (29/05/2026)
- 🆕 Tích hợp module quét mã độc chuyên sâu (db.php, webshell, zip:// injection)
- 🆕 Tự động phối hợp với Imunify360 (nếu có cài đặt)
- 🆕 Hỗ trợ đa nền tảng: Plesk / cPanel / Standalone Linux
- 🆕 Kiểm tra sức khỏe website sau khi xử lý + tự động rollback
- 🔧 Sửa lỗi đồng bộ mật khẩu Database (dùng SQL trực tiếp)
- 🔧 Bảo vệ wp-config.php — không bao giờ mở rộng quyền đọc
- 🔧 Sửa lỗi `--reassign` dùng User ID thay vì login name

### v1.3.2 (27/05/2026)
- Phiên bản đầu tiên ổn định
- Core: Nuke & Pave, Database Forensics, IAM Password Rotation
- Hỗ trợ JSON output và Dry-run mode

---

<h2 id="author">👤 Tác Giả</h2>

- **Tác giả:** [TuyenHT](https://github.com/tuyenht)

> ⚠️ **Khuyến cáo:** Mặc dù công cụ được thiết kế bảo toàn 100% dữ liệu người dùng, bạn vẫn nên **sao lưu (backup) website** trước khi thực hiện càn quét toàn Server.
