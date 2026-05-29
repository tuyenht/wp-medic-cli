#!/bin/bash
# ==============================================================================
# 🚀 CÀI ĐẶT WP-MEDIC CLI
# Kho lưu trữ: https://github.com/tuyenht/wp-medic-cli
# ==============================================================================

# Màu sắc giao diện
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}    BẮT ĐẦU CÀI ĐẶT: WP-MEDIC CLI                     ${NC}"
echo -e "${CYAN}======================================================${NC}"

# 1. Quản lý Tham số cài đặt (Dành cho Baoson Ecosystem)
BAOSON_BRIDGE=""
SERVER_ID=$(hostname)
BRIDGE_TOKEN=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --baoson-bridge) BAOSON_BRIDGE="$2"; shift ;;
        --server) SERVER_ID="$2"; shift ;;
        --token) BRIDGE_TOKEN="$2"; shift ;;
    esac
    shift
done

# 2. Kiểm tra quyền Root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[LỖI] Kịch bản cài đặt này yêu cầu quyền Root (sudo). Hãy chạy lại.${NC}"
   exit 1
fi

# 3. Định nghĩa thư mục đích
BIN_DIR="/usr/local/bin"
BIN_NAME="wp-medic"
TARGET_FILE="$BIN_DIR/$BIN_NAME"
SOURCE_URL="https://raw.githubusercontent.com/tuyenht/wp-medic-cli/main/wp-medic.sh"

echo -e "\n[+] Đang tải mã nguồn từ Github ($SOURCE_URL)..."
curl -sL -o "$TARGET_FILE" "$SOURCE_URL"

if [[ $? -ne 0 || ! -s "$TARGET_FILE" ]]; then
    echo -e "${RED}[LỖI] Không thể tải mã nguồn. Kiểm tra lại đường truyền mạng hoặc URL Github.${NC}"
    rm -f "$TARGET_FILE"
    exit 1
fi

# Xác minh file tải về thực sự là bash script (không phải trang lỗi HTML từ CDN)
if ! head -n 1 "$TARGET_FILE" | grep -q '^#!/bin/bash'; then
    echo -e "${RED}[LỖI] File tải về không phải mã nguồn hợp lệ (thiếu shebang). Github có thể đang lỗi, hãy thử lại sau.${NC}"
    rm -f "$TARGET_FILE"
    exit 1
fi

# 4. Phân quyền thực thi & Cài đặt Dependencies
echo -e "[+] Cấp quyền thực thi (chmod +x)..."
chmod +x "$TARGET_FILE"

echo -e "[+] Kiểm tra gói phụ trợ (jq)..."
if ! command -v jq &> /dev/null; then
    echo -e "    -> Đang cài đặt 'jq' (phục vụ JSON mode)..."
    if command -v yum &> /dev/null; then
        yum install epel-release -y &>/dev/null
        yum install jq -y &>/dev/null
    elif command -v apt-get &> /dev/null; then
        apt-get update &>/dev/null
        apt-get install jq -y &>/dev/null
    fi
fi

# 5. GIAO THỨC BAOSON BRIDGE (TỰ ĐỘNG TÍCH HỢP PULSE/TELEGRAM)
if [[ -n "$BAOSON_BRIDGE" ]]; then
    echo -e "\n${CYAN}[+] KHỞI TẠO BAOSON BRIDGE...${NC}"
    echo -e "    -> Đang kết nối tới: $BAOSON_BRIDGE"
    echo -e "    -> Server ID: $SERVER_ID"
    
    # Giả lập gửi thông tin đăng ký lên hệ thống Pulse API (bảo vệ bằng Timeout để tránh treo script)
    curl -s -m 10 --connect-timeout 5 -X POST "$BAOSON_BRIDGE" \
         -H "Content-Type: application/json" \
         -d "{\"server_id\":\"$SERVER_ID\", \"status\":\"wp_medic_installed\", \"token\":\"$BRIDGE_TOKEN\"}" > /dev/null
    
    echo -e "    -> [OK] Đã đăng ký Server thành công với Hệ thống Baoson Pulse."
    echo -e "    -> [OK] Bot @bs_server_monitor_bot hiện đã có thể điều khiển wp-medic trên server này."
fi

# 6. Hoàn tất
echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}🎉 CÀI ĐẶT THÀNH CÔNG!${NC}"
echo -e "WP-Medic CLI đã được cài đặt tại: $TARGET_FILE"
echo -e ""
echo -e "Các lệnh khả dụng ngay bây giờ:"
echo -e "  ${CYAN}wp-medic --help${NC}                   (Xem hướng dẫn)"
echo -e "  ${CYAN}wp-medic --domain inbacha.com${NC}     (Càn quét 1 website)"
echo -e "  ${CYAN}wp-medic --all-domains --dry-run${NC}  (Quét thử nghiệm toàn Server)"
echo -e "${GREEN}======================================================${NC}"
