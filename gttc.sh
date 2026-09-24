#!/bin/bash
# =========================================================
# GoogleToThisCountry (GTTC) 管理脚本
# 官网: https://nekoqwq.com
# 支持国家/地区: 🇹🇼 台湾 | 🇨🇳 中国大陆 | 🇯🇵 日本 | 🇲🇴 澳门 | 🇺🇸 美国
# 快捷指令: gttc
# =========================================================

set -e

# --- 1. 初始化：清理旧版残留文件与快捷方式 ---
LOCAL_SCRIPT="/usr/local/bin/gttc_manager.sh"
rm -f "$LOCAL_SCRIPT" /usr/local/bin/gttc 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

PING_SCRIPT="/usr/local/bin/gttc_ping.sh"
SERVICE_FILE_SYSTEMD="/etc/systemd/system/gttc-ping.service"
SERVICE_FILE_OPENRC="/etc/init.d/gttc-ping"
CONFIG_TAG_FILE="/etc/gttc_country.conf"

show_banner() {
    clear
    echo -e "${CYAN}+-------------------------------------------------------+${NC}"
    echo -e "${CYAN}|         GoogleToThisCountry (GTTC) 管理脚本           |${NC}"
    echo -e "${CYAN}|         官网: ${YELLOW}https://nekoqwq.com${CYAN}                     |${NC}"
    echo -e "${CYAN}+-------------------------------------------------------+${NC}"
    echo ""
    echo -e "   ${BLUE}██████${NC}   ${RED}██████${NC}   ${YELLOW}██████${NC}   ${BLUE}██████${NC}    ${GREEN}██${NC}      ${RED}██████${NC}"
    echo -e "  ${BLUE}██${NC}        ${RED}██  ██${NC}   ${YELLOW}██  ██${NC}  ${BLUE}██${NC}         ${GREEN}██${NC}      ${RED}██${NC}"
    echo -e "  ${BLUE}██   ███${NC}  ${RED}██  ██${NC}   ${YELLOW}██  ██${NC}  ${BLUE}██   ███${NC}   ${GREEN}██${NC}      ${RED}██████${NC}"
    echo -e "  ${BLUE}██    ██${NC}  ${RED}██  ██${NC}   ${YELLOW}██  ██${NC}  ${BLUE}██    ██${NC}   ${GREEN}██${NC}      ${RED}██${NC}"
    echo -e "   ${BLUE}██████${NC}   ${RED}██████${NC}   ${YELLOW}██████${NC}   ${BLUE}██████${NC}    ${GREEN}███████${NC} ${RED}██████${NC}"
    echo ""
}

find_config() {
    XRAY_CONF=""
    for path in "/etc/xray/config.json" "/usr/local/etc/xray/config.json" "/etc/v2ray/config.json" "/usr/local/etc/v2ray/config.json"; do
        if [ -f "$path" ]; then
            XRAY_CONF="$path"
            break
        fi
    done
}

get_current_country_name() {
    if [ -f "$CONFIG_TAG_FILE" ]; then
        cat "$CONFIG_TAG_FILE"
    else
        echo "未开启"
    fi
}

check_status() {
    find_config
    if [ -n "$XRAY_CONF" ] && [ -f "$CONFIG_TAG_FILE" ]; then
        COUNTRY=$(cat "$CONFIG_TAG_FILE")
        echo -e "${GREEN}[已开启 - ${COUNTRY}]${NC}"
    else
        echo -e "${RED}[已关闭]${NC}"
    fi
}

setup_shortcut() {
    mkdir -p /usr/local/bin

    # 总是从远程拉取最新脚本保存到本地路径，保证 gttc 命令永不失效
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ] && [[ "$0" != *"/dev/fd/"* ]]; then
        cp -f "$0" "$LOCAL_SCRIPT" 2>/dev/null || true
    else
        curl -sSL "https://raw.githubusercontent.com/edmond1294/GoogleToThisCountry/main/gttc.sh" -o "$LOCAL_SCRIPT" || \
        wget -qO "$LOCAL_SCRIPT" "https://raw.githubusercontent.com/edmond1294/GoogleToThisCountry/main/gttc.sh"
    fi

    chmod +x "$LOCAL_SCRIPT" 2>/dev/null || true
    ln -sfn "$LOCAL_SCRIPT" /usr/local/bin/gttc
    chmod +x /usr/local/bin/gttc
}

