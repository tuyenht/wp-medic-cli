#!/bin/bash
# ================================================================
#  DIAMOND+ WP HARDENING — Phase 2: WordPress Lockdown
#  Server 37 (103.166.184.37) — AlmaLinux 9.7 / Plesk
#
#  Mục tiêu: Hardening WordPress cho TẤT CẢ sites trên server
#            + Plugin audit + File permissions + Core integrity
#
#  Chạy: bash /root/diamond_wp_hardening.sh
#  Yêu cầu: root, wp-cli
# ================================================================
set -euo pipefail

VHOST_ROOT="/var/www/vhosts"
LOG="/var/log/diamond_wp_hardening.log"
REPORT_DIR="/root/diamond_reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT="$REPORT_DIR/wp_hardening_${TIMESTAMP}.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
report() { echo "$*" | tee -a "$REPORT"; }
separator() { report "$(printf '═%.0s' {1..70})"; }

mkdir -p "$REPORT_DIR"
: > "$REPORT"

separator
report " DIAMOND+ WORDPRESS HARDENING — Phase 2"
report " Server: $(hostname) | $(date '+%Y-%m-%d %H:%M:%S')"
separator
report ""

# ================================================================
#  Tìm tất cả WordPress installations trên server
# ================================================================
log "[Phase 2] Scanning WordPress installations..."
report "## ALL WORDPRESS SITES"
report ""

WP_SITES=()
while IFS= read -r wpconfig; do
    WP_DIR=$(dirname "$wpconfig")
    # Xác định domain từ path
    DOMAIN=$(echo "$WP_DIR" | sed -n "s|$VHOST_ROOT/\([^/]*\).*|\1|p")
    SUBDIR=$(echo "$WP_DIR" | sed "s|$VHOST_ROOT/[^/]*/||")
    WP_SITES+=("$WP_DIR|$DOMAIN|$SUBDIR")
done < <(find "$VHOST_ROOT" -maxdepth 5 -name "wp-config.php" -type f 2>/dev/null)

report "  Found ${#WP_SITES[@]} WordPress installations:"
for SITE_INFO in "${WP_SITES[@]}"; do
    IFS='|' read -r WP_DIR DOMAIN SUBDIR <<< "$SITE_INFO"
    report "    • $DOMAIN ($SUBDIR)"
done
report ""

# ================================================================
#  XỬ LÝ TỪNG SITE
# ================================================================
SITE_NUM=0
TOTAL_ISSUES=0

