#!/usr/bin/env bash
# =============================================================================
#  OpenClaw Manager — 一键安装脚本（含 Nginx 访问控制）
#  支持: Ubuntu 16.04+ / Debian 9+ / CentOS 7+ / RHEL 7+ / Rocky / Alma /
#        OpenSUSE / Amazon Linux 2
#  架构: x86_64 / aarch64 (ARM64)
#  用法: curl -fsSL https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/install.sh | sudo bash
# =============================================================================
set -euo pipefail

# ---------- 颜色（终端不支持时自动降级）----------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}>>> $* ${RESET}"; }
step()    { echo -e "    ${BOLD}...${RESET} $*"; }

# ---------- 常量 ----------
INSTALL_DIR="/opt/openclaw-manager"
BIN_PATH="${INSTALL_DIR}/openclaw-manager"
WRAPPER_SCRIPT="${INSTALL_DIR}/openclaw-manager-service"
LOG_FILE="/var/log/openclaw-manager.log"
PIDFILE="/var/run/openclaw-manager.pid"
SERVICE_NAME="openclaw-manager"
WEB_PORT="51942"          # 内部服务端口（仅本机监听）
NGINX_PORT="51943"        # Nginx 对外端口（带密码保护）
NGINX_HTPASSWD="/etc/nginx/.openclaw_htpasswd"
NGINX_CONF="/etc/nginx/conf.d/openclaw-manager.conf"
DEFAULT_USER="apimart"
DEFAULT_PASS="apimart"
GITHUB_REPO="zhihong-apimart/OpenClaw-Manager-Releases"
LATEST_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"

# ---------- 全局变量 ----------
PKG_MANAGER=""
DOWNLOADER=""
OS_ID=""
OS_VER=""
ARCH_SUFFIX=""

# =============================================================================
#  函数区
# =============================================================================

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="unknown"
    fi
}

PKG_UPDATED=false
pkg_update() {
    if [[ "$PKG_UPDATED" == "true" ]]; then return; fi
    step "更新包索引..."
    case "$PKG_MANAGER" in
        apt)    apt-get update -qq -y 2>/dev/null || true ;;
        dnf)    dnf makecache -q 2>/dev/null || true ;;
        yum)    yum makecache -q 2>/dev/null || true ;;
        zypper) zypper refresh -q 2>/dev/null || true ;;
        apk)    apk update -q 2>/dev/null || true ;;
    esac
    PKG_UPDATED=true
}

install_pkg() {
    local pkg="$1"
    step "安装 $pkg ..."
    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive \
            NEEDRESTART_MODE=a \
            apt-get install -y -q \
                -o Dpkg::Use-Pty=0 \
                -o DPkg::Options::="--force-confold" \
                "$pkg" 2>/dev/null
            ;;
        dnf)    dnf install -y -q "$pkg" 2>/dev/null ;;
        yum)    yum install -y -q "$pkg" 2>/dev/null ;;
        zypper) zypper install -y -q "$pkg" 2>/dev/null ;;
        apk)    apk add -q "$pkg" 2>/dev/null ;;
        *)      warn "无法识别包管理器，跳过安装 $pkg" ;;
    esac
}

ensure_cmd() {
    local cmd="$1"
    local pkg="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        warn "$cmd 未找到，正在安装..."
        pkg_update
        install_pkg "$pkg"
        if ! command -v "$cmd" &>/dev/null; then
            local alt_pkg="${3:-}"
            if [[ -n "$alt_pkg" ]]; then install_pkg "$alt_pkg"; fi
        fi
        command -v "$cmd" &>/dev/null && info "$cmd 安装成功 ✓" || warn "$cmd 安装失败，继续尝试..."
    else
        info "$cmd: 已安装 ✓"
    fi
}

# =============================================================================
#  Nginx + Basic Auth 配置
# =============================================================================

