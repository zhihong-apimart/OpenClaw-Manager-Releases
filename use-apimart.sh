#!/usr/bin/env bash
# =============================================================================
#  APIMart 一键接入脚本
#  适用于：已安装官方 OpenClaw 的用户
#  功能：注入 APIMart 模型配置 + 安装 OpenClaw Manager 管理界面
#  支持: Ubuntu / Debian / CentOS / RHEL / Rocky / Alma / OpenSUSE
#  用法: bash <(curl -fsSL https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/use-apimart.sh) YOUR_API_KEY
# =============================================================================
set -euo pipefail

# ---------- 颜色 ----------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'; BG_RED='\033[41m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''; BG_RED=''
fi
info()    { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}>>> $*${RESET}"; }

# ---------- 常量（与 install.sh 保持一致）----------
INSTALL_DIR="/opt/openclaw-manager"
BIN_PATH="${INSTALL_DIR}/openclaw-manager"
WRAPPER_SCRIPT="${INSTALL_DIR}/openclaw-manager-service"
LOG_FILE="/var/log/openclaw-manager.log"
PIDFILE="/var/run/openclaw-manager.pid"
SERVICE_NAME="openclaw-manager"
WEB_PORT="51942"
NGINX_PORT="51943"
NGINX_HTPASSWD="/etc/nginx/.openclaw_htpasswd"
NGINX_CONF="/etc/nginx/conf.d/openclaw-manager.conf"
DEFAULT_USER="apimart"
DEFAULT_PASS="apimart"
GITHUB_REPO="zhihong-apimart/OpenClaw-Manager-Releases"
LATEST_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"

# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║                                              ║"
echo "  ║      🦞  APIMart 一键接入脚本                ║"
echo "  ║                                              ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  为已有的 OpenClaw 注入 APIMart 模型，并安装可视化管理界面"
echo ""

# =============================================================================
#  Step 1: 检查环境
# =============================================================================
section "Step 1/5  检查环境"

command -v openclaw &>/dev/null || \
    error "未检测到 OpenClaw，请先安装官方龙虾: curl -fsSL https://openclaw.ai/install.sh | bash"
info "OpenClaw $(openclaw --version 2>/dev/null | head -1) ✓"

if ! command -v jq &>/dev/null; then
    echo -e "    ... 安装 jq..."
    if   command -v apt-get &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq 2>/dev/null
    elif command -v yum     &>/dev/null; then yum install -y -q jq 2>/dev/null
    elif command -v dnf     &>/dev/null; then dnf install -y -q jq 2>/dev/null
    else error "无法自动安装 jq，请手动执行: apt install jq"; fi
fi
info "jq ✓"

if ! command -v python3 &>/dev/null; then
    if   command -v apt-get &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 2>/dev/null
    elif command -v yum     &>/dev/null; then yum install -y -q python3 2>/dev/null
    elif command -v dnf     &>/dev/null; then dnf install -y -q python3 2>/dev/null
    fi
fi
info "python3 ✓"

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="x64"   ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *) error "不支持的架构: $ARCH（仅支持 x86_64 / aarch64）" ;;
esac
info "架构: $ARCH ✓"

# =============================================================================
#  Step 2: API Key
# =============================================================================
section "Step 2/5  输入 APIMart API Key"

API_KEY="${1:-}"
if [ -z "$API_KEY" ]; then
    echo ""
    echo -e "  还没有 API Key？前往 ${CYAN}https://apimart.ai${RESET} 注册获取"
    echo ""
    read -rp "  请输入你的 APIMart API Key: " API_KEY
fi
[ -z "$API_KEY" ] && error "API Key 不能为空"
info "API Key ✓"

# =============================================================================
#  Step 3: 选择节点和默认模型
# =============================================================================
section "Step 3/5  选择节点与默认模型"

