#!/bin/bash
# ==============================================================================
# 🛡️ WP-MEDIC CLI (v1.4.0) — WordPress Emergency Security Toolkit
# Tác giả: TuyenHT
# Chức năng: Phát hiện & loại bỏ mã độc, tái tạo Core, xoay vòng mật khẩu,
#            quét malware chuyên sâu, và tự động kiểm tra sức khỏe website.
# Github: https://github.com/tuyenht/wp-medic-cli
# Tương thích: Plesk / cPanel / Standalone Linux (tự động phát hiện)
VERSION="1.4.0"
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

# --- FEATURE FLAGS (Tự động phát hiện khả năng hệ thống) ---
HAS_PLESK=0
HAS_IMUNIFY=0
HAS_WP_CLI=0
HAS_MYSQL=0

# --- HÀM 1: LOGGER (GHI LOG & HIỂN THỊ) ---
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
append_json() {
    local key=$1
    local val=$2
    if [[ $OUTPUT_JSON -eq 1 ]]; then
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
    echo ""
    echo "Sử dụng:"
    echo "  --domain <domain>   : (Chế độ bắn tỉa) Dọn dẹp 1 website cụ thể."
    echo "  --all-domains       : (Chế độ rải thảm) Dọn dẹp toàn bộ website WordPress."
    echo "  --dry-run           : Phân tích giả lập, KHÔNG xóa file thực tế."
    echo "  --output json       : Trả về kết quả JSON (dành cho Telegram Bot)."
    echo "  --auto-yes, -y      : Bỏ qua các bước xác nhận, tự động chạy toàn bộ."
    echo "  --version           : Hiển thị phiên bản hiện tại."
    echo "  --help, -h          : Hiển thị bảng trợ giúp này."
    echo ""
    echo "Tương thích: Plesk / cPanel / Standalone Linux (tự động phát hiện)."
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

# --- HÀM 4: KHỞI TẠO & PHÁT HIỆN KHẢ NĂNG (BOOTSTRAP) ---
detect_capabilities() {
    # Phát hiện Plesk
    if command -v plesk &> /dev/null; then
        HAS_PLESK=1
        log_msg "INFO" "Phát hiện: Plesk Panel ✓"
    else
        log_msg "INFO" "Plesk không có mặt → Chế độ Standalone Linux"
    fi

    # Phát hiện Imunify360
    if command -v imunify360-agent &> /dev/null; then
        HAS_IMUNIFY=1
        log_msg "INFO" "Phát hiện: Imunify360 ✓"
    else
        log_msg "INFO" "Imunify360 không có mặt → Bỏ qua module Bridge"
    fi

    # Phát hiện WP-CLI
    WP_CLI_PATH=$(command -v wp 2>/dev/null)
    if [[ -n "$WP_CLI_PATH" ]]; then
        HAS_WP_CLI=1
    else
        log_msg "WARN" "WP-CLI chưa được cài đặt → Một số tính năng bị hạn chế"
    fi

    # Phát hiện MySQL client (cho DB password sync trực tiếp)
    if command -v mysql &> /dev/null; then
        HAS_MYSQL=1
    fi
}

bootstrap() {
    # Kiểm tra quyền root
    if [[ $EUID -ne 0 ]]; then
       log_msg "ERROR" "Kịch bản này BẮT BUỘC phải chạy dưới quyền root (sudo su)."
       exit 1
    fi

    # Khởi tạo log file
    touch "$LOG_FILE"
    
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        if ! command -v jq &> /dev/null; then
            log_msg "ERROR" "Chế độ JSON yêu cầu gói 'jq'. Hãy cài đặt (yum install jq / apt install jq)."
            exit 1
        fi
        append_json "status" "running"
        append_json "timestamp" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    else
        echo -e "${CYAN}=================================================================${NC}"
        echo -e "${CYAN}   🛡️ KHỞI ĐỘNG CỖ MÁY WP-MEDIC v${VERSION} 🛡️   ${NC}"
        echo -e "${CYAN}=================================================================${NC}"
        if [[ $DRY_RUN -eq 1 ]]; then
            echo -e "${YELLOW}>> ĐANG CHẠY TRONG CHẾ ĐỘ DRY-RUN (AN TOÀN - KHÔNG GHI/XÓA DATA) <<${NC}"
        fi
    fi

    # Phát hiện khả năng hệ thống
    detect_capabilities

    if [[ -z "$TARGET_DOMAIN" && $MASS_SCAN -eq 0 ]]; then
        log_msg "ERROR" "Thiếu mục tiêu. Vui lòng sử dụng --domain <tên_miền> hoặc --all-domains."
        exit 1
    fi
}

# --- HÀM 5: PRIVILEGE DROP & DOMAIN RESOLUTION ---
run_wp() {
    local sys_user=$1
    local doc_root=$2
    shift 2
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        sudo -u "$sys_user" "$WP_CLI_PATH" "$@" --path="$doc_root" 2>/dev/null
    fi
}

get_domain_info() {
    local domain=$1
    local sys_user=""
    local doc_root=""

    if [[ $HAS_PLESK -eq 1 ]]; then
        # Strategy 1: Plesk CLI
        sys_user=$(plesk bin domain -i "$domain" 2>/dev/null | grep "FTP Login" | awk -F': ' '{print $2}' | tr -d '\r' | xargs)
        doc_root=$(plesk bin domain -i "$domain" 2>/dev/null | grep "WWW-Root" | awk -F': ' '{print $2}' | tr -d '\r' | xargs)
    fi

    if [[ -z "$doc_root" ]]; then
        # Strategy 2: Tự dò filesystem (Plesk layout)
        if [[ -d "/var/www/vhosts/$domain/httpdocs" ]]; then
            doc_root="/var/www/vhosts/$domain/httpdocs"
            sys_user=$(stat -c '%U' "$doc_root" 2>/dev/null)
        # Strategy 3: cPanel layout
        elif [[ -d "/home/*/public_html" ]]; then
            for d in /home/*/public_html; do
                if [[ -f "$d/wp-config.php" ]]; then
                    local site_url=$(grep "siteurl" "$d/wp-config.php" 2>/dev/null | grep -oP "https?://[^'\"]+")
                    if echo "$site_url" | grep -q "$domain"; then
                        doc_root="$d"
                        sys_user=$(stat -c '%U' "$d" 2>/dev/null)
                        break
                    fi
                fi
            done
        fi
    fi

    echo "$sys_user|$doc_root"
}

# Liệt kê tất cả domains WordPress trên server (multi-platform)
list_all_wp_domains() {
    if [[ $HAS_PLESK -eq 1 ]]; then
        plesk bin domain -l 2>/dev/null
    else
        # Fallback: quét filesystem cho wp-config.php
        find /var/www/vhosts/*/httpdocs /home/*/public_html -maxdepth 1 -name "wp-config.php" 2>/dev/null | while read -r cfg; do
            local parent=$(dirname "$cfg")
            # Trích xuất domain từ đường dẫn
            if echo "$parent" | grep -q "/var/www/vhosts/"; then
                echo "$parent" | sed 's|/var/www/vhosts/||; s|/httpdocs||'
            else
                basename "$(dirname "$parent")"
            fi
        done
    fi
}

# =============================================================================
# MODULE 0: IMUNIFY360 BRIDGE (Tích hợp từ Diamond Vaccine v5.0)
# Giải trừ blacklist & Ghost Malware state TRƯỚC khi phẫu thuật
# Graceful: Tự bỏ qua nếu Imunify360 không tồn tại
# =============================================================================
imunify360_bridge() {
    local domain=$1
    local doc_root=$2

    if [[ $HAS_IMUNIFY -eq 0 ]]; then
        return 0
    fi

    log_msg "INFO" "-> Imunify360 Bridge: Giải trừ blacklist cho $domain..."

    # 1. Ép Proactive Defense sang KILL mode (đảm bảo nhất quán)
    imunify360-agent config update '{"PROACTIVE_DEFENCE": {"mode": "KILL"}}' &>/dev/null

    # 2. Cleanup toàn bộ malicious entries liên quan đến domain
    #    Sử dụng cleanup-all cho background cleanup
    imunify360-agent malware malicious cleanup-all &>/dev/null &

    # 3. Tạm tắt realtime scan cho doc_root trong quá trình phẫu thuật
    #    bằng cách thêm vào ignore list
    imunify360-agent malware ignore add "$doc_root/wp-admin" &>/dev/null
    imunify360-agent malware ignore add "$doc_root/wp-includes" &>/dev/null

    log_msg "OK" "   Imunify360 Bridge hoàn tất. Đường phẫu thuật đã thông."
}

# Gỡ bỏ ignore tạm thời sau khi phẫu thuật xong (để Imunify360 bảo vệ lại)
imunify360_restore() {
    local doc_root=$1

    if [[ $HAS_IMUNIFY -eq 0 ]]; then
        return 0
    fi

    # Xóa ignore tạm thời — Imunify360 sẽ bảo vệ bình thường trở lại
    imunify360-agent malware ignore delete path "$doc_root/wp-admin" &>/dev/null
    imunify360-agent malware ignore delete path "$doc_root/wp-includes" &>/dev/null
}

# =============================================================================
# MODULE VACCINE: DEEP MALWARE KILL
# Quét & diệt các loại mã độc chuyên sâu mà Core Nuke không xử lý được
# (db.php drop-in, zip:// wrapper injection, webshell payloads)
# Graceful: Hoạt động 100% standalone, không phụ thuộc bất kỳ panel nào
# =============================================================================
deep_malware_kill() {
    local doc_root=$1
    log_msg "INFO" "-> Quét mã độc chuyên sâu (Deep Malware Kill)..."

    # 1. Quét & xóa db.php drop-in độc hại (bỏ qua W3TC, Query Monitor, Redis)
    local db_dropin="$doc_root/wp-content/db.php"
    if [[ -f "$db_dropin" ]]; then
        if ! grep -qE "W3 Total Cache|Query Monitor|Redis Object Cache|WP_CACHE|LudicrousDB" "$db_dropin" 2>/dev/null; then
            rm -f "$db_dropin"
            log_msg "WARN" "   Tiêu diệt db.php drop-in độc hại!"
        fi
    fi

    # 2. Xóa zip:// wrapper injection & obfuscated base64 payloads
    #    CHỈ quét thư mục root + mu-plugins + uploads (bỏ qua plugins/themes để tránh false positive)
    local scan_dirs=(
        "$doc_root"
        "$doc_root/wp-content/mu-plugins"
        "$doc_root/wp-content/uploads"
    )
    for scan_dir in "${scan_dirs[@]}"; do
        [[ ! -d "$scan_dir" ]] && continue
        # Chỉ quét maxdepth 1 cho root, recursive cho mu-plugins/uploads
        local depth_flag=""
        if [[ "$scan_dir" == "$doc_root" ]]; then
            depth_flag="-maxdepth 1"
        fi
        find "$scan_dir" $depth_flag -name "*.php" -type f 2>/dev/null | while read -r phpfile; do
            if grep -qE 'U2k2A|zip://|eval\(base64_decode|eval\(gzinflate|\$GLOBALS\[.{0,3}\]\(' "$phpfile" 2>/dev/null; then
                sed -i '/U2k2A/d; /zip:\/\//d' "$phpfile" 2>/dev/null
                log_msg "WARN" "   Xóa injection trong: $(basename "$phpfile")"
            fi
        done
    done

    # 3. Xóa payload đặc trưng của hacker (webshell files)
    local payload_count=0
    for payload_name in "cha.php" "cha1.php" "x.php" "shell.php" "c99.php" "r57.php" "wso.php" "b374k.php" "alfa.php"; do
        local found=$(find "$doc_root" -name "$payload_name" -type f 2>/dev/null)
        if [[ -n "$found" ]]; then
            find "$doc_root" -name "$payload_name" -type f -delete 2>/dev/null
            log_msg "WARN" "   Tiêu diệt payload: $payload_name"
            payload_count=$((payload_count + 1))
        fi
    done

    # 4. Xóa file .zip khả nghi tải lên gần đây (trong vòng 3 ngày)
    find "$doc_root/wp-content/uploads" -name "*.zip" -mtime -3 -delete 2>/dev/null

    log_msg "OK" "   Quét mã độc chuyên sâu hoàn tất."
}

# =============================================================================
# MODULE DB-SYNC: Đồng bộ mật khẩu DB an toàn (Multi-platform)
# Giải quyết Bug #3: plesk bin database dùng sai tham số
# Graceful: Tự chọn phương thức phù hợp với hệ thống
# =============================================================================
db_password_sync() {
    local db_user=$1
    local new_pass=$2
    local db_name=$3

    # Strategy 1: plesk db (SQL trực tiếp qua Plesk admin credentials)
    if [[ $HAS_PLESK -eq 1 ]]; then
        # Tạo file SQL tạm để tránh lỗi quoting trên shell
        local tmp_sql=$(mktemp /tmp/wp-medic-db-XXXX.sql)
        # Thử ALTER USER trước (MariaDB 10.2+ / MySQL 5.7+)
        cat > "$tmp_sql" << EOSQL
ALTER USER '${db_user}'@'%' IDENTIFIED BY '${new_pass}';
FLUSH PRIVILEGES;
EOSQL
        if ! plesk db < "$tmp_sql" &>/dev/null; then
            # Fallback: thử với localhost host
            cat > "$tmp_sql" << EOSQL
ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}';
FLUSH PRIVILEGES;
EOSQL
            if ! plesk db < "$tmp_sql" &>/dev/null; then
                # Fallback cuối: SET PASSWORD (MariaDB cũ)
                cat > "$tmp_sql" << EOSQL
SET PASSWORD FOR '${db_user}'@'%' = PASSWORD('${new_pass}');
SET PASSWORD FOR '${db_user}'@'localhost' = PASSWORD('${new_pass}');
FLUSH PRIVILEGES;
EOSQL
                plesk db < "$tmp_sql" &>/dev/null
            fi
        fi
        rm -f "$tmp_sql"
        return $?
    fi

    # Strategy 2: MySQL client trực tiếp (non-Plesk)
    if [[ $HAS_MYSQL -eq 1 ]]; then
        mysql -e "ALTER USER '${db_user}'@'%' IDENTIFIED BY '${new_pass}'; FLUSH PRIVILEGES;" &>/dev/null \
        || mysql -e "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}'; FLUSH PRIVILEGES;" &>/dev/null
        return $?
    fi

    log_msg "WARN" "   Không thể đồng bộ DB password: Thiếu cả Plesk lẫn MySQL client."
    return 1
}

# =============================================================================
# MODULE HEALTHCHECK: Kiểm tra website sống sau phẫu thuật
# Giải quyết Bug #4: Script báo OK nhưng website chết
# =============================================================================
post_op_healthcheck() {
    local domain=$1
    local old_db_pass=$2
    local db_user=$3
    local doc_root=$4
    local sys_user=$5

    log_msg "INFO" "-> Healthcheck: Kiểm tra $domain sau phẫu thuật..."

    # Thử HTTPS trước, fallback HTTP
    local http_code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 10 "https://$domain" 2>/dev/null)
    if [[ "$http_code" == "000" ]]; then
        http_code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 10 "http://$domain" 2>/dev/null)
    fi

    if [[ "$http_code" == "200" || "$http_code" == "301" || "$http_code" == "302" ]]; then
        log_msg "OK" "   ✅ Healthcheck PASSED: HTTP $http_code"
        append_json "healthcheck_$domain" "PASS:$http_code"
        return 0
    fi

    log_msg "ERROR" "   ❌ Healthcheck FAILED: HTTP $http_code"
    append_json "healthcheck_$domain" "FAIL:$http_code"

    # === EMERGENCY ROLLBACK: Khôi phục mật khẩu DB cũ ===
    if [[ -n "$old_db_pass" && -n "$db_user" ]]; then
        log_msg "WARN" "   🔄 Đang rollback mật khẩu DB về bản gốc..."
        
        # Rollback wp-config.php
        if [[ $HAS_WP_CLI -eq 1 ]]; then
            run_wp "$sys_user" "$doc_root" config set DB_PASSWORD "$old_db_pass"
        else
            sed -i "s|define.*DB_PASSWORD.*|define('DB_PASSWORD', '${old_db_pass}');|" "$doc_root/wp-config.php" 2>/dev/null
        fi
        
        # Rollback MySQL password
        db_password_sync "$db_user" "$old_db_pass" ""

        # Kiểm tra lại sau rollback
        sleep 2
        local recheck=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 10 "https://$domain" 2>/dev/null)
        if [[ "$recheck" == "200" || "$recheck" == "301" || "$recheck" == "302" ]]; then
            log_msg "OK" "   ✅ Rollback thành công! Website sống lại: HTTP $recheck"
        else
            log_msg "ERROR" "   ⚠️ Rollback không cứu được. Cần kiểm tra thủ công: $domain"
        fi
    fi

    return 1
}

# =============================================================================
# MAIN ENGINE: CỖ MÁY PHẪU THUẬT TỔNG HỢP
# =============================================================================
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

    # ===========================================================
    # [PRE-OP] MỞ KHÓA wp-config.php (có thể bị Diamond Vaccine/lần chạy trước khóa 400)
    # WP-CLI cần đọc file này suốt quá trình phẫu thuật
    # ===========================================================
    chmod 644 "$doc_root/wp-config.php" 2>/dev/null

    # ===========================================================
    # [MODULE 0] IMUNIFY360 BRIDGE — Giải trừ blacklist trước phẫu thuật
    # ===========================================================
    imunify360_bridge "$domain" "$doc_root"

    # ===========================================================
    # [MODULE 1] DATABASE FORENSICS — Dọn spam & khóa comment
    # ===========================================================
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        local db_prefix=$(run_wp "$sys_user" "$doc_root" config get table_prefix 2>/dev/null | tr -d '\r')
        db_prefix=$(echo "$db_prefix" | tr -dc 'a-zA-Z0-9_')
        if [[ -z "$db_prefix" ]]; then db_prefix="wp_"; fi

        log_msg "INFO" "-> Khóa & Tiêu diệt Spam Comments/Pingbacks (Prefix: $db_prefix)..."
        run_wp "$sys_user" "$doc_root" db query "UPDATE ${db_prefix}posts SET comment_status = 'closed', ping_status = 'closed';" 2>/dev/null
        run_wp "$sys_user" "$doc_root" db query "DELETE FROM ${db_prefix}comments WHERE comment_approved = 'spam' OR comment_approved = 'trash';" 2>/dev/null
        run_wp "$sys_user" "$doc_root" db query "DELETE FROM ${db_prefix}commentmeta WHERE comment_id NOT IN (SELECT comment_ID FROM ${db_prefix}comments);" 2>/dev/null
    else
        log_msg "WARN" "-> Bỏ qua Database Forensics: WP-CLI chưa cài đặt."
    fi

    # ===========================================================
    # [MODULE 2] NUKE & PAVE — Tái tạo Core Files
    # ===========================================================
    log_msg "INFO" "-> Nuke & Pave (Tái tạo Core Files)..."
    
    local wp_version=""
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        wp_version=$(run_wp "$sys_user" "$doc_root" core version 2>/dev/null | tr -d '\r')
    fi
    if [[ -z "$wp_version" ]]; then
        wp_version=$(grep "\$wp_version =" "$doc_root/wp-includes/version.php" 2>/dev/null | grep -oP "[0-9]+\.[0-9\.]+")
    fi
    log_msg "INFO" "   Phiên bản WP hiện tại: ${wp_version:-không xác định}"
    
    # Backup thư mục cũ (Safe-Nuke)
    local backup_dir_admin="${doc_root}/wp-admin.bak"
    local backup_dir_includes="${doc_root}/wp-includes.bak"
    
    rm -rf "$backup_dir_admin" "$backup_dir_includes"
    if [[ -d "$doc_root/wp-admin" ]]; then mv "$doc_root/wp-admin" "$backup_dir_admin"; fi
    if [[ -d "$doc_root/wp-includes" ]]; then mv "$doc_root/wp-includes" "$backup_dir_includes"; fi
    
    # Strategy 1: WP-CLI core download
    local dl_status=1
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        run_wp "$sys_user" "$doc_root" core download --skip-content --force 2>/dev/null
        dl_status=$?
    fi
    
    # Strategy 2: Fallback tar.gz
    if [[ $dl_status -ne 0 ]] || [[ ! -d "$doc_root/wp-admin" ]] || [[ ! -d "$doc_root/wp-includes" ]]; then
        local tar_url="https://wordpress.org/latest.tar.gz"
        if [[ -n "$wp_version" ]]; then
            tar_url="https://wordpress.org/wordpress-${wp_version}.tar.gz"
        fi
        log_msg "WARN" "-> WP-CLI thất bại. Fallback tar.gz (v${wp_version:-latest})..."
        local tmp_dir=$(mktemp -d)
        curl -sL --connect-timeout 10 -m 60 -o "$tmp_dir/wordpress.tar.gz" "$tar_url" 2>/dev/null
        if [[ ! -s "$tmp_dir/wordpress.tar.gz" && "$tar_url" != *"latest"* ]]; then
            log_msg "WARN" "   Phiên bản $wp_version không tìm thấy, dùng bản mới nhất..."
            curl -sL --connect-timeout 10 -m 60 -o "$tmp_dir/wordpress.tar.gz" https://wordpress.org/latest.tar.gz 2>/dev/null
        fi
        if [[ -s "$tmp_dir/wordpress.tar.gz" ]]; then
            tar -xzf "$tmp_dir/wordpress.tar.gz" -C "$tmp_dir" 2>/dev/null
            if [[ -d "$tmp_dir/wordpress/wp-admin" ]]; then
                cp -rf "$tmp_dir/wordpress/wp-admin" "$doc_root/wp-admin"
                cp -rf "$tmp_dir/wordpress/wp-includes" "$doc_root/wp-includes"
                find "$tmp_dir/wordpress" -maxdepth 1 -type f -exec cp -f {} "$doc_root/" \;
                dl_status=0
                log_msg "OK" "-> Tải thành công Core qua Fallback tar.gz!"
            fi
        fi
        rm -rf "$tmp_dir"
    fi
    
    if [[ $dl_status -eq 0 && -d "$doc_root/wp-admin" && -d "$doc_root/wp-includes" ]]; then
        # Đồng bộ phân quyền
        local doc_root_group=$(stat -c '%G' "$doc_root" 2>/dev/null)
        if [[ -z "$doc_root_group" ]]; then doc_root_group="psacln"; fi
        chown -R "$sys_user:$doc_root_group" "$doc_root/wp-admin" "$doc_root/wp-includes" 2>/dev/null
        chown "$sys_user:$doc_root_group" "$doc_root"/*.php "$doc_root"/*.html "$doc_root"/*.txt 2>/dev/null
        
        # Fix quyền (khắc phục umask 027 của root)
        find "$doc_root/wp-admin" "$doc_root/wp-includes" -type d -exec chmod 755 {} \; 2>/dev/null
        find "$doc_root/wp-admin" "$doc_root/wp-includes" -type f -exec chmod 644 {} \; 2>/dev/null
        # Chmod root PHP files NHƯNG BẢO VỆ wp-config.php (Fix Bug #2)
        for f in "$doc_root"/*.php; do
            local fname=$(basename "$f")
            if [[ "$fname" != "wp-config.php" ]]; then
                chmod 644 "$f" 2>/dev/null
            fi
        done
        chmod 644 "$doc_root"/*.html "$doc_root"/*.txt 2>/dev/null

        rm -rf "$backup_dir_admin" "$backup_dir_includes"
        log_msg "OK" "-> Hoàn tất tái tạo mã nguồn WordPress Core!"
    else
        log_msg "ERROR" "-> Tất cả các chiến lược tải Core đều thất bại. Khôi phục phiên bản trước đó..."
        if [[ -d "$backup_dir_admin" ]]; then mv "$backup_dir_admin" "$doc_root/wp-admin"; fi
        if [[ -d "$backup_dir_includes" ]]; then mv "$backup_dir_includes" "$doc_root/wp-includes"; fi
        local doc_root_group=$(stat -c '%G' "$doc_root" 2>/dev/null)
        if [[ -z "$doc_root_group" ]]; then doc_root_group="psacln"; fi
        chown -R "$sys_user:$doc_root_group" "$doc_root/wp-admin" "$doc_root/wp-includes" 2>/dev/null
        append_json "core_status" "download_failed_rolled_back"
    fi

    # ===========================================================
    # [MODULE 3] DEEP MALWARE KILL (Diamond Vaccine Engine)
    # ===========================================================
    deep_malware_kill "$doc_root"
    
    # ===========================================================
    # [MODULE 4] ROOT DIRECTORY SANITIZATION (Whitelist Mode)
    # ===========================================================
    log_msg "INFO" "-> Quét & Tiêu diệt file rác/mã độc tại Document Root (Whitelist Mode)..."
    
    local wp_root_whitelist="index.php|wp-activate.php|wp-blog-header.php|wp-comments-post.php|wp-config.php|wp-config-sample.php|wp-cron.php|wp-links-opml.php|wp-load.php|wp-login.php|wp-mail.php|wp-settings.php|wp-signup.php|wp-trackback.php|xmlrpc.php|license.txt|readme.html|.htaccess|robots.txt|wp-cli.yml"
    local wp_dir_whitelist="wp-admin|wp-content|wp-includes|.well-known"
    
    local rogue_count=0
    while IFS= read -r rogue_file; do
        local basename_file=$(basename "$rogue_file")
        if ! echo "$basename_file" | grep -qE "^($wp_root_whitelist)$"; then
            rm -f "$rogue_file"
            log_msg "WARN" "   Tiêu diệt file lạ: $basename_file"
            rogue_count=$((rogue_count + 1))
        fi
    done < <(find "$doc_root" -maxdepth 1 -type f 2>/dev/null)
    
    while IFS= read -r rogue_dir; do
        local basename_dir=$(basename "$rogue_dir")
        if ! echo "$basename_dir" | grep -qE "^($wp_dir_whitelist)$"; then
            rm -rf "$rogue_dir"
            log_msg "WARN" "   Tiêu diệt thư mục lạ: $basename_dir/"
            rogue_count=$((rogue_count + 1))
        fi
    done < <(find "$doc_root" -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null)
    
    rm -f "$doc_root/wp-config.php.bak" "$doc_root/wp-config.php.old" "$doc_root/wp-config.php.save" "$doc_root/wp-config.php~" 2>/dev/null
    
    if [[ $rogue_count -gt 0 ]]; then
        log_msg "OK" "   Đã tiêu diệt $rogue_count đối tượng khả nghi tại Document Root."
        append_json "rogue_files_removed" "$rogue_count"
    else
        log_msg "OK" "   Document Root sạch sẽ, không phát hiện file/thư mục lạ."
    fi

    # ===========================================================
    # [MODULE 5] UPLOADS & CACHES CLEANUP
    # ===========================================================
    log_msg "INFO" "-> Càn quét Uploads & Caches..."
    find "$doc_root/wp-content/uploads" -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.py" -o -name "*.pl" -o -name "*.suspected" \) -delete 2>/dev/null
    rm -rf "$doc_root/wp-content/cache" "$doc_root/wp-content/w3tc-config" "$doc_root/wp-content/litespeed" 2>/dev/null

    # Flush rewrite rules
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        run_wp "$sys_user" "$doc_root" rewrite flush --hard 2>/dev/null
    fi

    # ===========================================================
    # [MODULE 6] IAM — Identity & Access Management (Password Rotation)
    # ===========================================================
    log_msg "INFO" "-> Xoay vòng Mật khẩu Hệ thống & Salts (Amnesia Protocol)..."
    
    # 6.1 Xoay Plesk SysUser password (chỉ khi có Plesk)
    if [[ $HAS_PLESK -eq 1 ]]; then
        local new_sys_pass=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
        plesk bin sysuser -u "$sys_user" -passwd "$new_sys_pass" &>/dev/null
    fi
    
    # 6.2 Xoay MySQL Pass & Salts (Multi-platform DB sync)
    local db_user=""
    local db_name=""
    local old_db_pass=""

    if [[ $HAS_WP_CLI -eq 1 ]]; then
        db_user=$(run_wp "$sys_user" "$doc_root" config get DB_USER 2>/dev/null | tr -d '\r')
        db_name=$(run_wp "$sys_user" "$doc_root" config get DB_NAME 2>/dev/null | tr -d '\r')
        old_db_pass=$(run_wp "$sys_user" "$doc_root" config get DB_PASSWORD 2>/dev/null | tr -d '\r')
    else
        # Fallback: parse wp-config.php trực tiếp
        db_user=$(grep "DB_USER" "$doc_root/wp-config.php" 2>/dev/null | grep -oP "(?<=['\"])[^'\"]+(?=['\"])" | tail -1)
        db_name=$(grep "DB_NAME" "$doc_root/wp-config.php" 2>/dev/null | grep -oP "(?<=['\"])[^'\"]+(?=['\"])" | tail -1)
        old_db_pass=$(grep "DB_PASSWORD" "$doc_root/wp-config.php" 2>/dev/null | grep -oP "(?<=['\"])[^'\"]+(?=['\"])" | tail -1)
    fi

    if [[ -n "$db_user" && -n "$db_name" ]]; then
        local new_db_pass=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
        
        # Bước 1: Cập nhật wp-config.php TRƯỚC
        if [[ $HAS_WP_CLI -eq 1 ]]; then
            run_wp "$sys_user" "$doc_root" config set DB_PASSWORD "$new_db_pass" 2>/dev/null
        else
            sed -i "s|define.*DB_PASSWORD.*|define('DB_PASSWORD', '${new_db_pass}');|" "$doc_root/wp-config.php" 2>/dev/null
        fi
        
        # Bước 2: Đồng bộ xuống MySQL (dùng SQL trực tiếp, Fix Bug #3)
        db_password_sync "$db_user" "$new_db_pass" "$db_name"
    fi

    # Shuffle salts
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        run_wp "$sys_user" "$doc_root" config shuffle-salts 2>/dev/null
    fi

    # 6.3 Reset mật khẩu Admin WP & Xử lý Username nhạy cảm
    log_msg "INFO" "-> Cưỡng chế Reset Mật khẩu Quản trị viên WP..."
    if [[ $HAS_WP_CLI -eq 1 ]]; then
        local admins=$(run_wp "$sys_user" "$doc_root" user list --role=administrator --field=user_login 2>/dev/null)
        local brand_name=$(echo "$domain" | cut -d'.' -f1)
        
        for admin_user in $admins; do
            local random_hash=$(head -c 150 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
            run_wp "$sys_user" "$doc_root" user update "$admin_user" --user_pass="$random_hash" 2>/dev/null
            
            # Xử lý Username nhạy cảm (Nuke-and-Reassign)
            if [[ "$admin_user" == "admin" || "$admin_user" == "root" || "$admin_user" == "administrator" || "$admin_user" == "manager" || "$admin_user" == "test" || "$admin_user" == "$brand_name" ]]; then
                log_msg "WARN" "Phát hiện Username nhạy cảm dễ bị Brute-force: $admin_user"
                
                local new_username=""
                if [[ $AUTO_YES -eq 1 ]]; then
                    if [[ -n "$CONFIRM_USERNAME" ]]; then
                        new_username="$CONFIRM_USERNAME"
                    else
                        log_msg "INFO" "Bỏ qua đổi tên do chạy chế độ Headless và thiếu tham số --confirm-username."
                    fi
                else
                    echo -e "${YELLOW}>> ĐỀ XUẤT ĐỔI TÊN ĐỂ TRÁNH BOTNET: Gợi ý: ${brand_name}_admin, qtri_${brand_name}, admin_${brand_name}${NC}"
                    read -p "Nhập Username mới (Hoặc nhấn Enter để bỏ qua): " user_input
                    new_username="$user_input"
                fi
                
                if [[ -n "$new_username" ]]; then
                    log_msg "INFO" "Đang thực thi Nuke-and-Reassign: $admin_user -> $new_username..."
                    local admin_email=$(run_wp "$sys_user" "$doc_root" user get "$admin_user" --field=user_email 2>/dev/null)
                    if [[ -z "$admin_email" ]]; then admin_email="admin@$domain"; fi
                    
                    local safe_pass=$(head -c 150 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
                    run_wp "$sys_user" "$doc_root" user create "$new_username" "$admin_email" --role=administrator --user_pass="$safe_pass" 2>/dev/null
                    
                    local new_user_id=$(run_wp "$sys_user" "$doc_root" user get "$new_username" --field=ID 2>/dev/null | tr -d '\r')
                    if [[ -n "$new_user_id" ]]; then
                        run_wp "$sys_user" "$doc_root" user delete "$admin_user" --reassign="$new_user_id" 2>/dev/null
                        log_msg "OK" "Hoàn tất đổi Username: $admin_user -> $new_username (ID: $new_user_id). Toàn bộ Data được bảo toàn!"
                    else
                        log_msg "ERROR" "Không thể truy xuất ID của user mới '$new_username'. Bỏ qua xóa user cũ để bảo toàn dữ liệu."
                    fi
                fi
            fi
        done
    fi

    # ===========================================================
    # [MODULE 7] IMUNIFY360 RESTORE — Gỡ ignore tạm, trả lại bảo vệ
    # ===========================================================
    imunify360_restore "$doc_root"

    # ===========================================================
    # [MODULE 8] POST-OP HEALTHCHECK — Kiểm tra website sống
    # Chạy TRƯỚC khi khóa wp-config.php để rollback vẫn hoạt động
    # ===========================================================
    post_op_healthcheck "$domain" "$old_db_pass" "$db_user" "$doc_root" "$sys_user"

    # ===========================================================
    # [MODULE 9] HARDENING — Đóng băng bảo mật (Fix Bug #2)
    # Chạy SAU CÙNG để không ảnh hưởng WP-CLI và rollback
    # ===========================================================
    log_msg "INFO" "-> Đóng băng bảo mật (Diamond Hardening)..."
    chmod 400 "$doc_root/wp-config.php" 2>/dev/null
    local doc_root_group_final=$(stat -c '%G' "$doc_root" 2>/dev/null)
    chown "$sys_user:${doc_root_group_final:-psacln}" "$doc_root/wp-config.php" 2>/dev/null
    log_msg "OK" "   wp-config.php → chmod 400 (Khóa cứng credentials)"

    log_msg "OK" "Hoàn tất làm sạch & Đóng băng $domain!"
    append_json "actions_$domain" "success"
}

# --- MAIN EXECUTION ---
bootstrap

if [[ $MASS_SCAN -eq 1 ]]; then
    log_msg "STEP" "BẮT ĐẦU CHẾ ĐỘ QUÉT RẢI THẢM (MASS QUARANTINE)"
    domains=$(list_all_wp_domains)
    for dom in $domains; do
        process_domain "$dom"
    done
else
    process_domain "$TARGET_DOMAIN"
fi

log_msg "STEP" "Chu trình hoàn tất."
print_final_json
exit 0
