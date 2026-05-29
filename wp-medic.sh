#!/bin/bash
# ==============================================================================
# 🛡️ WP-MEDIC CLI (v1.2.0)
# Tác giả: TuyenHT
# Chức năng: Hệ thống Thanh trừng mã độc & Tự động hóa Bảo mật WP (Plesk/Linux)
# Github: https://github.com/tuyenht/wp-medic-cli
VERSION="1.2.0"
# ==============================================================================

# --- MÀU SẮC & GIAO DIỆN (UI) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- BIẾN TOÀN CỤC (GLOBAL VARS) ---
LOG_FILE="/var/log/wp-medic.log"
TARGET_DOMAIN=""
MASS_SCAN=0
DRY_RUN=0
AUTO_YES=0
OUTPUT_JSON=0
JSON_RESULT="{}"
CONFIRM_USERNAME=""

# --- HÀM 1: LOGGER (GHI LOG & HIỂN THỊ) ---
# Tự động xuất JSON nếu bật OUTPUT_JSON, ngược lại thì in ra màn hình đẹp đẽ
log_msg() {
    local type=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ghi vào file log
    echo "[$timestamp] [$type] $msg" >> "$LOG_FILE"
    
    # Nếu chạy chế độ JSON thì không in chữ màu mè ra màn hình
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        return
    fi

    case "$type" in
        "INFO")  echo -e "${CYAN}[INFO]${NC} $msg" ;;
        "OK")    echo -e "${GREEN}[OK]${NC} $msg" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $msg" ;;
        "STEP")  echo -e "\n${BLUE}➤ $msg${NC}" ;;
        *)       echo "$msg" ;;
    esac
}

# --- HÀM 2: JSON BUILDER ---
# Quản lý kết quả trả về cho Telegram Bot (Webhook)
append_json() {
    local key=$1
    local val=$2
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        # Sử dụng jq để build JSON an toàn (cần cài jq trên server)
        JSON_RESULT=$(echo "$JSON_RESULT" | jq --arg k "$key" --arg v "$val" '.[$k] = $v')
    fi
}

print_final_json() {
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        echo "$JSON_RESULT" | jq .
    fi
}

# --- HÀM 3: PARSER (XỬ LÝ THAM SỐ CLI) ---
show_help() {
    echo -e "${CYAN}🛡️ WP-Medic CLI${NC} v${VERSION} - Cỗ máy thanh trừng mã độc WordPress."
    echo "Sử dụng:"
    echo "  --domain <domain>   : (Chế độ bắn tỉa) Dọn dẹp 1 website cụ thể."
    echo "  --all-domains       : (Chế độ rải thảm) Dọn dẹp toàn bộ website trên Plesk."
    echo "  --dry-run           : Phân tích giả lập, KHÔNG xóa file thực tế."
    echo "  --output json       : Trả về kết quả JSON (dành cho Telegram Bot)."
    echo "  --auto-yes, -y      : Bỏ qua các bước xác nhận, tự động chạy toàn bộ."
    echo "  --version           : Hiển thị phiên bản hiện tại."
    echo "  --help, -h          : Hiển thị bảng trợ giúp này."
    exit 0
}

show_version() {
    echo "wp-medic v${VERSION}"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --domain) TARGET_DOMAIN="$2"; shift ;;
        --all-domains) MASS_SCAN=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --confirm-username) CONFIRM_USERNAME="$2"; shift ;;
        --output)
            if [[ "$2" == "json" ]]; then
                OUTPUT_JSON=1
                shift
            fi
            ;;
        --auto-yes|-y) AUTO_YES=1 ;;
        --version) show_version ;;
        --help|-h) show_help ;;
        *) log_msg "ERROR" "Tham số không hợp lệ: $1"; exit 1 ;;
    esac
    shift
done

