#!/usr/bin/env bash

# =================================================================
#  Project: GoogleToThisCountry (GTTC)
#  Description: Google 地理位置重定向與多國定位維護工具
#  Supported OS: Alpine (LXC/Docker), Debian, Ubuntu, CentOS
# =================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_DIR="/etc/gttc"
STATUS_FILE="${CONFIG_DIR}/current_country"
PING_SCRIPT="/usr/local/bin/gttc-ping.sh"
SERVICE_NAME="gttc-ping"

mkdir -p "$CONFIG_DIR"

# -----------------------------------------------------------------
# 系統環境檢測與套件安裝
# -----------------------------------------------------------------
check_sys() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}無法識別目前系統作業環境，程式終止。${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}[+] 正在檢查並補充系統基礎依賴套件...${NC}"
    if [ "$OS" = "alpine" ]; then
        # Alpine LXC 邊緣套件庫修正
        if ! grep -q "community" /etc/apk/repositories; then
            echo "http://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)/community" >> /etc/apk/repositories
        fi
        apk update >/dev/null 2>&1
        apk add --no-progress bash curl openrc ca-certificates jq >/dev/null 2>&1
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl bash systemctl ca-certificates jq >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl bash ca-certificates jq >/dev/null 2>&1
    fi
}

check_swap() {
    # 針對小記憶體容器 (LXC) 建立臨時 SWAP 避免 OOM 崩潰
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    
    if [ "$MEM_TOTAL" -lt 512 ] && [ "$SWAP_TOTAL" -eq 0 ]; then
        echo -e "${YELLOW}[!] 檢測到記憶體低於 512MB 且未配置 SWAP，正在建立 512MB 緊急 SWAP...${NC}"
        if [ "$OS" != "alpine" ]; then
            fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 >/dev/null 2>&1
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile 2>/dev/null || true
        fi
    fi
}

# -----------------------------------------------------------------
# 國家參數配置矩陣
# -----------------------------------------------------------------
get_country_config() {
    case "$1" in
        "TW")
            C_NAME="台灣 🇹🇼"
            C_DOMAIN="google.com.tw"
            C_ECS="61.216.0.0/16"
            C_LANG="zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7"
            C_DOH="https://dns.google/dns-query"
            ;;
        "CN")
            C_NAME="中國大陸 🇨🇳"
            C_DOMAIN="google.com"
            C_ECS="114.240.0.0/16"
            C_LANG="zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7"
            C_DOH="https://dns.alidns.com/dns-query"
            ;;
        "JP")
            C_NAME="日本 🇯🇵"
            C_DOMAIN="google.co.jp"
            C_ECS="133.242.0.0/16"
            C_LANG="ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7"
            C_DOH="https://dns.google/dns-query"
            ;;
        "MO")
            C_NAME="澳門 🇲🇴"
            C_DOMAIN="google.com.mo"
            C_ECS="202.175.0.0/16"
            C_LANG="zh-MO,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7"
            C_DOH="https://dns.google/dns-query"
            ;;
        *)
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------
# 服務狀態檢查
# -----------------------------------------------------------------
get_status() {
    if [ -f "$STATUS_FILE" ]; then
        CODE=$(cat "$STATUS_FILE")
        get_country_config "$CODE"
        echo -e "${GREEN}[已開啟 - ${C_NAME}]${NC}"
    else
        echo -e "${RED}[已關閉]${NC}"
    fi
}

# -----------------------------------------------------------------
# 動態背景保活發包腳本構建
# -----------------------------------------------------------------
create_ping_script() {
    cat << EOF > "$PING_SCRIPT"
#!/usr/bin/env bash
# GTTC (GoogleToThisCountry) Background Keeper

TARGET_DOMAIN="${C_DOMAIN}"
ECS_SUBNET="${C_ECS}"
ACCEPT_LANG="${C_LANG}"
DOH_URL="${C_DOH}"

UA_LIST=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
)