check_swap() {
    if [ -f /proc/1/environ ] && grep -qa -e "container=lxc" -e "container=docker" /proc/1/environ; then
        return 0
    fi
    if [ -d /dev/pve ] || grep -q "lxc" /proc/1/cgroup 2>/dev/null; then
        return 0
    fi

    MEM_FREE=$(free -m | awk '/Mem:/ {print $4+$6}')
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')

    if [ -n "$MEM_FREE" ] && [ "$MEM_FREE" -lt 300 ] && [ "$SWAP_TOTAL" -eq 0 ]; then
        echo -e "${YELLOW}检测到虚拟机内存不足且未配置 Swap，正在建立 1GB 临时 Swap...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null || true
        chmod 600 /swapfile 2>/dev/null || true
        mkswap /swapfile >/dev/null 2>&1 || true
        swapon /swapfile >/dev/null 2>&1 || true
    fi
}

create_ping_service() {
    local lang_header="$1"
    
    cat << EOF > "$PING_SCRIPT"
#!/bin/bash
UA_MOBILE="Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36"

endpoints=(
    "https://www.google.com/generate_204"
    "https://connectivitycheck.gstatic.com/generate_204"
    "https://clients3.google.com/generate_204"
    "https://location.services.mozilla.com/v1/geolocate"
    "https://play.googleapis.com/generate_204"
    "https://safebrowsing.googleapis.com/v4/threatListUpdates:fetch"
)

while true; do
    for url in "\${endpoints[@]}"; do
        curl -s -A "\$UA_MOBILE" \\
             -H "Accept-Language: ${lang_header}" \\
             -H "Cache-Control: no-cache" \\
             --connect-timeout 5 \\
             "\$url" >/dev/null 2>&1 || true
    done

    SLEEP_TIME=\$((120 + RANDOM % 180))
    sleep \$SLEEP_TIME
done
EOF
    chmod +x "$PING_SCRIPT"

    if command -v rc-service >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        cat << 'EOF' > "$SERVICE_FILE_OPENRC"
#!/sbin/openrc-run

name="gttc-ping"
description="Google Country Location Keep-Alive Service"
command="/usr/local/bin/gttc_ping.sh"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need net
}
EOF
        chmod +x "$SERVICE_FILE_OPENRC"
        rc-update add gttc-ping default >/dev/null 2>&1 || true
    else
        cat << EOF > "$SERVICE_FILE_SYSTEMD"
[Unit]
Description=Google Country Location Keep-Alive Service
After=network.target

[Service]
Type=simple
ExecStart=$PING_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

install_core_alpine_binary() {
    echo -e "${YELLOW}正在下载核心服务二进制文件...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XARCH="64" ;;
        aarch64|arm64) XARCH="arm64-v8a" ;;
        armv7l) XARCH="arm32-v7a" ;;
        *) XARCH="64" ;;
    esac

    TMP_DIR=$(mktemp -d)
    curl -sSL -o "$TMP_DIR/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XARCH}.zip"
    unzip -q -o "$TMP_DIR/xray.zip" -d "$TMP_DIR"
    
    mkdir -p /usr/local/bin /usr/local/share/xray /etc/xray
    cp -f "$TMP_DIR/xray" /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
    [ -f "$TMP_DIR/geoip.dat" ] && cp -f "$TMP_DIR/geoip.dat" /usr/local/share/xray/
    [ -f "$TMP_DIR/geosite.dat" ] && cp -f "$TMP_DIR/geosite.dat" /usr/local/share/xray/
    rm -rf "$TMP_DIR"

    cat << 'EOF' > /etc/init.d/xray
#!/sbin/openrc-run

name="xray"
description="Proxy Core Service"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default >/dev/null 2>&1 || true
}