setup_nginx() {
    section "配置 Nginx 访问控制（页面锁）"

    # 安装 nginx
    if ! command -v nginx &>/dev/null; then
        step "安装 nginx..."
        pkg_update
        install_pkg "nginx"
    fi
    command -v nginx &>/dev/null && info "nginx: 已安装 ✓" || warn "nginx 安装失败，访问控制可能不生效"

    # 安装 htpasswd 工具
    if ! command -v htpasswd &>/dev/null; then
        step "安装 htpasswd 工具..."
        case "$PKG_MANAGER" in
            apt)     install_pkg "apache2-utils" ;;
            dnf|yum) install_pkg "httpd-tools" ;;
            zypper)  install_pkg "apache2-utils" ;;
            apk)     install_pkg "apache2-utils" ;;
            *)       warn "无法自动安装 htpasswd" ;;
        esac
    fi

    # 生成密码文件（仅首次安装时写入默认密码，升级时保留已有密码）
    if [[ ! -f "$NGINX_HTPASSWD" ]]; then
        if command -v htpasswd &>/dev/null; then
            htpasswd -cb "$NGINX_HTPASSWD" "$DEFAULT_USER" "$DEFAULT_PASS" 2>/dev/null
        else
            # htpasswd 不可用时用 openssl 生成 apr1 哈希
            local hashed=""
            hashed=$(openssl passwd -apr1 "$DEFAULT_PASS" 2>/dev/null || true)
            if [[ -z "$hashed" ]]; then
                hashed=$(python3 -c "import crypt; print(crypt.crypt('${DEFAULT_PASS}', crypt.mksalt(crypt.METHOD_MD5)))" 2>/dev/null || true)
            fi
            if [[ -n "$hashed" ]]; then
                echo "${DEFAULT_USER}:${hashed}" > "$NGINX_HTPASSWD"
            else
                warn "无法生成密码文件，请手动运行: htpasswd -cb ${NGINX_HTPASSWD} <用户名> <密码>"
            fi
        fi
        chmod 640 "$NGINX_HTPASSWD"
        info "访问控制密码文件已创建（使用默认账号密码）✓"
    else
        info "密码文件已存在，升级时保留原有密码不覆盖 ✓"
    fi

    # 写入 nginx 配置
    mkdir -p /etc/nginx/conf.d
    cat > "$NGINX_CONF" << NGINX_EOF
# OpenClaw Manager — Nginx 反向代理 + Basic Auth
# 如需修改密码，请运行: sudo openclaw-chpasswd

