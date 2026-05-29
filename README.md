# 🛡️ WP-Medic CLI (Diamond Edition)

<div align="center">
  <p><strong>Cỗ Máy Thanh Trừng Mã Độc & Tự Động Hóa Bảo Mật WordPress Tối Thượng Dành Cho Máy Chủ Plesk/Linux.</strong></p>
  <a href="https://github.com/tuyenht/wp-medic-cli">Tài liệu tham khảo</a> •
  <a href="#-tính-năng-cốt-lõi">Tính năng</a> •
  <a href="#-cài-đặt">Cài đặt</a> •
  <a href="#-hướng-dẫn-sử-dụng">Sử dụng</a>
</div>

---

**WP-Medic CLI** không phải là một công cụ quét virus thông thường (Antivirus Scanner). Đây là một hệ thống **Surgical Incident Response (Ứng cứu sự cố phẫu thuật)** được xây dựng dựa trên tiêu chuẩn bảo mật *Diamond++*. 

Thay vì sử dụng phương pháp "Blacklist" (quét và xóa file nghi ngờ) vốn đầy rẫy lỗ hổng và bỏ sót mã độc, WP-Medic áp dụng chiến thuật **"Whitelist Isolation" & "Nuke and Pave"**. Cỗ máy này phá hủy hoàn toàn phần Lõi (Core) của hệ thống cũ và tái thiết lập (Pave) lại bản gốc tinh khiết từ WordPress.org, kết hợp xoay vòng toàn bộ Danh tính (Identity) chỉ trong vài giây.

## 🌟 Tính năng Cốt Lõi (Core Features)

### 1. Zero-Blind Trust: Xóa Sổ File & Phục Hồi (Nuke & Pave)
- Xóa sạch 100% các file thực thi `.php` tại thư mục gốc (Ngoại trừ `wp-config.php`).
- Băm nát thư mục `wp-admin` và `wp-includes` và tải đè bản mới bằng WP-CLI.
- Tự động quét và diệt Webshell ẩn giấu trong `wp-content/uploads`.

### 2. Quản Trị Danh Tính Tự Động (Identity & Access Automation)
- Sinh mật khẩu ngẫu nhiên (High-Entropy) và **Đổi Mật khẩu Database** tự động qua Plesk API.
- Bắt buộc **Khởi tạo lại Mật khẩu** toàn bộ Admin (The Amnesia Protocol).
- **Interactive Audit:** Khuyến cáo và gợi ý đổi các Username nhạy cảm (như `admin`, `root`) thành các tên an toàn mang dấu ấn thương hiệu (VD: `tênmiền_admin`).

### 3. Xóa sổ Rác Database (Database Forensics)
- Lọc máu Spam Comments: Xóa sạch hàng chục ngàn bình luận spam chỉ trong chớp mắt bằng Regex (`casino|bet|viagra...`).
- Xóa rác SEO ảo (SEO Spam Post/Pages).
- Khóa vĩnh viễn (Lockdown) tính năng Comment trên **TẤT CẢ** các bài viết cũ và mới để chặn đường lùi của Botnet.

### 4. Tương Thích ChatOps & Telegram Bot
- Chế độ **Headless (Câm lặng)** chạy bằng cờ `--auto-yes`.
- Giao thức đầu ra **JSON Output** (`--output json`) cho phép dễ dàng tích hợp API và điều khiển từ xa qua Telegram Bot mà không cần login SSH.

---

## 🚀 Cài Đặt (Installation)

WP-Medic CLI là một file Bash thực thi độc lập (Standalone Portable Binary). Không cần cài đặt dependencies cồng kềnh, chỉ cần Server của bạn có sẵn WP-CLI và Plesk.

Chạy lệnh sau dưới quyền `root`:
```bash
curl -sL https://raw.githubusercontent.com/tuyenht/wp-medic-cli/main/install.sh | bash
```
Lệnh trên sẽ tải file cấu hình, phân quyền thực thi (`chmod +x`) và đặt vào `/usr/local/bin/wp-medic`.

---

## 🛠 Hướng Dẫn Sử Dụng (Usage)

### 1. Chế độ Bắn Tỉa (Cứu Hộ 1 Website)
Sử dụng khi khách hàng báo cáo 1 website cụ thể bị nhiễm độc.
```bash
wp-medic --domain example.com
```

### 2. Chế độ Quét Rải Thảm Toàn Server (Mass Quarantine)
Tool tự động móc nối Plesk API, lấy danh sách toàn bộ domains, tìm kiếm cài đặt WordPress và áp dụng SOP làm sạch toàn diện lên hàng trăm website xuyên đêm.
```bash
wp-medic --all-domains
```

### 3. Chế độ Kiểm Toán (Dry-Run / Audit Mode)
An toàn tuyệt đối. Phân tích, thống kê những file sẽ bị xóa, số lượng spam comment phát hiện, nhưng không thao tác thực tế.
```bash
wp-medic --domain example.com --dry-run
```

### 4. Chế độ ChatOps (Tích hợp Bot/API)
Chạy tự động 100% không cần tương tác (Non-interactive) và trả về định dạng JSON chuẩn.
```bash
wp-medic --domain example.com --confirm-username example_admin --auto-yes --output json
```

*Ví dụ Kết quả trả về (JSON):*
```json
{
  "status": "success",
  "domain": "example.com",
  "actions": {
    "core_nuked": true,
    "spam_comments_deleted": 1542,
    "db_password_rotated": true,
    "salts_shuffled": true
  },
  "timestamp": "2026-05-29T15:00:00Z"
}
```

---

## 🔒 Yêu Cầu Hệ Thống (Requirements)
*   **Hệ điều hành:** AlmaLinux / Ubuntu / CentOS / RHEL.
*   **Môi trường:** Plesk Obsidian (yêu cầu quyền gọi `plesk bin`).
*   **Công cụ phụ trợ:** `wp-cli` (đã được cài đặt global), `openssl`, `jq` (để parse JSON).

---

## 👤 Đóng Góp & Tác Giả (Author)

Công cụ được thiết kế và bảo trì bởi **TuyenHT** và cộng đồng chuyên gia bảo mật.
*   **Github:** [https://github.com/tuyenht](https://github.com/tuyenht)

**Disclaimer:** Công cụ can thiệp rất sâu vào Database và File System. Khuyến cáo luôn bật chế độ Backup định kỳ của Plesk trước khi sử dụng `--all-domains`. Dù hệ thống an toàn tuyệt đối nhờ cơ chế Privilege Drop (`sudo -u`), người dùng vẫn nên chạy `--dry-run` trước khi thực thi thực tế.