echo ""
echo -e "  ${BOLD}APIMart 节点：${RESET}"
echo "    1) 国际节点  ← 海外服务器 / 国际用户"
echo "    2) 香港节点  ← 国内用户 / 国内服务器"
echo ""
read -rp "  请输入 [1/2，回车默认国际]: " NODE_CHOICE
case "${NODE_CHOICE:-1}" in
    2) HOST="cn-api.apimart.ai" ; NODE_NAME="香港节点" ;;
    *) HOST="api.apimart.ai"    ; NODE_NAME="国际节点" ;;
esac
info "节点: ${NODE_NAME} ✓"

echo ""
echo -e "  ${BOLD}默认模型：${RESET}"
echo "    1) GPT-5.3            — OpenAI 旗舰"
echo "    2) Claude Sonnet 4.6  — Anthropic，擅长写作分析"
echo "    3) DeepSeek V3.2      — 国产高性价比"
echo "    4) Gemini 2.5 Pro     — Google 最新旗舰"
echo ""
read -rp "  请输入 [1-4，回车默认 GPT-5.3]: " MODEL_CHOICE
case "${MODEL_CHOICE:-1}" in
    2) DEFAULT_MODEL="apimart-claude/claude-sonnet-4-6" ; MODEL_NAME="Claude Sonnet 4.6" ;;
    3) DEFAULT_MODEL="apimart/deepseek-v3.2"            ; MODEL_NAME="DeepSeek V3.2"     ;;
    4) DEFAULT_MODEL="apimart-gemini/gemini-2.5-pro"    ; MODEL_NAME="Gemini 2.5 Pro"    ;;
    *) DEFAULT_MODEL="apimart/gpt-5.3"                  ; MODEL_NAME="GPT-5.3"           ;;
esac
info "默认模型: ${MODEL_NAME} ✓"

# =============================================================================
#  构建 providers JSON
# =============================================================================
PROVIDERS=$(jq -n --arg host "$HOST" --arg key "$API_KEY" '{
  "apimart": {
    "baseUrl": ("https://"+$host+"/v1"),
    "api": "openai-completions",
    "apiKey": $key,
    "models": [
      {"id":"gpt-5.3-codex","name":"GPT-5.3 Codex"},
      {"id":"gpt-5.3","name":"GPT-5.3"},
      {"id":"gpt-5.2","name":"GPT-5.2"},
      {"id":"gpt-5.1","name":"GPT-5.1"},
      {"id":"gpt-5","name":"GPT-5"},
      {"id":"deepseek-v3.2","name":"DeepSeek V3.2"},
      {"id":"deepseek-v3-0324","name":"DeepSeek V3-0324"},
      {"id":"deepseek-r1-0528","name":"DeepSeek R1-0528"},
      {"id":"glm-5","name":"GLM-5"},
      {"id":"kimi-k2.5","name":"Kimi K2.5"},
      {"id":"minimax-m2.5","name":"MiniMax M2.5"}
    ]
  },
  "apimart-claude": {
    "baseUrl": ("https://"+$host),
    "api": "anthropic-messages",
    "apiKey": $key,
    "models": [
      {"id":"claude-opus-4-6","name":"Claude Opus 4.6"},
      {"id":"claude-sonnet-4-6","name":"Claude Sonnet 4.6"},
      {"id":"claude-opus-4-5-20251101","name":"Claude Opus 4.5"},
      {"id":"claude-sonnet-4-5-20250929","name":"Claude Sonnet 4.5"},
      {"id":"claude-haiku-4-5-20251001","name":"Claude Haiku 4.5"}
    ]
  },
  "apimart-gemini": {
    "baseUrl": ("https://"+$host+"/v1beta"),
    "api": "google-generative-ai",
    "apiKey": $key,
    "models": [
      {"id":"gemini-2.5-pro","name":"Gemini 2.5 Pro"},
      {"id":"gemini-2.5-flash","name":"Gemini 2.5 Flash"},
      {"id":"gemini-3.1-flash-preview","name":"Gemini 3.1 Flash Preview"},
      {"id":"gemini-3.1-pro-preview","name":"Gemini 3.1 Pro Preview"}
    ]
  }
}')

