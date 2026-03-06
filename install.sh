#!/usr/bin/env bash
# =============================================================================
#  OpenClaw Manager — 一键安装脚本
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
WEB_PORT="51942"
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

# 检测包管理器
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

# 更新包索引（只更新一次）
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

# 安装单个包
install_pkg() {
    local pkg="$1"
    step "安装 $pkg ..."
    case "$PKG_MANAGER" in
        apt)    apt-get install -y -q "$pkg" 2>/dev/null ;;
        dnf)    dnf install -y -q "$pkg" 2>/dev/null ;;
        yum)    yum install -y -q "$pkg" 2>/dev/null ;;
        zypper) zypper install -y -q "$pkg" 2>/dev/null ;;
        apk)    apk add -q "$pkg" 2>/dev/null ;;
        *)      warn "无法识别包管理器，跳过安装 $pkg" ;;
    esac
}

# 确保某个命令可用，不存在则安装对应包
ensure_cmd() {
    local cmd="$1"
    local pkg="${2:-$1}"   # 包名默认和命令同名
    if ! command -v "$cmd" &>/dev/null; then
        warn "$cmd 未找到，正在安装..."
        pkg_update
        install_pkg "$pkg"
        if ! command -v "$cmd" &>/dev/null; then
            # 二次尝试（CentOS 有时包名不同）
            local alt_pkg="${3:-}"
            if [[ -n "$alt_pkg" ]]; then
                install_pkg "$alt_pkg"
            fi
        fi
        command -v "$cmd" &>/dev/null && info "$cmd 安装成功 ✓" || warn "$cmd 安装失败，继续尝试..."
    else
        info "$cmd: 已安装 ✓"
    fi
}

# =============================================================================
#  开始
# =============================================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      OpenClaw Manager — 一键安装程序         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# ---------- 1. Root 检查 ----------
[[ $EUID -ne 0 ]] && error "请使用 sudo 或 root 用户运行此脚本。\n  示例: curl -fsSL ... | sudo bash"

# ---------- 2. 检测系统 ----------
section "检测系统环境"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VER="${VERSION_ID:-0}"
    info "操作系统: ${PRETTY_NAME:-$OS_ID $OS_VER}"
elif [[ -f /etc/redhat-release ]]; then
    OS_ID="rhel"
    OS_VER=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    info "操作系统: $(cat /etc/redhat-release)"
else
    OS_ID="unknown"
    OS_VER="0"
    warn "无法识别发行版，继续尝试..."
fi

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        ARCH_SUFFIX="x64"   ;;
    aarch64|arm64) ARCH_SUFFIX="arm64" ;;
    *) error "不支持的 CPU 架构: $ARCH（仅支持 x86_64 / aarch64）" ;;
esac
info "CPU 架构: ${ARCH} → 将下载 linux-${ARCH_SUFFIX} 版本"

# 内核版本
KERNEL=$(uname -r)
info "内核版本: $KERNEL"

# systemd 检测
if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    info "systemd: 可用 ✓"
else
    error "此系统未检测到 systemd，暂不支持。\n  如需帮助请提交 Issue: https://github.com/${GITHUB_REPO}/issues"
fi

# ---------- 3. 检测并安装包管理器/基础工具 ----------
section "检测并安装基础依赖"

detect_pkg_manager
if [[ "$PKG_MANAGER" == "unknown" ]]; then
    warn "无法识别包管理器，将跳过自动安装依赖（需要 curl 或 wget）"
else
    info "包管理器: $PKG_MANAGER ✓"
fi

# 必须有 curl 或 wget 之一
if command -v curl &>/dev/null; then
    DOWNLOADER="curl"
    info "curl: 已安装 ✓"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget"
    info "wget: 已安装 ✓"
else
    warn "curl 和 wget 均未找到，尝试安装 curl..."
    pkg_update
    # apt 系
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        install_pkg "ca-certificates"
        install_pkg "curl"
    # rpm 系
    elif [[ "$PKG_MANAGER" =~ ^(dnf|yum)$ ]]; then
        install_pkg "curl"
    else
        install_pkg "curl"
    fi

    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
        info "curl 安装成功 ✓"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
        info "将使用 wget ✓"
    else
        error "无法安装下载工具，请手动安装 curl 后重试:\n  Ubuntu/Debian: apt-get install -y curl\n  CentOS/RHEL:   yum install -y curl"
    fi
fi

# 确保 ca-certificates 存在（HTTPS 下载必须）
if [[ "$PKG_MANAGER" == "apt" ]]; then
    if ! dpkg -l ca-certificates &>/dev/null 2>&1; then
        step "安装 ca-certificates（HTTPS 需要）..."
        pkg_update
        install_pkg "ca-certificates"
    else
        info "ca-certificates: 已安装 ✓"
    fi