while true; do
    RANDOM_UA=\${UA_LIST[\$RANDOM % \${#UA_LIST[@]}]}
    
    # 1. EDNS Client Subnet 域名解析發包
    curl -s -H "accept: application/dns-json" \
         "\${DOH_URL}?name=\${TARGET_DOMAIN}&type=A&edns_client_subnet=\${ECS_SUBNET}" >/dev/null 2>&1

    # 2. 模擬真實地理用戶 HTTP 請求
    curl -s -L -A "\${RANDOM_UA}" \
         -H "Accept-Language: \${ACCEPT_LANG}" \
         "https://\${TARGET_DOMAIN}/generate_204" >/dev/null 2>&1

    # 3. 隨機間隔 45-90 秒，避免頻率異常
    SLEEP_TIME=\$((RANDOM % 46 + 45))
    sleep \$SLEEP_TIME
done
EOF
    chmod +x "$PING_SCRIPT"
}

# -----------------------------------------------------------------
# 守護進程服務註冊 (Systemd / OpenRC)
# -----------------------------------------------------------------
setup_service() {
    if command -v systemctl >/dev/null 2>&1; then
        cat << EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=GoogleToThisCountry Keep-Alive Service
After=network.target

[Service]
Type=simple
ExecStart=${PING_SCRIPT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
        systemctl restart ${SERVICE_NAME} >/dev/null 2>&1
    elif [ -f /etc/rc.conf ] || [ -d /etc/init.d ]; then
        cat << EOF > /etc/init.d/${SERVICE_NAME}
#!/sbin/openrc-run

name="GTTC Keep-Alive Service"
command="${PING_SCRIPT}"
command_background=true
pidfile="/run/${SERVICE_NAME}.pid"

depend() {
    need net
}
EOF
        chmod +x /etc/init.d/${SERVICE_NAME}
        rc-update add ${SERVICE_NAME} default >/dev/null 2>&1
        rc-service ${SERVICE_NAME} restart >/dev/null 2>&1
    else
        # 降級備用方案：nohup 背景執行
        pkill -f "$PING_SCRIPT" >/dev/null 2>&1 || true
        nohup "$PING_SCRIPT" >/dev/null 2>&1 &
    fi
}

stop_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop ${SERVICE_NAME} >/dev/null 2>&1 || true
        systemctl disable ${SERVICE_NAME} >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reload >/dev/null 2>&1
    elif [ -f /etc/init.d/${SERVICE_NAME} ]; then
        rc-service ${SERVICE_NAME} stop >/dev/null 2>&1 || true
        rc-update del ${SERVICE_NAME} default >/dev/null 2>&1 || true
        rm -f /etc/init.d/${SERVICE_NAME}
    fi
    pkill -f "$PING_SCRIPT" >/dev/null 2>&1 || true
    rm -f "$PING_SCRIPT" "$STATUS_FILE"
}

# -----------------------------------------------------------------
# 快捷指令設置
# -----------------------------------------------------------------
setup_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ ! -f /usr/local/bin/gttc ]; then
        ln -sf "$SCRIPT_PATH" /usr/local/bin/gttc 2>/dev/null || true
        chmod +x /usr/local/bin/gttc 2>/dev/null || true
    fi
    if [ ! -f /usr/local/bin/sz ]; then
        ln -sf "$SCRIPT_PATH" /usr/local/bin/sz 2>/dev/null || true
        chmod +x /usr/local/bin/sz 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------
# 操作選單與邏輯
# -----------------------------------------------------------------
enable_mode() {
    echo -e "\n${CYAN}=================================================${NC}"
    echo -e "       ${YELLOW}請選擇目標定位國家 / 地區${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 1. 🇹🇼 台灣 (Taiwan)"
    echo -e " 2. 🇨🇳 中國大陸 (China)"
    echo -e " 3. 🇯🇵 日本 (Japan)"
    echo -e " 4. 🇲🇴 澳門 (Macau)"
    echo -e " 0. 返回主選單"
    echo -e "${CYAN}=================================================${NC}"
    read -p "請輸入選項 [0-4]: " COUNTRY_OPT

    case "$COUNTRY_OPT" in
        1) TARGET_CODE="TW" ;;
        2) TARGET_CODE="CN" ;;
        3) TARGET_CODE="JP" ;;
        4) TARGET_CODE="MO" ;;
        0) return ;;
        *) echo -e "${RED}無效選項！${NC}"; sleep 1; return ;;
    esac

    get_country_config "$TARGET_CODE"
    echo -e "\n${YELLOW}[+] 正在配置並啟動 [${C_NAME}] 定位維護服務...${NC}"
    
    create_ping_script
    setup_service
    echo "$TARGET_CODE" > "$STATUS_FILE"

    echo -e "${GREEN}[✔] 成功啟用 [${C_NAME}] 重定向維護模式！${NC}"
    echo -e "${CYAN}[i] 系統已在背景啟動動態保活發包與 EDNS 模擬。${NC}"
    echo -e "${YELLOW}[!] 注意：Google 地理歸屬更新需靠累積權重，請維持背景服務運行 6-24 小時。${NC}"
    read -p "按 Enter 鍵返回主選單..."
}

disable_mode() {
    echo -e "\n${YELLOW}[+] 正在停止並清理服務...${NC}"
    stop_service
    echo -e "${GREEN}[✔] 定位維護服務已順利關閉。${NC}"
    read -p "按 Enter 鍵返回主選單..."
}

install_env() {
    check_sys
    install_dependencies
    check_swap
    setup_shortcut
    echo -e "${GREEN}[✔] 環境依賴與快捷指令 (gttc / sz) 升級安裝完成！${NC}"
    read -p "按 Enter 鍵返回主選單..."
}

# -----------------------------------------------------------------
# 主選單 UI
# -----------------------------------------------------------------
main_menu() {
    check_sys
    setup_shortcut
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "      ${YELLOW}GoogleToThisCountry (GTTC) 管理控制台${NC}"
    echo -n -e "      目前重定向狀態: "
    get_status
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 1. 切換 / 啟用目標國家定位模式"
    echo -e " 2. 關閉定位維護模式"
    echo -e " 3. 一鍵檢查 / 修復依賴環境與快捷指令"
    echo -e " 0. 退出腳本"
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 💡 提示：後續可在終端輸入 ${GREEN}gttc${NC} 或 ${GREEN}sz${NC} 呼出本選單"
    echo -e "${CYAN}=================================================${NC}"
    read -p "請選擇操作 [0-3]: " MAIN_OPT

    case "$MAIN_OPT" in
        1)
            enable_mode
            main_menu
            ;;
        2)
            disable_mode
            main_menu
            ;;
        3)
            install_env
            main_menu
            ;;
        0)
            echo -e "${GREEN}感謝使用 GoogleToThisCountry，再見！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}輸入錯誤，請重新選擇！${NC}"
            sleep 1
            main_menu
            ;;
    esac
}

main_menu
