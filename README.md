<div align="center">
  <h1>🛡️ WP-Medic CLI</h1>
  <p><strong>Cỗ máy 1-Click tự động diệt sạch mã độc, phục hồi Core WordPress và xoay vòng bảo mật.</strong></p>
  <a href="#introduction">Giới thiệu</a> •
  <a href="#features">Tính năng</a> •
  <a href="#installation">Cài đặt 1-Click</a> •
  <a href="#usage">Sử dụng</a>
</div>

---

<h2 id="introduction">🌟 Giới thiệu (Introduction)</h2>

**WP-Medic CLI** không phải là một công cụ quét virus (Scanner) thông thường. Khi website của bạn bị nhiễm mã độc, việc quét và xóa từng file thường không triệt để và dễ bị tái nhiễm.

Công cụ này sử dụng phương pháp **"Phá hủy và Tái tạo" (Nuke & Pave)**:
1. Phá hủy toàn bộ các file hệ thống (Core) có nguy cơ bị tiêm nhiễm mã độc.
2. Tải về nguyên bản sạch 100% từ máy chủ chính thức của WordPress.org.
3. Giữ nguyên vẹn 100% dữ liệu bài viết, hình ảnh, sản phẩm và cấu hình của bạn.

Tất cả diễn ra hoàn toàn tự động chỉ với **1 dòng lệnh**, cực kỳ dễ sử dụng ngay cả khi bạn không rành về kỹ thuật Server.

---

<h2 id="features">✨ Tính năng Cốt lõi (Core Features)</h2>

- 🧹 **Tái tạo Lõi Tự động:** Xóa trắng `wp-admin`, `wp-includes` và tải lại bản sạch.
- 🔐 **Xoay vòng Bảo mật:** Tự động đổi mật khẩu Database, đổi khóa Salts và vô hiệu hóa các kết nối FTP trái phép.
- 🛡️ **Quản trị Danh tính (Identity Audit):** Tự động cảnh báo và hướng dẫn bạn đổi các tên đăng nhập nguy hiểm (như `admin`, `root`) sang tên an toàn.
- 🗑️ **Lọc máu Database:** Xóa sạch hàng chục ngàn bình luận Spam, SEO ẩn giấu sâu trong cơ sở dữ liệu.
- 🤖 **Thân thiện Tự động hóa:** Hỗ trợ xuất dữ liệu JSON để điều khiển từ xa qua Telegram Bot hoặc API.

---

<h2 id="installation">🚀 Cài Đặt (Installation)</h2>

Chỉ mất 3 giây để cài đặt. Truy cập vào SSH (quyền root) trên Server của bạn và chạy duy nhất 1 dòng lệnh này:

```bash
curl -sL https://raw.githubusercontent.com/tuyenht/wp-medic-cli/main/install.sh | bash
```

*Hệ thống sẽ tự động tải công cụ và thiết lập lệnh `wp-medic` cho Server của bạn.*

---

<h2 id="usage">💻 Hướng Dẫn Sử Dụng (Usage)</h2>

Sau khi cài đặt, bạn có thể gọi công cụ này ở bất kỳ đâu trên Server.

### 1. Cứu Hộ Nhanh 1 Website (Bắn Tỉa)
Nếu bạn có một website tên là `example.com` bị nhiễm mã độc, hãy chạy lệnh:
```bash
wp-medic --domain example.com
```

### 2. Chạy Thử Nghiệm An Toàn (Dry-Run)
Công cụ sẽ quét, thống kê và báo cáo những gì nó MONG MUỐN làm (như số lượng file sẽ bị xóa, số user nguy hiểm), nhưng **KHÔNG** thực sự xóa bất kỳ dữ liệu nào.
```bash
wp-medic --domain example.com --dry-run
```

### 3. Càn Quét Toàn Bộ Server (Dành riêng cho Plesk)
Lệnh này sẽ lấy danh sách toàn bộ các website đang có trên Server Plesk của bạn, và tự động làm sạch từng website một xuyên đêm.
```bash
wp-medic --all-domains
```

### 4. Tự động hóa hoàn toàn (Auto-yes)
Bỏ qua mọi câu hỏi xác nhận (Y/N), tự động ép đổi tên user `admin` thành `my_admin`:
```bash
wp-medic --domain example.com --auto-yes --confirm-username my_admin
```

---

<h2 id="requirements">🔒 Yêu Cầu Hệ Thống (Requirements)</h2>

- **Hệ điều hành:** AlmaLinux / Ubuntu / CentOS / Debian.
- **Bảng điều khiển:** Hỗ trợ tốt nhất cho **Plesk Obsidian**.
- **Yêu cầu nội bộ:** Hệ thống cần có sẵn `wp-cli` (mặc định Plesk đã có).

---

<h2 id="author">👤 Tác Giả & Đóng Góp</h2>

Mã nguồn được thiết kế theo tiêu chuẩn hệ thống doanh nghiệp nghiêm ngặt nhất.
- **Tác giả:** [TuyenHT](https://github.com/tuyenht)

*⚠️ **Khuyến cáo:** Mặc dù công cụ được thiết kế bảo vệ an toàn 100% dữ liệu người dùng, bạn vẫn luôn nên Backup (sao lưu) website trước khi thực hiện thao tác càn quét toàn Server.*
