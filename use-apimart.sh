#!/usr/bin/env bash
# =============================================================================
#  APIMart 一键接入脚本
#  将已安装的 OpenClaw 切换为 APIMart 中转节点
#  支持: Ubuntu / Debian / CentOS / RHEL / Rocky / Alma / OpenSUSE / macOS
#  用法: curl -fsSLo use-apimart.sh https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/use-apimart.sh && bash use-apimart.sh YOUR_API_KEY
# =============================================================================
set -euo pipefail

# ---------- 颜色 ----------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}>>> $*${RESET}"; }
step()    { echo -e "    ... $*"; }

# =============================================================================
#  Banner
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║                                              ║"
echo "  ║      🦞  APIMart 一键接入脚本                ║"
echo "  ║                                              ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  将你的 OpenClaw 接入 APIMart，即可畅享全球顶尖 AI 模型"
echo ""

# =============================================================================
#  Step 1: 检查依赖
# =============================================================================
section "Step 1/4  检查依赖环境"

# 安装 jq
if ! command -v jq &>/dev/null; then
    step "正在自动安装 jq..."
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y -qq -o Dpkg::Use-Pty=0 jq 2>/dev/null
    elif command -v yum  &>/dev/null; then yum  install -y -q jq 2>/dev/null
    elif command -v dnf  &>/dev/null; then dnf  install -y -q jq 2>/dev/null
    elif command -v brew &>/dev/null; then brew install jq -q  2>/dev/null
    elif command -v apk  &>/dev/null; then apk  add -q jq      2>/dev/null
    else error "无法自动安装 jq，请手动执行: apt install jq"; fi
    command -v jq &>/dev/null || error "jq 安装失败"
fi
info "jq ✓"

command -v openclaw &>/dev/null || \
    error "未检测到 OpenClaw，请先安装: curl -fsSL https://openclaw.ai/install.sh | bash"
info "OpenClaw $(openclaw --version 2>/dev/null | head -1) ✓"

# =============================================================================
#  Step 2: 获取 API Key
# =============================================================================
section "Step 2/4  输入 APIMart API Key"

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
#  Step 3: 选择节点和模型
# =============================================================================
section "Step 3/4  配置节点与模型"

echo ""
echo -e "  ${BOLD}选择 APIMart 节点：${RESET}"
echo "    1) 国际节点  ← 海外服务器 / 国际用户"
echo "    2) 香港节点  ← 国内用户 / 国内服务器"
echo ""
read -rp "  请输入选项 [1/2，回车默认国际]: " NODE_CHOICE
case "${NODE_CHOICE:-1}" in
    2) HOST="cn-api.apimart.ai" ; NODE_NAME="香港节点" ;;
    *) HOST="api.apimart.ai"    ; NODE_NAME="国际节点" ;;
esac
info "节点: ${NODE_NAME} ✓"

echo ""
echo -e "  ${BOLD}选择默认模型：${RESET}"
echo "    1) GPT-5.3            — OpenAI 旗舰"
echo "    2) Claude Sonnet 4.6  — Anthropic，擅长写作分析"
echo "    3) DeepSeek V3.2      — 国产高性价比"
echo "    4) Gemini 2.5 Pro     — Google 最新旗舰"
echo ""
read -rp "  请输入选项 [1-4，回车默认 GPT-5.3]: " MODEL_CHOICE
case "${MODEL_CHOICE:-1}" in
    2) DEFAULT_MODEL="apimart-claude/claude-sonnet-4-6" ; MODEL_NAME="Claude Sonnet 4.6" ;;
    3) DEFAULT_MODEL="apimart/deepseek-v3.2"            ; MODEL_NAME="DeepSeek V3.2"     ;;
    4) DEFAULT_MODEL="apimart-gemini/gemini-2.5-pro"    ; MODEL_NAME="Gemini 2.5 Pro"    ;;
    *) DEFAULT_MODEL="apimart/gpt-5.3"                  ; MODEL_NAME="GPT-5.3"           ;;
esac
info "模型: ${MODEL_NAME} ✓"