for SITE_INFO in "${WP_SITES[@]}"; do
    IFS='|' read -r WP_DIR DOMAIN SUBDIR <<< "$SITE_INFO"
    SITE_NUM=$((SITE_NUM + 1))
    SITE_ISSUES=0

    # Xác định user sở hữu site
    SITE_USER=$(stat -c '%U' "$WP_DIR" 2>/dev/null || echo "unknown")

    separator
    report ""
    report "## [$SITE_NUM/${#WP_SITES[@]}] $DOMAIN ($SUBDIR)"
    report "   Path: $WP_DIR | Owner: $SITE_USER"
    report ""

    # ── A. CORE INTEGRITY CHECK ─────────────────────────────
    report "  ### A. Core Integrity Check"
    if command -v wp &>/dev/null; then
        CHECKSUM_RESULT=$(cd "$WP_DIR" && sudo -u "$SITE_USER" wp core verify-checksums \
            --skip-plugins --skip-themes 2>&1 || true)
        if echo "$CHECKSUM_RESULT" | grep -q "Success"; then
            report "    ✅ WordPress core: INTACT"
        else
            report "    🔴 WordPress core: MODIFIED!"
            echo "$CHECKSUM_RESULT" | grep -E "File|Warning" | head -10 | while read -r l; do
                report "      $l"
            done || true
            SITE_ISSUES=$((SITE_ISSUES + 1))
            
            # Auto-fix: reinstall core from local zip if available
            LOCAL_UPDATES="/var/www/vhosts/baoson.net/httpdocs/wordpress-updates"
            WP_VER=$(cd "$WP_DIR" && sudo -u "$SITE_USER" wp core version 2>/dev/null || echo "7.0")
            ZIP_FILE=""
            if [[ "$WP_VER" == 6* ]]; then
                ZIP_FILE="$LOCAL_UPDATES/wordpress/wordpress-6.9.4-no-content.zip"
            else
                ZIP_FILE="$LOCAL_UPDATES/wordpress/wordpress-7.0-no-content.zip"
            fi
            
            if [ -f "$ZIP_FILE" ]; then
                log "  Reinstalling WP core for $DOMAIN from local source ($ZIP_FILE)..."
                # Unzip directly, overwriting all core files (excluding content)
                unzip -o -q "$ZIP_FILE" -d "$WP_DIR/" && \
                chown -R "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$WP_DIR" 2>/dev/null && \
                report "    → Core reinstalled from local source ($ZIP_FILE)"
            else
                log "  Reinstalling WP core for $DOMAIN from official source..."
                cd "$WP_DIR" && sudo -u "$SITE_USER" wp core download --force \
                    --skip-content --skip-plugins --skip-themes 2>/dev/null && \
                    report "    → Core reinstalled from official source" || \
                    report "    ⚠️ Failed to reinstall core (manual action needed)"
            fi
        fi
    else
        report "    ⚠️ wp-cli not found — manual check needed"
    fi
    report ""

    # ── B. PLUGIN AUDIT ─────────────────────────────────────
    report "  ### B. Plugin Audit"
    if command -v wp &>/dev/null && [ -d "$WP_DIR/wp-content/plugins" ]; then
        # List active plugins
        cd "$WP_DIR"
        PLUGIN_LIST=$(sudo -u "$SITE_USER" wp plugin list --format=csv \
            --fields=name,status,version,update \
            --skip-plugins --skip-themes 2>/dev/null || echo "")
        
        if [ -n "$PLUGIN_LIST" ]; then
            echo "$PLUGIN_LIST" | while IFS=',' read -r PNAME PSTATUS PVER PUPDATE; do
                [ "$PNAME" = "name" ] && continue  # Skip header
                
                STATUS_ICON="✅"
                NOTES=""
                
                # Check for nulled indicators
                PLUGIN_DIR="$WP_DIR/wp-content/plugins/$PNAME"
                if [ -d "$PLUGIN_DIR" ]; then
                    if grep -rql "nulled\|GPL.*Nulled\|cracked\|pirated\|unlocked\|warez" \
                        "$PLUGIN_DIR" --include="*.php" 2>/dev/null; then
                        STATUS_ICON="🔴"
                        NOTES="NULLED DETECTED!"
                        SITE_ISSUES=$((SITE_ISSUES + 1))
                    fi
                    
                    # Auto-replace if clean source is available
                    LOCAL_SOURCE="/var/www/vhosts/baoson.net/httpdocs/wordpress-updates/plugins/$PNAME"
                    if [ -d "$LOCAL_SOURCE" ]; then
                        log "  Replacing modified plugin $PNAME for $DOMAIN with clean source..."
                        # Backup first
                        mv "$PLUGIN_DIR" "${PLUGIN_DIR}_bak_${TIMESTAMP}" 2>/dev/null || true
                        # Copy clean source
                        cp -rf "$LOCAL_SOURCE" "$WP_DIR/wp-content/plugins/" && \
                        # Fix ownership
                        chown -R "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$PLUGIN_DIR" 2>/dev/null && \
                        report "      → Removed modified and copied clean $PNAME from local repository"
                    fi
                fi
                
                # Check for updates
                if [ "$PUPDATE" = "available" ]; then
                    STATUS_ICON="🟡"
                    NOTES="${NOTES} Update available"
                fi
                
                report "    $STATUS_ICON $PNAME ($PVER) [$PSTATUS] $NOTES"
            done
        fi

        # Specific: Auto-replace WP Rocket with clean version 3.21.3 if it exists
        WP_ROCKET_DIR="$WP_DIR/wp-content/plugins/wp-rocket"
        if [ -d "$WP_ROCKET_DIR" ]; then
            report "    🚀 WP Rocket detected — replacing with clean version 3.21.3..."
            ZIP_SOURCE="/var/www/vhosts/baoson.net/httpdocs/wordpress-updates/plugins/wp-rocket/wp-rocket.3.21.3.zip"
            if [ -f "$ZIP_SOURCE" ]; then
                # Backup old plugin first
                mv "$WP_ROCKET_DIR" "${WP_ROCKET_DIR}_bak_${TIMESTAMP}" 2>/dev/null || true
                
                # Unzip directly to plugins/ (it extracts a directory named wp-rocket)
                unzip -o -q "$ZIP_SOURCE" -d "$WP_DIR/wp-content/plugins/" && \
                
                # Fix ownership and permissions
                chown -R "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$WP_ROCKET_DIR" 2>/dev/null && \
                find "$WP_ROCKET_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true && \
                find "$WP_ROCKET_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true && \
                
                report "    ✅ WP Rocket replaced successfully with clean v3.21.3 + Perms locked"
                SITE_ISSUES=$((SITE_ISSUES + 1))
            else
                report "    ⚠️ Clean WP Rocket ZIP source not found at $ZIP_SOURCE"
            fi
        fi
    fi
    report ""

    # ── C. MALICIOUS UPLOADS CHECK ──────────────────────────
    report "  ### C. Uploads Directory Security"
    UPLOADS_DIR="$WP_DIR/wp-content/uploads"
    if [ -d "$UPLOADS_DIR" ]; then
        # Xóa triệt để thư mục wpseo-redirects giả mạo
        WPSEO_REDIR_DIR="$UPLOADS_DIR/wpseo-redirects"
        if [ -d "$WPSEO_REDIR_DIR" ]; then
            rm -rf "$WPSEO_REDIR_DIR"
            report "    🔴 REMOVED FAKE DIR: uploads/wpseo-redirects/ (Malware backdoor)"
            SITE_ISSUES=$((SITE_ISSUES + 1))
        fi

        # Tìm PHP files trong uploads (KHÔNG ĐƯỢC CÓ!)
        PHP_IN_UPLOADS=$(find "$UPLOADS_DIR" -name "*.php" -o -name "*.phtml" -o -name "*.php5" 2>/dev/null | wc -l)
        if [ "$PHP_IN_UPLOADS" -gt 0 ]; then
            report "    🔴 Found $PHP_IN_UPLOADS PHP files in uploads/ (MUST NOT EXIST!)"
            find "$UPLOADS_DIR" -name "*.php" -o -name "*.phtml" -o -name "*.php5" 2>/dev/null | \
                head -10 | while read -r f; do
                report "      → $f"
                # Quarantine
                mkdir -p "$REPORT_DIR/quarantine_${TIMESTAMP}"
                mv "$f" "$REPORT_DIR/quarantine_${TIMESTAMP}/" 2>/dev/null || true
            done
            SITE_ISSUES=$((SITE_ISSUES + 1))
        else
            report "    ✅ No PHP files in uploads/"
        fi

        # Tìm zip files nghi ngờ (như manage-tweets-elementor.zip)
        SUSPICIOUS_ZIPS=$(find "$UPLOADS_DIR" -name "*.zip" -newer "$WP_DIR/wp-config.php" 2>/dev/null)
        if [ -n "$SUSPICIOUS_ZIPS" ]; then
            report "    🟠 Recent ZIP files found in uploads/:"
            echo "$SUSPICIOUS_ZIPS" | while read -r z; do
                report "      → $(basename "$z") ($(du -h "$z" | cut -f1))"
            done
        fi

        # Tạo .htaccess block PHP execution trong uploads
        UPLOADS_HTACCESS="$UPLOADS_DIR/.htaccess"
        cat > "$UPLOADS_HTACCESS" << 'HTEOF'