elif [[ "$PKG_MANAGER" =~ ^(dnf|yum)$ ]]; then
    ensure_cmd "update-ca-trust" "ca-certificates" "ca-certs"
fi

# 其他常用工具（不强制，缺了有备用方案）
for tool_info in "ps:procps:procps-ng" "ss:iproute2:iproute" "pgrep:procps:procps-ng"; do
    cmd="${tool_info%%:*}"
    rest="${tool_info#*:}"
    pkg1="${rest%%:*}"
    pkg2="${rest#*:}"
    if ! command -v "$cmd" &>/dev/null; then
        warn "$cmd 未找到，尝试安装..."
        pkg_update
        install_pkg "$pkg1" || install_pkg "$pkg2" 2>/dev/null || true
    fi
done

# ---------- 4. 停止旧版本（如有）----------
UPGRADE_MODE=false
if [[ -f "$BIN_PATH" ]]; then
    CURRENT_VER=$("$BIN_PATH" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知版本")
    warn "检测到已安装: ${CURRENT_VER}，执行升级..."
    UPGRADE_MODE=true

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        section "停止旧服务"
        systemctl stop "$SERVICE_NAME" || true
        sleep 2
        info "旧服务已停止"
    fi
fi

# Kill 可能残留的直接运行进程
if command -v pkill &>/dev/null; then
    pkill -f "openclaw-manager$" 2>/dev/null || true
elif command -v killall &>/dev/null; then
    killall openclaw-manager 2>/dev/null || true
fi
sleep 1

# ---------- 5. 下载程序 ----------
section "下载 OpenClaw Manager"

mkdir -p "$INSTALL_DIR"
DOWNLOAD_URL="${LATEST_URL}/openclaw-manager-linux-${ARCH_SUFFIX}"
DOWNLOAD_TMP="${INSTALL_DIR}/openclaw-manager.tmp"

echo "  下载地址: ${DOWNLOAD_URL}"
echo "  安装路径: ${BIN_PATH}"
echo ""

# 备份旧版本
if [[ -f "$BIN_PATH" && "$UPGRADE_MODE" == "true" ]]; then
    BACKUP="${BIN_PATH}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$BIN_PATH" "$BACKUP"
    info "旧版本已备份: $BACKUP"
fi

# 下载（带重试）
DOWNLOAD_OK=false
if [[ "$DOWNLOADER" == "curl" ]]; then
    if curl -fSL --retry 3 --retry-delay 3 --connect-timeout 15 \
            --progress-bar -o "$DOWNLOAD_TMP" "$DOWNLOAD_URL"; then
        DOWNLOAD_OK=true
    fi
else
    if wget -q --show-progress --tries=3 --timeout=15 \
            -O "$DOWNLOAD_TMP" "$DOWNLOAD_URL"; then
        DOWNLOAD_OK=true
    fi
fi

if [[ "$DOWNLOAD_OK" != "true" ]] || [[ ! -s "$DOWNLOAD_TMP" ]]; then
    rm -f "$DOWNLOAD_TMP"
    error "下载失败！请检查网络连接后重试。\n  下载地址: ${DOWNLOAD_URL}\n  或手动下载后上传到服务器"
fi

mv "$DOWNLOAD_TMP" "$BIN_PATH"
chmod +x "$BIN_PATH"
info "程序下载完成 ✓"

# ---------- 6. 初始化日志 ----------
section "初始化运行环境"

touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
info "日志文件: $LOG_FILE ✓"
info "安装目录: $INSTALL_DIR ✓"

# ---------- 7. 创建 Wrapper 脚本 ----------
# 因为 openclaw-manager 会自行 daemonize（后台化），
# 用 Type=forking + wrapper 让 systemd 正确追踪进程
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

BIN="/opt/openclaw-manager/openclaw-manager"
LOG="/var/log/openclaw-manager.log"
PIDFILE="/var/run/openclaw-manager.pid"

export HOME=/root

case "${1:-start}" in
    start)
        # 启动（程序自行 daemonize）
        "$BIN" >> "$LOG" 2>&1 &
        LAUNCHER_PID=$!
        # 等待 daemonize 完成
        sleep 3
        # 找到真正的主进程 PID
        MAIN_PID=$(pgrep -f "openclaw-manager$" | head -1 || echo "")
        if [[ -n "$MAIN_PID" ]]; then
            echo "$MAIN_PID" > "$PIDFILE"
            echo "OpenClaw Manager started (PID=$MAIN_PID)"
        else
            # fallback: 用 launcher PID
            echo "$LAUNCHER_PID" > "$PIDFILE"
            echo "OpenClaw Manager started (launcher PID=$LAUNCHER_PID)"
        fi
        ;;
    stop)
        if [[ -f "$PIDFILE" ]]; then
            PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
            [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
        # 保底 kill
        if command -v pkill &>/dev/null; then
            pkill -f "openclaw-manager$" 2>/dev/null || true
        fi
        echo "OpenClaw Manager stopped"
        ;;
    status)
        "$BIN" --status 2>&1 || true
        ;;