# =============================================================================
#  构建 providers JSON
# =============================================================================
PROVIDERS=$(jq -n --arg host "$HOST" --arg key "$API_KEY" '{
  "apimart": {
    "baseUrl": ("https://"+$host+"/v1"), "api": "openai-completions", "apiKey": $key,
    "models": [
      {"id":"gpt-5.3-codex","name":"GPT-5.3 Codex"},{"id":"gpt-5.3","name":"GPT-5.3"},
      {"id":"gpt-5.2","name":"GPT-5.2"},{"id":"gpt-5.1","name":"GPT-5.1"},
      {"id":"gpt-5","name":"GPT-5"},{"id":"deepseek-v3.2","name":"DeepSeek V3.2"},
      {"id":"deepseek-v3-0324","name":"DeepSeek V3-0324"},
      {"id":"deepseek-r1-0528","name":"DeepSeek R1-0528"},
      {"id":"glm-5","name":"GLM-5"},{"id":"kimi-k2.5","name":"Kimi K2.5"},
      {"id":"minimax-m2.5","name":"MiniMax M2.5"}
    ]
  },
  "apimart-claude": {
    "baseUrl": ("https://"+$host), "api": "anthropic-messages", "apiKey": $key,
    "models": [
      {"id":"claude-opus-4-6","name":"Claude Opus 4.6"},
      {"id":"claude-sonnet-4-6","name":"Claude Sonnet 4.6"},
      {"id":"claude-opus-4-5-20251101","name":"Claude Opus 4.5"},
      {"id":"claude-sonnet-4-5-20250929","name":"Claude Sonnet 4.5"},
      {"id":"claude-haiku-4-5-20251001","name":"Claude Haiku 4.5"}
    ]
  },
  "apimart-gemini": {
    "baseUrl": ("https://"+$host+"/v1beta"), "api": "google-generative-ai", "apiKey": $key,
    "models": [
      {"id":"gemini-2.5-pro","name":"Gemini 2.5 Pro"},
      {"id":"gemini-2.5-flash","name":"Gemini 2.5 Flash"},
      {"id":"gemini-3.1-flash-preview","name":"Gemini 3.1 Flash Preview"},
      {"id":"gemini-3.1-pro-preview","name":"Gemini 3.1 Pro Preview"}
    ]
  }
}')

# =============================================================================
#  Step 4: 写入配置、配置 Gateway、配置 HTTPS
# =============================================================================
section "Step 4/4  写入配置并启动服务"

HOME_DIR="$HOME"
ALL_CONFIGS=()
[ -f "$HOME_DIR/.openclaw/openclaw.json" ] && ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
for d in "$HOME_DIR"/.openclaw-*/; do
    [ -f "${d}openclaw.json" ] && ALL_CONFIGS+=("${d}openclaw.json")
done