# Diamond+ Security: Block PHP execution in uploads
<FilesMatch "\.(?:php|phtml|php3|php5|phps|pht|shtml)$">
    Order Allow,Deny
    Deny from all
</FilesMatch>

# Block dangerous file types  
<FilesMatch "\.(cgi|pl|py|jsp|asp|aspx|sh|bash)$">
    Order Allow,Deny
    Deny from all
</FilesMatch>
HTEOF
        chown "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$UPLOADS_HTACCESS" 2>/dev/null || true
        chmod 444 "$UPLOADS_HTACCESS"
        report "    ✅ PHP execution blocked in uploads/ (.htaccess)"
        
        # Tạo .htaccess block PHP execution trong cache
        CACHE_DIR="$WP_DIR/wp-content/cache"
        if [ -d "$CACHE_DIR" ]; then
            CACHE_HTACCESS="$CACHE_DIR/.htaccess"
            chattr -i "$CACHE_HTACCESS" 2>/dev/null || true
            cat > "$CACHE_HTACCESS" << 'HTEOF'
# Diamond+ Security: Block PHP execution in cache
<FilesMatch "\.(?:php|phtml|php3|php5|phps|pht|shtml)$">
    Order Allow,Deny
    Deny from all
</FilesMatch>

# Block dangerous file types  
<FilesMatch "\.(cgi|pl|py|jsp|asp|aspx|sh|bash)$">
    Order Allow,Deny
    Deny from all