server {
    listen ${NGINX_PORT};
    server_name _;

    access_log /var/log/nginx/openclaw-manager.access.log;
    error_log  /var/log/nginx/openclaw-manager.error.log;

    # ★ 页面锁：需要账号密码才能访问
    auth_basic           "OpenClaw Manager - 请输入账号密码";
    auth_basic_user_file ${NGINX_HTPASSWD};

    location / {
        proxy_pass         http://127.0.0.1:${WEB_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGINX_EOF

    # 测试配置 + 启动/重载 nginx
    if nginx -t -q 2>/dev/null; then
        systemctl enable nginx --quiet 2>/dev/null || true
        if systemctl is-active --quiet nginx 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
        else
            systemctl start nginx 2>/dev/null || true
        fi
        info "Nginx 反向代理 + 访问控制已生效 ✓"
    else
        warn "Nginx 配置语法有问题，请检查: sudo nginx -t"
    fi
}

# 安装一键改密工具到 PATH
install_chpasswd_tool() {
    cat > /usr/local/bin/openclaw-chpasswd << 'CHPASSWD_EOF'
#!/usr/bin/env bash
# OpenClaw Manager — 一键修改访问密码
# 用法: sudo openclaw-chpasswd
HTPASSWD_FILE="/etc/nginx/.openclaw_htpasswd"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      OpenClaw Manager — 修改访问密码             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

CURRENT_USER="apimart"
if [[ -f "$HTPASSWD_FILE" ]]; then
    CURRENT_USER=$(cut -d: -f1 "$HTPASSWD_FILE" 2>/dev/null | head -1 || echo "apimart")
fi

echo "  当前用户名: ${CURRENT_USER}"
echo ""

read -p "  新用户名（直接回车保持 '${CURRENT_USER}' 不变）: " NEW_USER
NEW_USER="${NEW_USER:-$CURRENT_USER}"

while true; do
    read -s -p "  新密码: " NEW_PASS; echo ""
    [[ -z "$NEW_PASS" ]] && { echo "  密码不能为空，请重新输入。"; continue; }
    read -s -p "  确认密码: " NEW_PASS2; echo ""
    [[ "$NEW_PASS" == "$NEW_PASS2" ]] && break
    echo "  两次密码不一致，请重新输入。"
done

if command -v htpasswd &>/dev/null; then
    htpasswd -cb "$HTPASSWD_FILE" "$NEW_USER" "$NEW_PASS" 2>/dev/null
else
    HASHED=$(openssl passwd -apr1 "$NEW_PASS" 2>/dev/null || true)
    [[ -z "$HASHED" ]] && { echo "  错误：无法生成密码哈希，请先安装 apache2-utils 或 httpd-tools"; exit 1; }
    echo "${NEW_USER}:${HASHED}" > "$HTPASSWD_FILE"
fi
chmod 640 "$HTPASSWD_FILE"

# 重载 nginx 使新密码立即生效
systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true

echo ""
echo "  ✅ 密码修改成功！"
echo "     用户名: ${NEW_USER}"
echo "     新密码已生效，请用新密码重新登录。"
echo ""
CHPASSWD_EOF

    chmod +x /usr/local/bin/openclaw-chpasswd
    info "密码修改工具已安装 (/usr/local/bin/openclaw-chpasswd) ✓"
}

# =============================================================================
#  主流程
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      OpenClaw Manager — 一键安装程序         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# 1. Root 检查
[[ $EUID -ne 0 ]] && error "请使用 sudo 或 root 用户运行此脚本。\n  示例: curl -fsSL ... | sudo bash"

# 2. 检测系统
section "检测系统环境"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-0}"
    info "操作系统: ${PRETTY_NAME:-$OS_ID $OS_VER}"
elif [[ -f /etc/redhat-release ]]; then
    OS_ID="rhel"; OS_VER=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    info "操作系统: $(cat /etc/redhat-release)"
else
    OS_ID="unknown"; OS_VER="0"
    warn "无法识别发行版，继续尝试..."
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        ARCH_SUFFIX="x64"   ;;
    aarch64|arm64) ARCH_SUFFIX="arm64" ;;
    *) error "不支持的 CPU 架构: $ARCH（仅支持 x86_64 / aarch64）" ;;
esac
info "CPU 架构: ${ARCH} → 将下载 linux-${ARCH_SUFFIX} 版本"
info "内核版本: $(uname -r)"

if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    info "systemd: 可用 ✓"
else
    error "此系统未检测到 systemd，暂不支持。\n  请提交 Issue: https://github.com/${GITHUB_REPO}/issues"
fi

# 3. 基础依赖
section "检测并安装基础依赖"

detect_pkg_manager
[[ "$PKG_MANAGER" == "unknown" ]] && warn "无法识别包管理器" || info "包管理器: $PKG_MANAGER ✓"

if command -v curl &>/dev/null; then
    DOWNLOADER="curl"; info "curl: 已安装 ✓"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget"; info "wget: 已安装 ✓"
else
    warn "curl/wget 均未找到，尝试安装 curl..."
    pkg_update
    [[ "$PKG_MANAGER" == "apt" ]] && install_pkg "ca-certificates"
    install_pkg "curl"
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"; info "curl 安装成功 ✓"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"; info "将使用 wget ✓"
    else
        error "无法安装下载工具，请手动安装 curl 后重试"
    fi
fi

if [[ "$PKG_MANAGER" == "apt" ]]; then
    dpkg -l ca-certificates &>/dev/null 2>&1 && info "ca-certificates: 已安装 ✓" || { pkg_update; install_pkg "ca-certificates"; }