# --- HÀM 4: KHỞI TẠO (BOOTSTRAP) ---
bootstrap() {
    # Kiểm tra quyền root (bắt buộc để gọi plesk api và sudo user)
    if [[ $EUID -ne 0 ]]; then
       log_msg "ERROR" "Kịch bản này BẮT BUỘC phải chạy dưới quyền root (sudo su)."
       exit 1
    fi

    # Kiểm tra WP-CLI tồn tại (bắt buộc cho mọi thao tác)
    WP_CLI_PATH=$(command -v wp 2>/dev/null)
    if [[ -z "$WP_CLI_PATH" ]]; then
        log_msg "ERROR" "WP-CLI chưa được cài đặt. Hãy cài đặt trước: https://wp-cli.org/"
        exit 1
    fi

    # Khởi tạo log file
    touch "$LOG_FILE"
    
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        # Check jq requirement for JSON mode
        if ! command -v jq &> /dev/null; then
            log_msg "ERROR" "Chế độ JSON yêu cầu gói 'jq'. Hãy cài đặt (yum install jq / apt install jq)."
            exit 1
        fi
        append_json "status" "running"
        append_json "timestamp" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    else
        echo -e "${CYAN}=================================================================${NC}"
        echo -e "${CYAN}   🛡️ KHỞI ĐỘNG CỖ MÁY WP-MEDIC CHUYÊN DỤNG 🛡️   ${NC}"
        echo -e "${CYAN}=================================================================${NC}"
        if [[ $DRY_RUN -eq 1 ]]; then
            echo -e "${YELLOW}>> ĐANG CHẠY TRONG CHẾ ĐỘ DRY-RUN (AN TOÀN - KHÔNG GHI/XÓA DATA) <<${NC}"
        fi
    fi

    if [[ -z "$TARGET_DOMAIN" && $MASS_SCAN -eq 0 ]]; then
        log_msg "ERROR" "Thiếu mục tiêu. Vui lòng sử dụng --domain <tên_miền> hoặc --all-domains."
        exit 1
    fi
}

# --- HÀM 5: TÍCH HỢP PLESK & PRIVILEGE DROP ---
run_wp() {
    local sys_user=$1
    local doc_root=$2
    shift 2
    # Bọc lệnh WP-CLI qua sudo với đường dẫn tuyệt đối để tránh lỗi PATH của sys_user
    sudo -u "$sys_user" "$WP_CLI_PATH" "$@" --path="$doc_root"
}

get_domain_info() {
    local domain=$1
    # Trích xuất SysUser và DocRoot từ Plesk
    local sys_user=$(plesk bin domain -i "$domain" 2>/dev/null | grep "FTP Login" | awk -F': ' '{print $2}' | tr -d '\r' | xargs)
    local doc_root=$(plesk bin domain -i "$domain" 2>/dev/null | grep "WWW-Root" | awk -F': ' '{print $2}' | tr -d '\r' | xargs)
    echo "$sys_user|$doc_root"
}