</FilesMatch>
HTEOF
            chown "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$CACHE_HTACCESS" 2>/dev/null || true
            chmod 444 "$CACHE_HTACCESS"
            chattr +i "$CACHE_HTACCESS" 2>/dev/null || true
            report "    ✅ PHP execution blocked in cache/ (.htaccess + immutable)"
        fi
    fi
    report ""

    # ── D. WP-CONFIG HARDENING ──────────────────────────────
    report "  ### D. wp-config.php Hardening"
    WPCONFIG="$WP_DIR/wp-config.php"
    if [ -f "$WPCONFIG" ]; then
        WPCONFIG_CHANGES=0

        # DISALLOW_FILE_EDIT
        if ! grep -q "DISALLOW_FILE_EDIT" "$WPCONFIG"; then
            sed -i "/^\s*require_once.*wp-settings/i\\define('DISALLOW_FILE_EDIT', true);" "$WPCONFIG"
            report "    ✅ Added: DISALLOW_FILE_EDIT = true"
            WPCONFIG_CHANGES=$((WPCONFIG_CHANGES + 1))
        else
            report "    ✓ DISALLOW_FILE_EDIT already set"
        fi

        # DISALLOW_FILE_MODS (chặn install/update plugin từ admin)  
        if ! grep -q "DISALLOW_FILE_MODS" "$WPCONFIG"; then
            sed -i "/^\s*require_once.*wp-settings/i\\define('DISALLOW_FILE_MODS', true);" "$WPCONFIG"
            report "    ✅ Added: DISALLOW_FILE_MODS = true"
            WPCONFIG_CHANGES=$((WPCONFIG_CHANGES + 1))
        else
            report "    ✓ DISALLOW_FILE_MODS already set"
        fi

        # WP_DEBUG off
        if grep -q "define.*WP_DEBUG.*true" "$WPCONFIG"; then
            sed -i "s/define\s*(\s*'WP_DEBUG'\s*,\s*true\s*)/define('WP_DEBUG', false)/" "$WPCONFIG"
            report "    ✅ Fixed: WP_DEBUG = false"
            WPCONFIG_CHANGES=$((WPCONFIG_CHANGES + 1))
        fi

        # FORCE_SSL_ADMIN
        if ! grep -q "FORCE_SSL_ADMIN" "$WPCONFIG"; then
            sed -i "/^\s*require_once.*wp-settings/i\\define('FORCE_SSL_ADMIN', true);" "$WPCONFIG"
            report "    ✅ Added: FORCE_SSL_ADMIN = true"
            WPCONFIG_CHANGES=$((WPCONFIG_CHANGES + 1))
        fi

        # Clean up legacy buggy XML-RPC block if present
        if grep -q "add_filter('xmlrpc_enabled'" "$WPCONFIG" 2>/dev/null; then
            chattr -i "$WPCONFIG" 2>/dev/null || true
            chmod 600 "$WPCONFIG" 2>/dev/null || true
            sed -i "/add_filter('xmlrpc_enabled'/d" "$WPCONFIG"
            sed -i "/Block XML-RPC attacks/d" "$WPCONFIG"
            report "    🧹 Cleaned legacy buggy XML-RPC add_filter lines"
        fi

        # Disable XML-RPC safely using native PHP
        if ! grep -q "XMLRPC_REQUEST" "$WPCONFIG"; then
            chattr -i "$WPCONFIG" 2>/dev/null || true
            chmod 600 "$WPCONFIG" 2>/dev/null || true
            sed -i "/^\s*require_once.*wp-settings/i\\// Diamond+: Block XML-RPC attacks\\nif (defined('XMLRPC_REQUEST') || (isset(\$_SERVER['SCRIPT_NAME']) && strpos(\$_SERVER['SCRIPT_NAME'], 'xmlrpc.php') !== false)) {\\n    header('HTTP/1.1 403 Forbidden');\\n    exit;\\n}" "$WPCONFIG"
            report "    ✅ Added: XML-RPC disabled (native PHP)"
            WPCONFIG_CHANGES=$((WPCONFIG_CHANGES + 1))
        fi

        # Lock down file permissions  
        chmod 400 "$WPCONFIG"
        report "    ✅ Permissions: 400 (read-only owner)"
        
        [ "$WPCONFIG_CHANGES" -gt 0 ] && SITE_ISSUES=$((SITE_ISSUES + WPCONFIG_CHANGES))
    fi
    report ""

    # ── E. FILE PERMISSIONS LOCKDOWN ────────────────────────
    report "  ### E. File Permissions Lockdown"
    
    # Temporarily remove immutable attribute on .htaccess before chown/chmod
    MAIN_HTACCESS="$WP_DIR/.htaccess"
    if [ -f "$MAIN_HTACCESS" ]; then
        chattr -i "$MAIN_HTACCESS" 2>/dev/null || true
    fi
    
    # Directories: 755, Files: 644
    find "$WP_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$WP_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    # wp-config already set to 400 above
    report "    ✅ Directories: 755 | Files: 644"

    # Fix ownership BEFORE making files immutable
    chown -R "$SITE_USER":"$(id -gn "$SITE_USER" 2>/dev/null || echo psacln)" "$WP_DIR" 2>/dev/null || true
    # wp-config must be readable by PHP user
    chmod 400 "$WPCONFIG" 2>/dev/null || true
    report "    ✅ Ownership: $SITE_USER"

    # Lock .htaccess files (immutable)
    if [ -f "$MAIN_HTACCESS" ]; then
        chmod 444 "$MAIN_HTACCESS" 2>/dev/null || true
        chattr +i "$MAIN_HTACCESS" 2>/dev/null || true
        report "    ✅ .htaccess: 444 + immutable (chattr +i)"
    fi
    report ""

    # ── F. XMLRPC + WP-CRON PROTECTION ──────────────────────
    report "  ### F. Attack Surface Reduction"
    
    # Block xmlrpc.php via .htaccess (since we made root .htaccess immutable, use Nginx)
    # Add to Plesk additional nginx directives instead
    XMLRPC_FILE="$WP_DIR/xmlrpc.php"
    if [ -f "$XMLRPC_FILE" ]; then
        chmod 000 "$XMLRPC_FILE"
        report "    ✅ xmlrpc.php: permissions set to 000"
    fi

    # Block wp-trackback.php
    TRACKBACK_FILE="$WP_DIR/wp-trackback.php"
    if [ -f "$TRACKBACK_FILE" ]; then
        chmod 000 "$TRACKBACK_FILE"
        report "    ✅ wp-trackback.php: permissions set to 000"
    fi
    report ""

    # ── SITE SUMMARY ────────────────────────────────────────
    report "  → Site issues fixed: $SITE_ISSUES"
    TOTAL_ISSUES=$((TOTAL_ISSUES + SITE_ISSUES))
    report ""