esac
WRAPPER_EOF

chmod +x "$WRAPPER_SCRIPT"
info "Wrapper 脚本已创建 ✓"

# ---------- 8. 写入 systemd unit ----------
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

# ---------- 9. 启动服务 ----------
section "启动服务"
systemctl start "$SERVICE_NAME"
info "服务启动指令已发出"

# ---------- 10. 健康检查 ----------
section "健康检查（最多等待 60 秒）"
echo "  首次启动会自动安装 Node.js，请耐心等待..."
echo ""

MAX_WAIT=60
STARTED=false
for i in $(seq 1 $MAX_WAIT); do
    sleep 1
    # 优先用 ss，备用 netstat
    if command -v ss &>/dev/null; then
        PORT_LISTEN=$(ss -tlnp 2>/dev/null | grep ":${WEB_PORT}" || true)
    elif command -v netstat &>/dev/null; then
        PORT_LISTEN=$(netstat -tlnp 2>/dev/null | grep ":${WEB_PORT}" || true)
    else
        PORT_LISTEN=""
    fi

    if [[ -n "$PORT_LISTEN" ]]; then
        STARTED=true
        echo ""
        info "服务已就绪！端口 ${WEB_PORT} 监听中 ✓"
        break
    fi

    # 每 10 秒打一个点，避免用户以为卡死
    if (( i % 10 == 0 )); then
        echo "  已等待 ${i}s，仍在初始化中（安装 Node.js 需要约 30-60 秒）..."
    fi
done

if [[ "$STARTED" != "true" ]]; then
    warn "等待超时（60s），服务可能仍在后台初始化中。"
    warn "请稍等 1-2 分钟后访问管理页面，或运行以下命令查看进度："
    warn "  sudo tail -f ${LOG_FILE}"
fi

# ---------- 11. 获取公网 IP ----------
PUBLIC_IP=""
for ip_svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipecho.net/plain"; do
    PUBLIC_IP=$(curl -fsSL --max-time 5 "$ip_svc" 2>/dev/null | tr -d '[:space:]' || true)
    # 简单校验是 IP 格式
    if echo "$PUBLIC_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        break
    fi
    PUBLIC_IP=""
done

# fallback：从路由表取
if [[ -z "$PUBLIC_IP" ]]; then
    if command -v ip &>/dev/null; then
        PUBLIC_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1 || echo "")
    fi
fi
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="<你的服务器公网IP>"

# =============================================================================
#  最终输出：傻瓜式使用说明
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║          🦞  OpenClaw Manager 安装成功！                     ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  📌 接下来怎么用${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}1. 打开浏览器，访问管理页面：${RESET}"
echo -e "     ${CYAN}${BOLD}http://${PUBLIC_IP}:${WEB_PORT}${RESET}"
echo ""
echo -e "  ${BOLD}2. 查看实时日志：${RESET}（Ctrl+C 退出）"
echo -e "     ${CYAN}sudo tail -f ${LOG_FILE}${RESET}"
echo -e "     或"
echo -e "     ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${RESET}"
echo ""
echo -e "  ${BOLD}3. 服务管理命令：${RESET}"
echo -e "     查看状态  →  ${CYAN}sudo systemctl status ${SERVICE_NAME}${RESET}"
echo -e "     重启服务  →  ${CYAN}sudo systemctl restart ${SERVICE_NAME}${RESET}"
echo -e "     停止服务  →  ${CYAN}sudo systemctl stop ${SERVICE_NAME}${RESET}"
echo -e "     启动服务  →  ${CYAN}sudo systemctl start ${SERVICE_NAME}${RESET}"
echo ""
echo -e "  ${BOLD}4. 升级到最新版本（重新运行安装脚本即可）：${RESET}"
echo -e "     ${CYAN}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | sudo bash${RESET}"
echo ""
echo -e "  ${BOLD}5. 卸载：${RESET}"
echo -e "     ${CYAN}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/uninstall.sh | sudo bash${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${YELLOW}⚠️  浏览器打不开？请在服务器防火墙/安全组中放通 TCP 端口 ${WEB_PORT}${RESET}"
echo ""
echo -e "  💬 遇到问题：${CYAN}https://github.com/${GITHUB_REPO}/issues${RESET}"
echo ""