install_core() {
    setup_shortcut

    NEED_INSTALL=0
    for pkg in curl jq python3 bash unzip; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            NEED_INSTALL=1
            break
        fi
    done

    if [ "$NEED_INSTALL" -eq 1 ]; then
        echo -e "${YELLOW}=== 检测到缺少依赖，开始安装环境 ===${NC}"
        check_swap
        
        if command -v apk >/dev/null 2>&1; then
            apk update -q
            apk add -q curl jq python3 bash unzip
        elif command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl jq python3 bash unzip
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q curl jq python3 bash unzip
        fi
    fi

    if command -v apk >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        if ! command -v xray >/dev/null 2>&1; then
            echo -e "${YELLOW}检测到 Alpine 环境，配置源并尝试安装...${NC}"
            ALPINE_VER=$(cat /etc/alpine-release | cut -d'.' -f1,2)
            echo "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community" >> /etc/apk/repositories
            echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
            apk update -q

            if ! apk add -q xray 2>/dev/null; then
                install_core_alpine_binary
            else
                rc-update add xray default >/dev/null 2>&1 || true
            fi
        fi
    else
        find_config
        if [ -z "$XRAY_CONF" ]; then
            echo -e "${YELLOW}未检测到核心服务，开始执行一键安装...${NC}"
            bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
        fi
    fi

    find_config
    if [ -z "$XRAY_CONF" ]; then
        XRAY_CONF="/etc/xray/config.json"
    fi

    if [ ! -s "$XRAY_CONF" ]; then
        mkdir -p "$(dirname "$XRAY_CONF")"
        cat << 'CONF_EOF' > "$XRAY_CONF"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
CONF_EOF
        echo -e "${GREEN}已创建基础配置文件 ($XRAY_CONF)。${NC}"
    fi
}

restart_service() {
    local action="$1"
    echo -e "${YELLOW}正在重启相关服务...${NC}"
    if command -v rc-service >/dev/null 2>&1 || [ -f /etc/alpine-release ]; then
        rc-service xray $action 2>/dev/null || true
        rc-service gttc-ping $action 2>/dev/null || true
    else
        systemctl $action xray 2>/dev/null || systemctl $action v2ray 2>/dev/null || true
        if [ "$action" = "restart" ] || [ "$action" = "start" ]; then
            systemctl enable gttc-ping.service >/dev/null 2>&1 || true
            systemctl restart gttc-ping.service >/dev/null 2>&1 || true
        else
            systemctl stop gttc-ping.service >/dev/null 2>&1 || true
            systemctl disable gttc-ping.service >/dev/null 2>&1 || true
        fi
    fi
}

enable_target_country() {
    echo ""
    echo "================================================="
    echo "          请选择目标国家 / 地区"
    echo "================================================="
    echo " 1. 🇹🇼 台湾 (Taiwan)"
    echo " 2. 🇨🇳 中国大陆 (China)"
    echo " 3. 🇯🇵 日本 (Japan)"
    echo " 4. 🇲🇴 澳门 (Macao)"
    echo " 5. 🇺🇸 美国 (United States)"
    echo "================================================="
    read -p "请选择 [1-5]: " c_choice

    case "$c_choice" in
        1)
            COUNTRY_NAME="🇹🇼 台湾"
            DOH_SERVER="https://dns.google/dns-query"
            ECS_IP="168.95.1.1/24"
            LANG_HEADER="zh-TW,zh;q=0.9,en;q=0.8"
            ;;
        2)
            COUNTRY_NAME="🇨🇳 中国大陆"
            DOH_SERVER="https://dns.alidns.com/dns-query"
            ECS_IP="114.240.0.0/16"
            LANG_HEADER="zh-CN,zh;q=0.9,en;q=0.8"
            ;;
        3)
            COUNTRY_NAME="🇯🇵 日本"
            DOH_SERVER="https://dns.google/dns-query"
            ECS_IP="133.242.0.0/16"
            LANG_HEADER="ja-JP,ja;q=0.9,en;q=0.8"
            ;;
        4)
            COUNTRY_NAME="🇲🇴 澳门"
            DOH_SERVER="https://dns.google/dns-query"
            ECS_IP="202.175.3.3/24"
            LANG_HEADER="zh-MO,zh-TW;q=0.9,zh;q=0.8,en;q=0.7"
            ;;
        5)
            COUNTRY_NAME="🇺🇸 美国"
            DOH_SERVER="https://dns.google/dns-query"
            ECS_IP="64.233.160.0/24"
            LANG_HEADER="en-US,en;q=0.9"
            ;;
        *)
            echo -e "${RED}无效选择，取消操作！${NC}"
            return
            ;;
    esac

    find_config
    if [ -z "$XRAY_CONF" ]; then
        XRAY_CONF="/etc/xray/config.json"
    fi

    if [ ! -f "$XRAY_CONF" ]; then
        echo -e "${RED}错误：未找到配置文件，请先执行安装！${NC}"
        return
    fi

    cp "$XRAY_CONF" "${XRAY_CONF}.bak"

    python3 -c "