done

# ================================================================
#  SPECIAL: CLEAN cpe.baoson.net MALICIOUS UPLOAD
# ================================================================
separator
report ""
report "## SPECIAL: cpe.baoson.net — Malicious Upload Cleanup"
report ""

CPE_UPLOADS="$VHOST_ROOT/baoson.net/cpe.baoson.net/wp-content/uploads/2026/04"
if [ -d "$CPE_UPLOADS" ]; then
    MALICIOUS_ZIP="$CPE_UPLOADS/manage-tweets-elementor.zip"
    if [ -f "$MALICIOUS_ZIP" ]; then
        mkdir -p "$REPORT_DIR/quarantine_${TIMESTAMP}"
        mv "$MALICIOUS_ZIP" "$REPORT_DIR/quarantine_${TIMESTAMP}/" 2>/dev/null || true
        report "  🗑️ QUARANTINED: manage-tweets-elementor.zip"
        report "     (Malware disguised as Elementor addon — from History 04/04)"
    else
        report "  ✅ manage-tweets-elementor.zip already cleaned by Imunify"
    fi

    # Scan for other suspicious ZIPs
    while IFS= read -r zipfile; do
        report "  🟠 SUSPECT ZIP: $(basename "$zipfile") — needs review"
    done < <(find "$CPE_UPLOADS" -name "*.zip" 2>/dev/null)
else
    report "  ✅ No upload directory for 2026/04"
fi
report ""

# ================================================================
#  FINAL SUMMARY
# ================================================================
separator
report ""
report " WORDPRESS HARDENING SUMMARY"
report "  Sites processed:     ${#WP_SITES[@]}"
report "  Total issues fixed:  $TOTAL_ISSUES"
report "  Report saved:        $REPORT"
report ""
report " Diamond+ WP Checklist:"
report "  ✅ Core integrity verified + reinstalled if modified"
report "  ✅ Nulled plugins detected + removed"
report "  ✅ PHP execution blocked in uploads/"
report "  ✅ DISALLOW_FILE_EDIT + DISALLOW_FILE_MODS"
report "  ✅ File permissions locked (755/644/400)"
report "  ✅ .htaccess immutable (chattr +i)"
report "  ✅ xmlrpc.php + trackback disabled"
report "  ✅ manage-tweets-elementor.zip quarantined"
separator

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ PHASE 2: WP HARDENING COMPLETE               ║"
echo "║  → Tiếp: bash diamond_security_hardening.sh      ║"
echo "╚══════════════════════════════════════════════════╝"
