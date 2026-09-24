#!/usr/bin/env bash

# =================================================================
#  Project: GoogleToThisCountry (GTTC)
#  Description: Google 地理位置重定向与多国定位维护工具
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
SYSTEM_BIN="/usr/local/bin/gttc"

mkdir -p "$CONFIG_DIR"

# -----------------------------------------------------------------
# 1. 脚本自我持久化安装 (将当前运行脚本安装至系统 PATH)
# -----------------------------------------------------------------
persist_script() {
    CURRENT_SCRIPT=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null)
    if [ "$CURRENT_SCRIPT" != "$SYSTEM_BIN" ]; then
        cp -f "$CURRENT_SCRIPT" "$SYSTEM_BIN" 2>/dev/null || true
        chmod +x "$SYSTEM_BIN" 2>/dev/null || true
    fi
    # 彻底清理旧版 sz 快捷方式 residual
    rm -f /usr/local/bin/sz 2>/dev/null || true
}

# -----------------------------------------------------------------
# 2. 系统环境检测与自动依赖安装
# -----------------------------------------------------------------
check_sys() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}错误: 无法识别当前系统作业环境，程序终止。${NC}"
        exit 1
    fi
}

install_dependencies() {
    check_sys
    if [ "$OS" = "alpine" ]; then
        if ! grep -q "community" /etc/apk/repositories; then
            echo "http://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)/community" >> /etc/apk/repositories
        fi
        apk update >/dev/null 2>&1
        apk add --no-progress bash curl openrc ca-certificates jq procps >/dev/null 2>&1
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl bash systemctl ca-certificates jq procps >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl bash ca-certificates jq procps >/dev/null 2>&1
    fi
}

check_swap() {
    # 针对低内存容器 (LXC) 建立临时 SWAP 避免 OOM 崩溃
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    
    if [ "$MEM_TOTAL" -lt 512 ] && [ "$SWAP_TOTAL" -eq 0 ]; then
        if [ "$OS" != "alpine" ]; then
            fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 >/dev/null 2>&1
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile 2>/dev/null || true
        fi
    fi
}

# -----------------------------------------------------------------
# 3. 国家参数矩阵配置
# -----------------------------------------------------------------
get_country_config() {
    case "$1" in
        "TW")
            C_NAME="台湾 🇹🇼"
            C_DOMAIN="google.com.tw"
            C_ECS="61.216.0.0/16"
            C_LANG="zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7"
            C_DOH="https://dns.google/dns-query"
            ;;
        "CN")
            C_NAME="中国大陆 🇨🇳"
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
            C_NAME="澳门 🇲🇴"
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
# 4. 服务状态检查
# -----------------------------------------------------------------
get_status() {
    if [ -f "$STATUS_FILE" ]; then
        CODE=$(cat "$STATUS_FILE")
        get_country_config "$CODE"
        echo -e "${GREEN}[已开启 - ${C_NAME}]${NC}"
    else
        echo -e "${RED}[已关闭]${NC}"
    fi
}

# -----------------------------------------------------------------
# 5. 生成后台保活脚本 (gttc-ping.sh)
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
    
    # 1. EDNS Client Subnet 域名解析发包
    curl -s -H "accept: application/dns-json" \
         "\${DOH_URL}?name=\${TARGET_DOMAIN}&type=A&edns_client_subnet=\${ECS_SUBNET}" >/dev/null 2>&1

    # 2. 模拟真实地理用户 HTTP 请求
    curl -s -L -A "\${RANDOM_UA}" \
         -H "Accept-Language: \${ACCEPT_LANG}" \
         "https://\${TARGET_DOMAIN}/generate_204" >/dev/null 2>&1

    # 3. 随机间隔 45-90 秒，避免频率异常
    SLEEP_TIME=\$((RANDOM % 46 + 45))
    sleep \$SLEEP_TIME
done
EOF
    chmod +x "$PING_SCRIPT"
}

# -----------------------------------------------------------------
# 6. 服务注册与系统守护
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
# 7. 控制台交互菜单
# -----------------------------------------------------------------
enable_mode() {
    echo -e "\n${CYAN}=================================================${NC}"
    echo -e "       ${YELLOW}请选择目标定位国家 / 地区${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 1. 🇹🇼 台湾 (Taiwan)"
    echo -e " 2. 🇨🇳 中国大陆 (China)"
    echo -e " 3. 🇯🇵 日本 (Japan)"
    echo -e " 4. 🇲🇴 澳门 (Macau)"
    echo -e " 0. 返回主菜单"
    echo -e "${CYAN}=================================================${NC}"
    read -p "请输入选项 [0-4]: " COUNTRY_OPT

    case "$COUNTRY_OPT" in
        1) TARGET_CODE="TW" ;;
        2) TARGET_CODE="CN" ;;
        3) TARGET_CODE="JP" ;;
        4) TARGET_CODE="MO" ;;
        0) return ;;
        *) echo -e "${RED}无效选项！${NC}"; sleep 1; return ;;
    esac

    get_country_config "$TARGET_CODE"
    echo -e "\n${YELLOW}[+] 正在配置并启动 [${C_NAME}] 定位维护服务...${NC}"
    
    create_ping_script
    setup_service
    echo "$TARGET_CODE" > "$STATUS_FILE"

    echo -e "${GREEN}[✔] 成功开启 [${C_NAME}] 重定向维护模式！${NC}"
    echo -e "${CYAN}[i] 系统已在后台启动动态保活发包与 EDNS 模拟。${NC}"
    echo -e "${YELLOW}[!] 注意：Google 地理归属更新需靠长效权重积累，请保持后台服务运行 6-24 小时。${NC}"
    read -p "按 Enter 键返回主菜单..."
}

disable_mode() {
    echo -e "\n${YELLOW}[+] 正在停止并清理服务...${NC}"
    stop_service
    echo -e "${GREEN}[✔] 定位维护服务已顺利关闭。${NC}"
    read -p "按 Enter 键返回主菜单..."
}

manual_install() {
    echo -e "\n${YELLOW}[+] 正在静默检查并修复依赖组件...${NC}"
    install_dependencies
    check_swap
    persist_script
    echo -e "${GREEN}[✔] 环境依赖与快捷指令 (gttc) 修复完成！${NC}"
    read -p "按 Enter 键返回主菜单..."
}

main_menu() {
    # 自动执行静默环境检查与自我持久化
    install_dependencies >/dev/null 2>&1
    check_swap >/dev/null 2>&1
    persist_script >/dev/null 2>&1

    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "      ${YELLOW}GoogleToThisCountry (GTTC) 管理控制台${NC}"
    echo -n -e "      当前重定向状态: "
    get_status
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 1. 切换 / 开启目标国家定位模式"
    echo -e " 2. 关闭定位维护模式"
    echo -e " 3. 一键检查 / 修复依赖环境与持久化命令"
    echo -e " 0. 退出脚本"
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 💡 提示：后续可在命令行直接输入 ${GREEN}gttc${NC} 呼出本菜单"
    echo -e "${CYAN}=================================================${NC}"
    read -p "请选择操作 [0-3]: " MAIN_OPT

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
            manual_install
            main_menu
            ;;
        0)
            echo -e "${GREEN}感谢使用 GoogleToThisCountry，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}输入错误，请重新选择！${NC}"
            sleep 1
            main_menu
            ;;
    esac
}

main_menu