elif [[ "$PKG_MANAGER" =~ ^(dnf|yum)$ ]]; then
    ensure_cmd "update-ca-trust" "ca-certificates" "ca-certs"
fi

for tool_info in "ps:procps:procps-ng" "ss:iproute2:iproute" "pgrep:procps:procps-ng"; do
    cmd="${tool_info%%:*}"; rest="${tool_info#*:}"
    pkg1="${rest%%:*}"; pkg2="${rest#*:}"
    command -v "$cmd" &>/dev/null || { pkg_update; install_pkg "$pkg1" || install_pkg "$pkg2" 2>/dev/null || true; }
done

# 4. 停止旧版本
UPGRADE_MODE=false
if [[ -f "$BIN_PATH" ]]; then
    CURRENT_VER=$("$BIN_PATH" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知版本")
    warn "检测到已安装: ${CURRENT_VER}，执行升级..."
    UPGRADE_MODE=true
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && { section "停止旧服务"; systemctl stop "$SERVICE_NAME" || true; sleep 2; info "旧服务已停止"; }
fi
command -v pkill &>/dev/null && pkill -f "openclaw-manager$" 2>/dev/null || true
command -v killall &>/dev/null && killall openclaw-manager 2>/dev/null || true
sleep 1

# 5. 下载程序
section "下载 OpenClaw Manager"
mkdir -p "$INSTALL_DIR"
DOWNLOAD_URL="${LATEST_URL}/openclaw-manager-linux-${ARCH_SUFFIX}"
DOWNLOAD_TMP="${INSTALL_DIR}/openclaw-manager.tmp"
echo "  下载地址: ${DOWNLOAD_URL}"
echo "  安装路径: ${BIN_PATH}"
echo ""

[[ -f "$BIN_PATH" && "$UPGRADE_MODE" == "true" ]] && { BACKUP="${BIN_PATH}.bak-$(date +%Y%m%d%H%M%S)"; cp "$BIN_PATH" "$BACKUP"; info "旧版本已备份: $BACKUP"; }

DOWNLOAD_OK=false
if [[ "$DOWNLOADER" == "curl" ]]; then
    curl -fSL --retry 3 --retry-delay 3 --connect-timeout 15 --progress-bar -o "$DOWNLOAD_TMP" "$DOWNLOAD_URL" && DOWNLOAD_OK=true || true
else
    wget -q --show-progress --tries=3 --timeout=15 -O "$DOWNLOAD_TMP" "$DOWNLOAD_URL" && DOWNLOAD_OK=true || true
fi

[[ "$DOWNLOAD_OK" != "true" ]] || [[ ! -s "$DOWNLOAD_TMP" ]] && { rm -f "$DOWNLOAD_TMP"; error "下载失败！请检查网络连接后重试。\n  下载地址: ${DOWNLOAD_URL}"; }
mv "$DOWNLOAD_TMP" "$BIN_PATH"
chmod +x "$BIN_PATH"
info "程序下载完成 ✓"

# 6. 初始化环境
section "初始化运行环境"
touch "$LOG_FILE"; chmod 644 "$LOG_FILE"
info "日志文件: $LOG_FILE ✓"

# 7. Wrapper 脚本
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
BIN="/opt/openclaw-manager/openclaw-manager"
LOG="/var/log/openclaw-manager.log"
PIDFILE="/var/run/openclaw-manager.pid"
export HOME=/root
case "${1:-start}" in
    start)
        "$BIN" >> "$LOG" 2>&1 &
        LAUNCHER_PID=$!
        sleep 3
        MAIN_PID=$(pgrep -f "openclaw-manager$" | head -1 || echo "")
        if [[ -n "$MAIN_PID" ]]; then
            echo "$MAIN_PID" > "$PIDFILE"
            echo "OpenClaw Manager started (PID=$MAIN_PID)"
        else
            echo "$LAUNCHER_PID" > "$PIDFILE"
            echo "OpenClaw Manager started (launcher PID=$LAUNCHER_PID)"
        fi
        ;;
    stop)
        [[ -f "$PIDFILE" ]] && { PID=$(cat "$PIDFILE" 2>/dev/null || echo ""); [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true; rm -f "$PIDFILE"; }
        command -v pkill &>/dev/null && pkill -f "openclaw-manager$" 2>/dev/null || true
        echo "OpenClaw Manager stopped"
        ;;
    status) "$BIN" --status 2>&1 || true ;;