# --- HÀM 6: CỖ MÁY XỬ LÝ SỰ CỐ PHẪU THUẬT (SURGICAL MODULE) ---
process_domain() {
    local domain=$1
    log_msg "STEP" "Bắt đầu càn quét: $domain"
    
    local info=$(get_domain_info "$domain")
    local sys_user=$(echo "$info" | cut -d'|' -f1)
    local doc_root=$(echo "$info" | cut -d'|' -f2)

    if [[ -z "$sys_user" || -z "$doc_root" || ! -d "$doc_root" ]]; then
        log_msg "WARN" "Bỏ qua $domain: Không tìm thấy System User hoặc Document Root."
        return 1
    fi

    # Kiểm tra dấu hiệu WordPress
    if [[ ! -f "$doc_root/wp-config.php" ]]; then
        log_msg "WARN" "Bỏ qua $domain: Không phải mã nguồn WordPress."
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_msg "INFO" "[DRY-RUN] Sẽ làm sạch Database, FileSystem và Xoay vòng IAM cho $domain ($sys_user)"
        append_json "actions_$domain" "dry-run success"
        return 0
    fi

    log_msg "INFO" "Đã xác thực Chủ sở hữu: $sys_user"

    # [MODULE 3.1] DATABASE FORENSICS
    # Lấy Table Prefix thực tế của Website (chống lỗi hardcode 'wp_')
    local db_prefix=$(run_wp "$sys_user" "$doc_root" config get table_prefix 2>/dev/null | tr -d '\r')
    db_prefix=$(echo "$db_prefix" | tr -dc 'a-zA-Z0-9_')
    if [[ -z "$db_prefix" ]]; then db_prefix="wp_"; fi

    log_msg "INFO" "-> Khóa & Tiêu diệt Spam Comments/Pingbacks (Prefix: $db_prefix)..."
    
    # 1. Khóa comment toàn hệ thống bằng SQL
    run_wp "$sys_user" "$doc_root" db query "UPDATE ${db_prefix}posts SET comment_status = 'closed', ping_status = 'closed';" 2>/dev/null
    
    # 2. Xóa Spam/Trash Comments bằng SQL để tránh lỗi "Argument list too long" nếu có quá nhiều spam
    run_wp "$sys_user" "$doc_root" db query "DELETE FROM ${db_prefix}comments WHERE comment_approved = 'spam' OR comment_approved = 'trash';" 2>/dev/null
    
    # 3. Dọn dẹp mồ côi (Orphaned Comment Meta)
    run_wp "$sys_user" "$doc_root" db query "DELETE FROM ${db_prefix}commentmeta WHERE comment_id NOT IN (SELECT comment_ID FROM ${db_prefix}comments);" 2>/dev/null

    # [MODULE 3.2] FILE SYSTEM NUKE & PAVE
    log_msg "INFO" "-> Nuke & Pave (Tái tạo Core Files)..."
    # Cơ chế Safe-Nuke-and-Pave bảo vệ an toàn hệ thống tránh nghẽn mạng
    local backup_dir_admin="${doc_root}/wp-admin.bak"
    local backup_dir_includes="${doc_root}/wp-includes.bak"
    
    rm -rf "$backup_dir_admin" "$backup_dir_includes"
    if [[ -d "$doc_root/wp-admin" ]]; then mv "$doc_root/wp-admin" "$backup_dir_admin"; fi
    if [[ -d "$doc_root/wp-includes" ]]; then mv "$doc_root/wp-includes" "$backup_dir_includes"; fi
    
    # Strategy 1: WP-CLI core download (nhanh, chính xác phiên bản)
    run_wp "$sys_user" "$doc_root" core download --skip-content --force 2>/dev/null
    local dl_status=$?
    
    # Strategy 2: Fallback bằng tar.gz nếu WP-CLI thất bại (thiếu ZipArchive, lỗi mạng...)
    if [[ $dl_status -ne 0 ]] || [[ ! -d "$doc_root/wp-admin" ]] || [[ ! -d "$doc_root/wp-includes" ]]; then
        log_msg "WARN" "-> WP-CLI core download thất bại. Chuyển sang Fallback (tar.gz từ WordPress.org)..."
        local tmp_dir=$(mktemp -d)
        curl -sL -o "$tmp_dir/wordpress.tar.gz" https://wordpress.org/latest.tar.gz 2>/dev/null
        if [[ -f "$tmp_dir/wordpress.tar.gz" ]]; then
            tar -xzf "$tmp_dir/wordpress.tar.gz" -C "$tmp_dir" 2>/dev/null
            if [[ -d "$tmp_dir/wordpress/wp-admin" ]]; then
                cp -rf "$tmp_dir/wordpress/wp-admin" "$doc_root/wp-admin"
                cp -rf "$tmp_dir/wordpress/wp-includes" "$doc_root/wp-includes"
                # Sao chép các file root của WP Core (đè lên bản cũ bị tiêm nhiễm)
                find "$tmp_dir/wordpress" -maxdepth 1 -type f -exec cp -f {} "$doc_root/" \;
                dl_status=0
                log_msg "OK" "-> Tải thành công Core qua Fallback tar.gz!"
            fi
        fi
        rm -rf "$tmp_dir"
    fi
    
    if [[ $dl_status -eq 0 && -d "$doc_root/wp-admin" && -d "$doc_root/wp-includes" ]]; then
        # Đồng bộ phân quyền sở hữu cho toàn bộ file mới tải về
        local doc_root_group=$(stat -c '%g' "$doc_root" 2>/dev/null)
        if [[ -z "$doc_root_group" ]]; then doc_root_group="psacln"; fi
        chown -R "$sys_user:$doc_root_group" "$doc_root/wp-admin" "$doc_root/wp-includes" 2>/dev/null
        chown "$sys_user:$doc_root_group" "$doc_root"/*.php "$doc_root"/*.html "$doc_root"/*.txt 2>/dev/null
        rm -rf "$backup_dir_admin" "$backup_dir_includes"
        log_msg "OK" "-> Hoàn tất tái tạo mã nguồn WordPress Core!"
    else
        log_msg "ERROR" "-> Tất cả các chiến lược tải Core đều thất bại. Tiến hành khôi phục phiên bản trước đó..."
        if [[ -d "$backup_dir_admin" ]]; then mv "$backup_dir_admin" "$doc_root/wp-admin"; fi
        if [[ -d "$backup_dir_includes" ]]; then mv "$backup_dir_includes" "$doc_root/wp-includes"; fi
        
        # Đồng bộ phân quyền sở hữu động để tránh lỗi 500/403 sau khi rollback bằng quyền root
        local doc_root_group=$(stat -c '%g' "$doc_root" 2>/dev/null)
        if [[ -z "$doc_root_group" ]]; then doc_root_group="psacln"; fi
        chown -R "$sys_user:$doc_root_group" "$doc_root/wp-admin" "$doc_root/wp-includes" 2>/dev/null
        
        append_json "core_status" "download_failed_rolled_back"
    fi
    
    # [MODULE 3.3] ROOT DIRECTORY SANITIZATION (WHITELIST APPROACH)
    # Chiến lược: Chỉ giữ lại các file/thư mục thuộc WP Core whitelist, tiêu diệt toàn bộ phần còn lại
    log_msg "INFO" "-> Quét & Tiêu diệt file rác/mã độc tại Document Root (Whitelist Mode)..."
    
    # Danh sách file hợp lệ tại thư mục gốc WordPress Core
    local wp_root_whitelist="index.php|wp-activate.php|wp-blog-header.php|wp-comments-post.php|wp-config.php|wp-config-sample.php|wp-cron.php|wp-links-opml.php|wp-load.php|wp-login.php|wp-mail.php|wp-settings.php|wp-signup.php|wp-trackback.php|xmlrpc.php|license.txt|readme.html|.htaccess|robots.txt|wp-cli.yml"
    
    # Danh sách thư mục hợp lệ tại thư mục gốc WordPress
    local wp_dir_whitelist="wp-admin|wp-content|wp-includes|.well-known"
    
    # Xóa file rác (không nằm trong whitelist)
    local rogue_count=0
    while IFS= read -r rogue_file; do
        local basename_file=$(basename "$rogue_file")
        if ! echo "$basename_file" | grep -qE "^($wp_root_whitelist)$"; then
            rm -f "$rogue_file"
            log_msg "WARN" "   Tiêu diệt file lạ: $basename_file"
            rogue_count=$((rogue_count + 1))
        fi
    done < <(find "$doc_root" -maxdepth 1 -type f 2>/dev/null)
    
    # Xóa thư mục lạ (không nằm trong whitelist)
    while IFS= read -r rogue_dir; do
        local basename_dir=$(basename "$rogue_dir")
        if ! echo "$basename_dir" | grep -qE "^($wp_dir_whitelist)$"; then
            rm -rf "$rogue_dir"
            log_msg "WARN" "   Tiêu diệt thư mục lạ: $basename_dir/"
            rogue_count=$((rogue_count + 1))
        fi
    done < <(find "$doc_root" -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null)
    
    # Xóa file backup config nguy hiểm (lộ DB credentials)
    rm -f "$doc_root/wp-config.php.bak" "$doc_root/wp-config.php.old" "$doc_root/wp-config.php.save" "$doc_root/wp-config.php~" 2>/dev/null
    
    if [[ $rogue_count -gt 0 ]]; then
        log_msg "OK" "   Đã tiêu diệt $rogue_count đối tượng khả nghi tại Document Root."
        append_json "rogue_files_removed" "$rogue_count"
    else
        log_msg "OK" "   Document Root sạch sẽ, không phát hiện file/thư mục lạ."
    fi

    # [MODULE 3.4] UPLOADS & CACHES CLEANUP
    log_msg "INFO" "-> Càn quét Uploads & Caches..."
    # Bảo toàn file .js hợp lệ của plugin giao diện, chỉ triệt tiêu 100% mã thực thi nguy hiểm
    find "$doc_root/wp-content/uploads" -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.py" -o -name "*.pl" -o -name "*.suspected" \) -delete 2>/dev/null
    rm -rf "$doc_root/wp-content/cache" "$doc_root/wp-content/w3tc-config" "$doc_root/wp-content/litespeed" 2>/dev/null

    # [MODULE 3.3] FLUSH REWRITE
    run_wp "$sys_user" "$doc_root" rewrite flush --hard 2>/dev/null

    # [MODULE 4] IDENTITY AUTOMATION (IAM)
    log_msg "INFO" "-> Xoay vòng Mật khẩu Hệ thống & Salts (Amnesia Protocol)..."
    
    # 4.1 Xoay Plesk SysUser (Password chỉ dùng chữ/số để tương thích tuyệt đối với Plesk API)
    local new_sys_pass=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
    plesk bin sysuser -u "$sys_user" -passwd "$new_sys_pass" &>/dev/null
    
    # 4.2 Xoay MySQL Pass & Salts
    local db_user=$(run_wp "$sys_user" "$doc_root" config get DB_USER 2>/dev/null | tr -d '\r')
    if [[ -n "$db_user" ]]; then
        local new_db_pass=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
        # Đảo ngược trình tự: Cập nhật wp-config.php trước khi đổi trên DB Server để tránh mất kết nối giữa chừng gây crash lệnh
        run_wp "$sys_user" "$doc_root" config set DB_PASSWORD "$new_db_pass" 2>/dev/null
        plesk bin database --update-dbuser "$db_user" -passwd "$new_db_pass" &>/dev/null
    fi
    run_wp "$sys_user" "$doc_root" config shuffle-salts 2>/dev/null

    # 4.3 Khóa WordPress Passwords & Interactive Audit Username
    log_msg "INFO" "-> Cưỡng chế Reset Mật khẩu Quản trị viên WP..."
    local admins=$(run_wp "$sys_user" "$doc_root" user list --role=administrator --field=user_login 2>/dev/null)
    local brand_name=$(echo "$domain" | cut -d'.' -f1)
    
    for admin_user in $admins; do
        # 1. Quét qua và reset mọi mật khẩu Admin
        local random_hash=$(head -c 150 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
        run_wp "$sys_user" "$doc_root" user update "$admin_user" --user_pass="$random_hash" 2>/dev/null
        
        # 2. Xử lý Username Nhạy cảm (Nuke-and-Reassign)
        if [[ "$admin_user" == "admin" || "$admin_user" == "root" || "$admin_user" == "administrator" || "$admin_user" == "manager" || "$admin_user" == "test" || "$admin_user" == "$brand_name" ]]; then
            log_msg "WARN" "Phát hiện Username nhạy cảm dễ bị Brute-force: $admin_user"
            
            local new_username=""
            if [[ $AUTO_YES -eq 1 ]]; then
                # Chế độ Bot/ChatOps
                if [[ -n "$CONFIRM_USERNAME" ]]; then
                    new_username="$CONFIRM_USERNAME"
                else
                    log_msg "INFO" "Bỏ qua đổi tên do chạy chế độ Headless và thiếu tham số --confirm-username."
                fi
            else
                # Chế độ Terminal Tương tác
                echo -e "${YELLOW}>> ĐỀ XUẤT ĐỔI TÊN ĐỂ TRÁNH BOTNET: Gợi ý các tên mang thương hiệu: ${brand_name}_admin, qtri_${brand_name}, admin_${brand_name}${NC}"
                read -p "Nhập Username mới (Hoặc nhấn Enter để bỏ qua): " user_input
                new_username="$user_input"
            fi
            
            if [[ -n "$new_username" ]]; then
                log_msg "INFO" "Đang thực thi Nuke-and-Reassign: $admin_user -> $new_username..."
                local admin_email=$(run_wp "$sys_user" "$doc_root" user get "$admin_user" --field=user_email 2>/dev/null)
                if [[ -z "$admin_email" ]]; then admin_email="admin@$domain"; fi
                
                # Tạo user mới với hash random để an toàn tuyệt đối
                local safe_pass=$(head -c 150 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
                run_wp "$sys_user" "$doc_root" user create "$new_username" "$admin_email" --role=administrator --user_pass="$safe_pass" 2>/dev/null
                
                # Truy xuất User ID số của user mới (WP-CLI --reassign yêu cầu ID, không phải login)
                local new_user_id=$(run_wp "$sys_user" "$doc_root" user get "$new_username" --field=ID 2>/dev/null | tr -d '\r')
                if [[ -n "$new_user_id" ]]; then
                    # Xóa user cũ và chuyển toàn bộ data sang user mới bằng ID
                    run_wp "$sys_user" "$doc_root" user delete "$admin_user" --reassign="$new_user_id" 2>/dev/null
                    log_msg "OK" "Hoàn tất đổi Username: $admin_user -> $new_username (ID: $new_user_id). Toàn bộ Data được bảo toàn!"
                else
                    log_msg "ERROR" "Không thể truy xuất ID của user mới '$new_username'. Bỏ qua xóa user cũ để bảo toàn dữ liệu."
                fi
            fi
        fi
    done

    log_msg "OK" "Hoàn tất làm sạch & Đóng băng $domain!"
    append_json "actions_$domain" "success"
}

# --- MAIN EXECUTION ---
bootstrap

if [[ $MASS_SCAN -eq 1 ]]; then
    log_msg "STEP" "BẮT ĐẦU CHẾ ĐỘ QUÉT RẢI THẢM (MASS QUARANTINE)"
    # Lấy danh sách domains từ Plesk
    domains=$(plesk bin domain -l 2>/dev/null)
    for dom in $domains; do
        process_domain "$dom"
    done
else
    process_domain "$TARGET_DOMAIN"
fi

log_msg "STEP" "Chu trình hoàn tất."
print_final_json
exit 0