# 没有配置则自动创建
if [ ${#ALL_CONFIGS[@]} -eq 0 ]; then
    step "初始化 OpenClaw 配置..."
    mkdir -p "$HOME_DIR/.openclaw"
    echo '{"models":{},"agents":{"defaults":{"model":{"primary":""}}}}' \
        > "$HOME_DIR/.openclaw/openclaw.json"
    ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
fi

# 写入 providers + 默认模型 + gateway 配置
UPDATED=0
for cfg in "${ALL_CONFIGS[@]}"; do
    cp "$cfg" "${cfg}.before-apimart" 2>/dev/null || true
    TEMP=$(mktemp)
    if jq --argjson p "$PROVIDERS" --arg m "$DEFAULT_MODEL" '
        .models.providers = $p
        | .agents.defaults.model.primary = $m
        | .gateway.mode = "local"
        | .gateway.bind = "lan"
        | .gateway.controlUi.allowedOrigins = ["*"]
        ' "$cfg" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
        mv "$TEMP" "$cfg"
        info "配置写入 ✓"
        UPDATED=$((UPDATED+1))
    else
        rm -f "$TEMP"; warn "写入失败: $cfg"
    fi
done
[ "$UPDATED" -eq 0 ] && error "配置写入失败"

# 生成固定 Gateway Token
GW_TOKEN=$(openssl rand -hex 24 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')
step "生成 Gateway Token..."

# 创建 system 级 systemd service（root 权限，开机自启，不依赖登录 session）
if [ "$(id -u)" = "0" ] && command -v systemctl &>/dev/null; then
    cat > /etc/systemd/system/openclaw-gateway.service << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_GATEWAY_TOKEN=${GW_TOKEN}
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable openclaw-gateway &>/dev/null
    systemctl restart openclaw-gateway
    sleep 4
    info "Gateway 系统服务已启动 ✓"
else
    # 非 root 或无 systemd，用 openclaw 自带方式
    OPENCLAW_GATEWAY_TOKEN="$GW_TOKEN" openclaw gateway restart &>/dev/null 2>&1 || true
    sleep 3
    info "Gateway 已重启 ✓"
fi

# 配置 HTTPS（nginx + 自签证书）
setup_https() {
    command -v nginx &>/dev/null || {
        step "安装 nginx..."
        if   command -v apt-get &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
            apt-get install -y -qq -o Dpkg::Use-Pty=0 nginx openssl 2>/dev/null
        elif command -v yum &>/dev/null; then yum install -y -q nginx openssl 2>/dev/null
        elif command -v dnf &>/dev/null; then dnf install -y -q nginx openssl 2>/dev/null
        else return 1; fi
    }
    command -v nginx &>/dev/null || return 1

    mkdir -p /etc/nginx/ssl
    [ -f /etc/nginx/ssl/openclaw.crt ] || \
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/openclaw.key \
        -out    /etc/nginx/ssl/openclaw.crt \
        -subj   "/CN=openclaw" 2>/dev/null || return 1

    cat > /etc/nginx/conf.d/openclaw.conf << 'NGINXEOF'
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/openclaw.crt;
    ssl_certificate_key /etc/nginx/ssl/openclaw.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
    }
}
server { listen 80; server_name _; return 301 https://$host$request_uri; }
NGINXEOF

    nginx -t &>/dev/null && systemctl restart nginx &>/dev/null && return 0 || return 1
}

HTTPS_OK=false
if [ "$(id -u)" = "0" ]; then
    step "配置 HTTPS..."
    setup_https && HTTPS_OK=true && info "HTTPS 已配置 ✓" || warn "HTTPS 配置失败，将使用 HTTP"
fi

# 获取公网 IP
PUBLIC_IP=""
for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
    PUBLIC_IP=$(curl -fsSL --max-time 4 "$svc" 2>/dev/null | tr -d '[:space:]' || true)
    echo "$PUBLIC_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && break || PUBLIC_IP=""
done
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="<你的服务器IP>"

# 拼接带 token 的访问链接
if [ "$HTTPS_OK" = "true" ]; then
    ACCESS_URL="https://${PUBLIC_IP}/#token=${GW_TOKEN}"
    WS_URL="wss://${PUBLIC_IP}"
else
    ACCESS_URL="http://${PUBLIC_IP}:18789/#token=${GW_TOKEN}"
    WS_URL="ws://${PUBLIC_IP}:18789"
fi

# 验证 gateway 确实在跑
if ! ss -tlnp 2>/dev/null | grep -q ":18789" && ! netstat -tlnp 2>/dev/null | grep -q ":18789"; then
    warn "Gateway 端口 18789 未检测到，请手动执行: systemctl restart openclaw-gateway"
fi

# =============================================================================
#  完成
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║                                                      ║"
echo "  ║      🎉  接入成功！                                  ║"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🌐 用浏览器打开以下链接，直接进入 OpenClaw${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${CYAN}${BOLD}${ACCESS_URL}${RESET}"
echo ""
if [ "$HTTPS_OK" = "true" ]; then
    echo -e "  ${YELLOW}提示：浏览器提示「不安全」→ 点「高级」→「继续访问」即可${RESET}"
fi
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  ✅ 配置摘要${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  节点：     ${BOLD}${NODE_NAME}${RESET}"
echo -e "  默认模型： ${BOLD}${MODEL_NAME}${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🆘 遇到问题？复制命令执行${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  打不开 / 模型没更新，重启服务："
echo -e "  ${CYAN}systemctl restart openclaw-gateway${RESET}"
echo ""
echo -e "  恢复到接入前的状态："
echo -e "  ${CYAN}cp ~/.openclaw/openclaw.json.before-apimart ~/.openclaw/openclaw.json && systemctl restart openclaw-gateway${RESET}"
echo ""