import json

conf_path = '$XRAY_CONF'
with open(conf_path, 'r') as f:
    data = json.load(f)

data['dns'] = {
    'servers': [
        {
            'address': '$DOH_SERVER',
            'clientSubnet': '$ECS_IP',
            'domains': [
                'geosite:google',
                'domain:google.com',
                'domain:googleapis.com',
                'domain:gstatic.com',
                'domain:gvt1.com',
                'domain:1e100.net',
                'domain:location.services'
            ]
        },
        'https://1.1.1.1/dns-query',
        '8.8.8.8'
    ]
}

if 'routing' not in data:
    data['routing'] = {}
data['routing']['domainStrategy'] = 'IPIfNonMatch'

with open(conf_path, 'w') as f:
    json.dump(data, f, indent=2)
"

    create_ping_service "$LANG_HEADER"
    echo "$COUNTRY_NAME" > "$CONFIG_TAG_FILE"
    restart_service "restart"

    echo -e "${GREEN}✅ 已成功开启 Google 定位重定向 -> [${COUNTRY_NAME}]！${NC}"
    echo -e "${GREEN}✅ 核心服务已重新加载配置，后台保活服务已启动。${NC}"
}

disable_target_country() {
    find_config
    if [ -z "$XRAY_CONF" ]; then
        XRAY_CONF="/etc/xray/config.json"
    fi

    if [ ! -f "$XRAY_CONF" ]; then
        echo -e "${RED}错误：未找到配置文件！${NC}"
        return
    fi

    cp "$XRAY_CONF" "${XRAY_CONF}.bak"

    python3 -c "
import json

conf_path = '$XRAY_CONF'
with open(conf_path, 'r') as f:
    data = json.load(f)

data['dns'] = {
    'servers': [
        'https://1.1.1.1/dns-query',
        '8.8.8.8',
        '1.1.1.1'
    ]
}

with open(conf_path, 'w') as f:
    json.dump(data, f, indent=2)
"
    rm -f "$CONFIG_TAG_FILE"
    restart_service "stop"

    echo -e "${GREEN}✅ 已成功关闭重定向模式，恢复默认国际解析！${NC}"
}

show_menu() {
    show_banner
    echo "================================================="
    echo -e "       GoogleToThisCountry (GTTC) 管理脚本   "
    echo -e "       当前模式状态: $(check_status)"
    echo "================================================="
    echo -e " 1. ${GREEN}开启/切换 目标国家重定向 (多维发包 + EDNS 宣告)${NC}"
    echo -e " 2. ${RED}关闭重定向模式${NC}"
    echo -e " 3. ${YELLOW}一键安装/修复 核心服务与依赖环境${NC}"
    echo " 0. 退出脚本"
    echo "================================================="
    echo -e " 💡 提示：后续可在命令行直接输入 ${GREEN}gttc${NC} 呼出本菜单"
    echo "================================================="
    read -p "请选择选项 [0-3]: " choice

    case "$choice" in
        1)
            enable_target_country
            ;;
        2)
            disable_target_country
            ;;
        3)
            install_core
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新输入！${NC}"
            show_menu
            ;;
    esac
}

# 自动建立最新的快捷方式
setup_shortcut

# 进入主菜单
show_menu