esac
WRAPPER_EOF
chmod +x "$WRAPPER_SCRIPT"
info "Wrapper 脚本已创建 ✓"

# 8. systemd
section "配置 systemd 服务（开机自启）"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << UNIT_EOF
[Unit]
Description=OpenClaw Manager - AI Gateway Management Tool
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=${PIDFILE}
ExecStart=${WRAPPER_SCRIPT} start
ExecStop=${WRAPPER_SCRIPT} stop
Restart=on-failure
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=20
Environment=HOME=/root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT_EOF
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" --quiet
info "systemd 服务已注册并设置开机自启 ✓"

# 9. Nginx 访问控制
setup_nginx
install_chpasswd_tool

# 9b. 封堵内部端口（在函数外执行，避免 pipe+heredoc 嵌套问题）
section "封锁内部服务端口"
if command -v iptables &>/dev/null; then
    # 幂等：先清旧规则再添加
    iptables -D INPUT -i lo -p tcp --dport "${WEB_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "${WEB_PORT}" -j DROP 2>/dev/null || true
    iptables -I INPUT 1 -p tcp --dport "${WEB_PORT}" -j DROP
    iptables -I INPUT 1 -i lo -p tcp --dport "${WEB_PORT}" -j ACCEPT
    info "iptables: 端口 ${WEB_PORT} 已限制为仅本机可访问 ✓"

    # 持久化（开机恢复）
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        # 写 systemd 恢复 unit（文件路径不含 heredoc，直接 echo）
        SVC_FILE="/etc/systemd/system/iptables-restore-ocm.service"
        if [[ ! -f "${SVC_FILE}" ]]; then
            {
                echo "[Unit]"
                echo "Description=Restore iptables rules for OpenClaw Manager"
                echo "After=network-pre.target"
                echo ""
                echo "[Service]"
                echo "Type=oneshot"
                echo "ExecStart=/bin/sh -c 'test -f /etc/iptables/rules.v4 && /sbin/iptables-restore < /etc/iptables/rules.v4 || true'"
                echo "RemainAfterExit=yes"
                echo ""
                echo "[Install]"
                echo "WantedBy=multi-user.target"
            } > "${SVC_FILE}"
            systemctl daemon-reload
            systemctl enable iptables-restore-ocm.service --quiet 2>/dev/null || true
        else
            # 升级时只刷新规则文件，unit 已存在
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        info "iptables 规则已持久化（重启后自动恢复）✓"
    fi
else
    warn "iptables 未找到，端口 ${WEB_PORT} 建议在云服务商安全组中手动封锁"
fi

# 10. 启动服务
section "启动服务"
systemctl start "$SERVICE_NAME" || true
info "服务启动指令已发出"

# 11. 健康检查
section "健康检查（最多等待 60 秒）"
echo "  首次启动会自动安装 Node.js，请耐心等待..."
echo ""
MAX_WAIT=60
STARTED=false
for i in $(seq 1 $MAX_WAIT); do
    sleep 1
    if command -v ss &>/dev/null; then
        PORT_LISTEN=$(ss -tlnp 2>/dev/null | grep ":${WEB_PORT}" || true)
    elif command -v netstat &>/dev/null; then
        PORT_LISTEN=$(netstat -tlnp 2>/dev/null | grep ":${WEB_PORT}" || true)
    else
        PORT_LISTEN=""
    fi
    if [[ -n "$PORT_LISTEN" ]]; then
        STARTED=true; echo ""; info "服务已就绪！端口 ${WEB_PORT} 监听中 ✓"; break
    fi
    (( i % 10 == 0 )) && echo "  已等待 ${i}s，仍在初始化中..."