# =============================================================================
#  Step 4: 注入 APIMart 配置到所有已有 OpenClaw 实例
# =============================================================================
section "Step 4/5  注入 APIMart 配置（保留原有数据）"

HOME_DIR="$HOME"
ALL_CONFIGS=()
[ -f "$HOME_DIR/.openclaw/openclaw.json" ] && ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
for d in "$HOME_DIR"/.openclaw-*/; do
    [ -f "${d}openclaw.json" ] && ALL_CONFIGS+=("${d}openclaw.json")
done

if [ ${#ALL_CONFIGS[@]} -eq 0 ]; then
    # 没有找到已有配置，创建默认的
    mkdir -p "$HOME_DIR/.openclaw"
    echo '{"models":{},"agents":{"defaults":{"model":{"primary":""}}}}' \
        > "$HOME_DIR/.openclaw/openclaw.json"
    ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
    info "已创建默认配置目录 ✓"
fi

UPDATED=0
for cfg in "${ALL_CONFIGS[@]}"; do
    # 备份原始配置
    cp "$cfg" "${cfg}.before-apimart" 2>/dev/null || true
    TEMP=$(mktemp)
    if jq --argjson p "$PROVIDERS" --arg m "$DEFAULT_MODEL" \
        '.models.providers = $p | .agents.defaults.model.primary = $m' \
        "$cfg" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
        mv "$TEMP" "$cfg"
        info "APIMart 配置已写入: $cfg ✓"
        UPDATED=$((UPDATED+1))
    else
        rm -f "$TEMP"
        warn "写入失败: $cfg"
    fi
done
[ "$UPDATED" -eq 0 ] && error "配置写入失败"

# 确保 gateway.mode=local
for cfg in "${ALL_CONFIGS[@]}"; do
    python3 - "$cfg" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f: d = json.load(f)
changed = False
gw = d.setdefault('gateway', {})
if gw.get('mode') != 'local':
    gw['mode'] = 'local'; changed = True
if gw.get('bind') not in ('lan', 'auto'):
    gw['bind'] = 'lan'; changed = True
if changed:
    with open(path, 'w') as f: json.dump(d, f, indent=2)
PYEOF
done

# 重启 openclaw gateway（让新的 provider 配置生效）
echo -e "    ... 重启 OpenClaw Gateway..."
if openclaw gateway restart &>/dev/null 2>&1; then
    sleep 2
    info "OpenClaw Gateway 已重启 ✓"
else
    warn "Gateway 重启失败，请稍后手动执行: openclaw gateway restart"
fi

# =============================================================================
#  Step 5: 安装 OpenClaw Manager
# =============================================================================
section "Step 5/5  安装 OpenClaw Manager 管理界面"

# 5a. 安装依赖
pkg_updated=false
pkg_update_once() {
    $pkg_updated && return
    if   command -v apt-get &>/dev/null; then apt-get update -qq -y 2>/dev/null || true
    elif command -v dnf     &>/dev/null; then dnf makecache -q 2>/dev/null || true
    elif command -v yum     &>/dev/null; then yum makecache -q 2>/dev/null || true
    fi
    pkg_updated=true
}

for pkg_cmd in "nginx:nginx" "htpasswd:apache2-utils:httpd-tools" "curl:curl"; do
    cmd=$(echo "$pkg_cmd" | cut -d: -f1)
    pkg=$(echo "$pkg_cmd" | cut -d: -f2)
    alt=$(echo "$pkg_cmd" | cut -d: -f3)
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "    ... 安装 ${pkg}..."
        pkg_update_once
        if   command -v apt-get &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" 2>/dev/null || true
        elif command -v dnf     &>/dev/null; then dnf install -y -q "${alt:-$pkg}" 2>/dev/null || true
        elif command -v yum     &>/dev/null; then yum install -y -q "${alt:-$pkg}" 2>/dev/null || true
        fi
    fi
done
info "nginx / htpasswd ✓"

# 5b. 停止旧版 Manager（升级模式）
if [[ -f "$BIN_PATH" ]]; then
    CURRENT_VER=$("$BIN_PATH" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "旧版本")
    warn "检测到已安装: ${CURRENT_VER}，执行升级..."
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && { systemctl stop "$SERVICE_NAME" || true; sleep 2; }
fi
command -v pkill &>/dev/null && pkill -f "openclaw-manager$" 2>/dev/null || true
sleep 1

# 5c. 下载 Manager 二进制
mkdir -p "$INSTALL_DIR"
DOWNLOAD_URL="${LATEST_URL}/openclaw-manager-linux-${ARCH_SUFFIX}"
DOWNLOAD_TMP="${INSTALL_DIR}/openclaw-manager.tmp"
echo -e "    ... 下载 OpenClaw Manager..."

DOWNLOAD_OK=false
curl -fSL --retry 3 --retry-delay 3 --connect-timeout 15 --progress-bar \
    -o "$DOWNLOAD_TMP" "$DOWNLOAD_URL" && DOWNLOAD_OK=true || true

[[ "$DOWNLOAD_OK" != "true" || ! -s "$DOWNLOAD_TMP" ]] && {
    rm -f "$DOWNLOAD_TMP"
    error "下载失败！请检查网络后重试\n  地址: ${DOWNLOAD_URL}"
}
[[ -f "$BIN_PATH" ]] && cp "$BIN_PATH" "${BIN_PATH}.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
mv "$DOWNLOAD_TMP" "$BIN_PATH"
chmod +x "$BIN_PATH"
info "Manager 下载完成 ✓"

# 5d. Wrapper 脚本
touch "$LOG_FILE"; chmod 644 "$LOG_FILE"
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

# 5e. systemd 服务
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << UNIT_EOF
[Unit]
Description=OpenClaw Manager - AI Gateway Management Tool
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
info "systemd 服务已配置 ✓"

# 5f. Nginx 访问控制（Basic Auth）
# 密码文件（首次安装写默认密码，升级保留已有密码）
if [[ ! -f "$NGINX_HTPASSWD" ]] && command -v htpasswd &>/dev/null; then
    htpasswd -cb "$NGINX_HTPASSWD" "$DEFAULT_USER" "$DEFAULT_PASS" 2>/dev/null
    chmod 640 "$NGINX_HTPASSWD"
fi

cat > "$NGINX_CONF" << NGINX_EOF
# OpenClaw Manager — 由 use-apimart.sh 生成
server {
    listen ${NGINX_PORT};
    server_name _;

    auth_basic           "OpenClaw Manager";
    auth_basic_user_file ${NGINX_HTPASSWD};

    access_log /var/log/nginx/openclaw-manager.access.log;
    error_log  /var/log/nginx/openclaw-manager.error.log;

    location / {
        proxy_pass         http://127.0.0.1:${WEB_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
    }
}
NGINX_EOF

# 删除之前 use-apimart.sh 可能写入的旧 https 配置（端口 18790）
rm -f /etc/nginx/conf.d/openclaw-manager-https.conf 2>/dev/null || true

nginx -t 2>/dev/null && {
    systemctl is-active --quiet nginx 2>/dev/null && systemctl reload nginx || systemctl enable --now nginx 2>/dev/null
    info "Nginx 访问控制已配置 ✓"
} || warn "Nginx 配置测试失败，请检查 /etc/nginx/conf.d/openclaw-manager.conf"

# 5g. 封锁内部端口（只允许本机访问 51942）
if command -v iptables &>/dev/null; then
    iptables -D INPUT -i lo -p tcp --dport "${WEB_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "${WEB_PORT}" -j DROP 2>/dev/null || true
    iptables -I INPUT 1 -p tcp --dport "${WEB_PORT}" -j DROP
    iptables -I INPUT 1 -i lo -p tcp --dport "${WEB_PORT}" -j ACCEPT
    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    info "内部端口 ${WEB_PORT} 已封锁（仅本机可访问）✓"
fi

# 5h. 启动 Manager
systemctl start "$SERVICE_NAME" || true

# 等待启动（最多 60 秒）
echo -e "    ... 等待 Manager 启动（首次运行可能需要 30 秒）..."
MAX_WAIT=60; STARTED=false
for i in $(seq 1 $MAX_WAIT); do
    sleep 1
    if ss -tlnp 2>/dev/null | grep -q ":${WEB_PORT}" || \
       netstat -tlnp 2>/dev/null | grep -q ":${WEB_PORT}"; then
        STARTED=true; break
    fi
    (( i % 15 == 0 )) && echo "    已等待 ${i}s，仍在初始化中..."
done
$STARTED && info "OpenClaw Manager 已启动 ✓" || warn "启动超时，服务可能仍在后台初始化，稍等片刻再访问"

# =============================================================================
#  获取公网 IP
# =============================================================================
PUBLIC_IP=""
for ip_svc in "https://api.ipify.org" "https://ip.sb" "https://ifconfig.me"; do
    PUBLIC_IP=$(curl -fsS --max-time 4 "$ip_svc" 2>/dev/null | tr -d '[:space:]') && \
        [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break || PUBLIC_IP=""
done
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="你的服务器IP"

MANAGER_URL="http://${PUBLIC_IP}:${NGINX_PORT}"

# =============================================================================
#  完成
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║                                                      ║"
echo "  ║      🎉  接入成功！全部搞定！                        ║"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  已接入节点：  ${BOLD}${NODE_NAME}${RESET}"
echo -e "  默认模型：    ${BOLD}${MODEL_NAME}${RESET}"
echo -e "  原有数据：    ${BOLD}完整保留 ✓${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${BOLD}💬 开始使用 AI：${RESET}"
echo ""
echo -e "     打开飞书（或 Telegram），找到你的机器人，直接发消息 😄"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}🖥️  管理界面（切换模型 / 查看日志 / 管理实例）：${RESET}"
echo ""
echo -e "     ${CYAN}${BOLD}👉  ${MANAGER_URL}${RESET}"
echo ""
echo -e "${BOLD}${YELLOW}  ┌─────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}${YELLOW}  │   🔐 管理界面默认登录账号               │${RESET}"
echo -e "${BOLD}${YELLOW}  │                                         │${RESET}"
echo -e "${BOLD}${YELLOW}  │   用户名：${RESET}${BOLD}  apimart  ${RESET}${BOLD}${YELLOW}                   │${RESET}"
echo -e "${BOLD}${YELLOW}  │   密  码：${RESET}${BOLD}  apimart  ${RESET}${BOLD}${YELLOW}                   │${RESET}"
echo -e "${BOLD}${YELLOW}  │                                         │${RESET}"
echo -e "${BOLD}${YELLOW}  │   ⚠️  请登录后修改密码！                │${RESET}"
echo -e "${BOLD}${YELLOW}  └─────────────────────────────────────────┘${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BG_RED}${BOLD}  ⚠️  以下是【恢复原状】命令，没问题请直接忽略  ${RESET}"
echo ""
echo -e "  ${RED}  出了问题才执行（粘贴到终端回车）：${RESET}"
echo -e "  ${RED}  cp ~/.openclaw/openclaw.json.before-apimart ~/.openclaw/openclaw.json && openclaw gateway restart${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${YELLOW}⚠️  打不开管理界面？请在服务器防火墙/安全组放通 TCP ${NGINX_PORT} 端口${RESET}"
echo ""
echo -e "  有问题？联系 APIMart 技术支持：${CYAN}https://apimart.ai${RESET}"
echo ""