done
[[ "$STARTED" != "true" ]] && { warn "等待超时（60s），服务可能仍在后台初始化。"; warn "稍等片刻后访问页面，或运行: sudo tail -f ${LOG_FILE}"; }

# 12. 获取公网 IP
PUBLIC_IP=""
for ip_svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipecho.net/plain"; do
    PUBLIC_IP=$(curl -fsSL --max-time 5 "$ip_svc" 2>/dev/null | tr -d '[:space:]' || true)
    echo "$PUBLIC_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && break || PUBLIC_IP=""
done
[[ -z "$PUBLIC_IP" ]] && command -v ip &>/dev/null && PUBLIC_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1 || echo "")
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="<你的服务器公网IP>"

# =============================================================================
#  最终输出：傻瓜式使用说明
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║          🦞  OpenClaw Manager 安装成功！                         ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ★★★ 默认账号密码 — 最醒目位置 ★★★
echo ""
echo -e "${BOLD}${YELLOW}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${YELLOW}║                                                                   ║${RESET}"
echo -e "${BOLD}${YELLOW}║                  🔐  默认访问账号密码                             ║${RESET}"
echo -e "${BOLD}${YELLOW}║                                                                   ║${RESET}"
echo -e "${BOLD}${YELLOW}║   用户名：${RESET}${BOLD}${RED}  apimart  ${RESET}${BOLD}${YELLOW}                                          ║${RESET}"
echo -e "${BOLD}${YELLOW}║   密  码：${RESET}${BOLD}${RED}  apimart  ${RESET}${BOLD}${YELLOW}                                          ║${RESET}"
echo -e "${BOLD}${YELLOW}║                                                                   ║${RESET}"
echo -e "${BOLD}${YELLOW}║   ⚠️  请登录后立即修改密码！使用默认密码存在安全风险！            ║${RESET}"
echo -e "${BOLD}${YELLOW}║                                                                   ║${RESET}"
echo -e "${BOLD}${YELLOW}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  📌 接下来怎么用${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}1. 打开浏览器，访问管理页面：${RESET}"
echo -e "     ${CYAN}${BOLD}http://${PUBLIC_IP}:${NGINX_PORT}${RESET}"
echo -e "     浏览器会弹出登录框，用上方账号密码登录"
echo ""
echo -e "  ${BOLD}2. 修改访问密码（复制以下命令，按提示输入新密码）：${RESET}"
echo -e "     ${CYAN}${BOLD}sudo openclaw-chpasswd${RESET}"
echo ""
echo -e "  ${BOLD}3. 查看实时日志：${RESET}"
echo -e "     ${CYAN}sudo tail -f ${LOG_FILE}${RESET}"
echo -e "     ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${RESET}"
echo ""
echo -e "  ${BOLD}4. 服务管理命令：${RESET}"
echo -e "     查看状态  →  ${CYAN}sudo systemctl status ${SERVICE_NAME}${RESET}"
echo -e "     重启服务  →  ${CYAN}sudo systemctl restart ${SERVICE_NAME}${RESET}"
echo -e "     停止服务  →  ${CYAN}sudo systemctl stop ${SERVICE_NAME}${RESET}"
echo ""
echo -e "  ${BOLD}5. 升级到最新版本（重新运行安装脚本即可）：${RESET}"
echo -e "     ${CYAN}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | sudo bash${RESET}"
echo ""
echo -e "  ${BOLD}6. 卸载：${RESET}"
echo -e "     ${CYAN}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/uninstall.sh | sudo bash${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${YELLOW}⚠️  浏览器打不开？请在服务器防火墙/安全组放通 TCP 端口 ${NGINX_PORT}${RESET}"
echo -e "  ${YELLOW}    原服务端口 ${WEB_PORT} 已变更为 ${NGINX_PORT}（Nginx 反代端口）${RESET}"
echo ""
echo -e "  💬 遇到问题：${CYAN}https://github.com/${GITHUB_REPO}/issues${RESET}"
echo ""