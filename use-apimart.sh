#!/usr/bin/env bash
# =============================================================================
#  APIMart 一键接入脚本
#  将已安装的 OpenClaw 切换为 APIMart 中转节点，并配置 HTTPS 管理界面
#  支持: Ubuntu / Debian / CentOS / RHEL / Rocky / Alma / OpenSUSE / macOS
#  用法: bash <(curl -fsSL https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/use-apimart.sh) YOUR_API_KEY
# =============================================================================
set -euo pipefail

# ---------- 颜色（终端不支持时自动降级）----------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
    BG_RED='\033[41m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''; BG_RED=''
fi
info()    { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}>>> $*${RESET}"; }

# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}"
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
section "Step 1/5  检查环境"

# 自动安装 jq
if ! command -v jq &>/dev/null; then
    echo -e "    ... 正在安装 jq..."
    if   command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y -qq -o Dpkg::Use-Pty=0 jq 2>/dev/null
    elif command -v yum  &>/dev/null; then yum  install -y -q jq 2>/dev/null
    elif command -v dnf  &>/dev/null; then dnf  install -y -q jq 2>/dev/null
    elif command -v brew &>/dev/null; then brew install -q jq  2>/dev/null
    elif command -v apk  &>/dev/null; then apk  add -q    jq  2>/dev/null
    else error "无法自动安装 jq，请手动执行: apt install jq"; fi
    command -v jq &>/dev/null || error "jq 安装失败，请联系技术支持"
fi
info "jq ✓"

command -v openclaw &>/dev/null || \
    error "未检测到 OpenClaw，请先安装官方龙虾: curl -fsSL https://openclaw.ai/install.sh | bash"
info "OpenClaw $(openclaw --version 2>/dev/null | head -1) ✓"

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
#  Step 4: 写入配置 + 重启 Gateway
# =============================================================================
section "Step 4/5  写入配置并重启"

HOME_DIR="$HOME"
ALL_CONFIGS=()
[ -f "$HOME_DIR/.openclaw/openclaw.json" ]   && ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
for d in "$HOME_DIR"/.openclaw-*/; do
    [ -f "${d}openclaw.json" ] && ALL_CONFIGS+=("${d}openclaw.json")
done

# 没有配置文件则自动创建
if [ ${#ALL_CONFIGS[@]} -eq 0 ]; then
    mkdir -p "$HOME_DIR/.openclaw"
    echo '{"models":{},"agents":{"defaults":{"model":{"primary":""}}}}' \
        > "$HOME_DIR/.openclaw/openclaw.json"
    ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
    info "配置目录已创建 ✓"
fi

# 写入 providers + 默认模型
UPDATED=0
for cfg in "${ALL_CONFIGS[@]}"; do
    cp "$cfg" "${cfg}.before-apimart" 2>/dev/null || true
    TEMP=$(mktemp)
    if jq --argjson p "$PROVIDERS" --arg m "$DEFAULT_MODEL" \
        '.models.providers = $p | .agents.defaults.model.primary = $m' \
        "$cfg" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
        mv "$TEMP" "$cfg"
        info "配置已写入: $cfg ✓"
        UPDATED=$((UPDATED+1))
    else
        rm -f "$TEMP"
        warn "写入失败: $cfg"
    fi
done
[ "$UPDATED" -eq 0 ] && error "配置写入失败，请检查 OpenClaw 是否正确安装"

# 确保 gateway.mode=local 并开放 controlUi
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
cui = gw.setdefault('controlUi', {})
if cui.get('allowedOrigins') != ['*']:
    cui['allowedOrigins'] = ['*']; changed = True
if changed:
    with open(path, 'w') as f: json.dump(d, f, indent=2)
    print("gateway config patched")
PYEOF
done

# 重启 Gateway
echo -e "    ... 重启 OpenClaw Gateway..."
if openclaw gateway restart &>/dev/null 2>&1; then
    sleep 3
    info "Gateway 已重启 ✓"
else
    warn "Gateway 重启失败，请手动执行: openclaw gateway restart"
fi

# 读取 Gateway Token
GATEWAY_PORT=18789
GW_TOKEN=""
for cfg in "${ALL_CONFIGS[@]}"; do
    _tok=$(python3 -c "
import json
try:
    with open('${cfg}') as f: d=json.load(f)
    print(d.get('gateway',{}).get('auth',{}).get('token',''))
except: pass
" 2>/dev/null || true)
    [ -n "$_tok" ] && GW_TOKEN="$_tok" && break
done

# =============================================================================
#  Step 5: Nginx + 自签证书（让管理界面可以在浏览器正常打开）
# =============================================================================
section "Step 5/5  配置管理界面 HTTPS 访问"

# 获取公网 IP
SERVER_IP=""
for ip_url in "https://api.ipify.org" "https://ip.sb" "https://ifconfig.me"; do
    SERVER_IP=$(curl -fsS --max-time 4 "$ip_url" 2>/dev/null | tr -d '[:space:]') && \
        [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break || SERVER_IP=""
done
[ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

NGINX_HTTPS_PORT=18790
CERT_DIR="/etc/openclaw-certs"
NGINX_CONF="/etc/nginx/conf.d/openclaw-manager.conf"

NGINX_OK=false

# macOS 跳过 nginx（通常本机访问，用 http 即可）
if [[ "$(uname)" == "Darwin" ]]; then
    warn "macOS 检测到，跳过 Nginx 配置（请直接用 http://localhost:${GATEWAY_PORT} 访问）"
else
    # 安装 nginx 和 openssl
    echo -e "    ... 安装 nginx / openssl（如已安装则跳过）..."
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y -qq -o Dpkg::Use-Pty=0 nginx openssl 2>/dev/null && NGINX_OK=true
    elif command -v yum &>/dev/null; then
        yum install -y -q nginx openssl 2>/dev/null && NGINX_OK=true
    elif command -v dnf &>/dev/null; then
        dnf install -y -q nginx openssl 2>/dev/null && NGINX_OK=true
    else
        warn "无法自动安装 nginx，管理界面将使用 http 访问"
    fi

    if $NGINX_OK; then
        # 生成自签证书（绑定服务器 IP，有效期 10 年）
        mkdir -p "$CERT_DIR"
        if [ ! -f "$CERT_DIR/openclaw.crt" ] || [ ! -f "$CERT_DIR/openclaw.key" ]; then
            echo -e "    ... 生成 HTTPS 自签证书..."
            openssl req -x509 -nodes -newkey rsa:2048 \
                -keyout "$CERT_DIR/openclaw.key" \
                -out    "$CERT_DIR/openclaw.crt" \
                -days   3650 \
                -subj   "/CN=${SERVER_IP}/O=APIMart/C=CN" \
                -addext "subjectAltName=IP:${SERVER_IP},IP:127.0.0.1" \
                2>/dev/null
            chmod 600 "$CERT_DIR/openclaw.key"
            info "HTTPS 证书已生成 ✓"
        else
            info "HTTPS 证书已存在，跳过生成 ✓"
        fi

        # 构建 nginx 配置
        # 如果有 token，直接在 location / 做跳转，把 token 注入 URL 参数
        if [ -n "$GW_TOKEN" ]; then
            WS_REDIRECT="wss://${SERVER_IP}:${NGINX_HTTPS_PORT}"
            MANAGER_LOCATION="
        # 访问根路径时自动携带 token 跳转到管理界面
        location = / {
            return 302 /chat?wsUrl=${WS_REDIRECT}&token=${GW_TOKEN};
        }"
        else
            MANAGER_LOCATION=""
        fi

        # 在 nginx.conf http 块里注入 connection_upgrade map（幂等）
        if ! grep -q "connection_upgrade" /etc/nginx/nginx.conf 2>/dev/null; then
            sed -i '/http {/a\    map $http_upgrade $connection_upgrade {\n        default upgrade;\n        '"''"' close;\n    }' /etc/nginx/nginx.conf
        fi

        cat > "$NGINX_CONF" << NGINX_EOF
# APIMart OpenClaw Manager UI — 由 use-apimart.sh 自动生成
server {
    listen ${NGINX_HTTPS_PORT} ssl;
    server_name _;

    ssl_certificate     ${CERT_DIR}/openclaw.crt;
    ssl_certificate_key ${CERT_DIR}/openclaw.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
${MANAGER_LOCATION}

    # 统一反代所有请求（HTTP + WebSocket 升级）
    location / {
        proxy_pass         http://127.0.0.1:${GATEWAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }
}
NGINX_EOF

        # 测试并重载/启动 nginx
        if nginx -t 2>/dev/null; then
            if systemctl is-active --quiet nginx 2>/dev/null; then
                systemctl reload nginx 2>/dev/null && info "Nginx 已重载 ✓"
            else
                systemctl enable --now nginx 2>/dev/null || nginx 2>/dev/null
                info "Nginx 已启动 ✓"
            fi
        else
            warn "Nginx 配置测试失败，管理界面将使用 http 访问"
            NGINX_OK=false
        fi
    fi
fi

# =============================================================================
#  构建最终访问链接
# =============================================================================
if $NGINX_OK; then
    MANAGER_URL="https://${SERVER_IP}:${NGINX_HTTPS_PORT}"
    MANAGER_DIRECT_NOTE="（浏览器会提示「不安全」，点「高级」→「继续前往」即可，这是正常的）"
else
    # 回退到 http，附带 token 参数
    if [ -n "$GW_TOKEN" ]; then
        MANAGER_URL="http://${SERVER_IP}:${GATEWAY_PORT}"
        MANAGER_DIRECT_NOTE="（如无法打开，请在「网关令牌」处填入：${GW_TOKEN}）"
    else
        MANAGER_URL="http://${SERVER_IP}:${GATEWAY_PORT}"
        MANAGER_DIRECT_NOTE=""
    fi
fi

# =============================================================================
#  完成 —— 傻瓜式指引
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║                                                      ║"
echo "  ║      🎉  接入成功！全部搞定！                        ║"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  节点：     ${BOLD}${NODE_NAME}${RESET}"
echo -e "  默认模型： ${BOLD}${MODEL_NAME}${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${BOLD}💬 开始使用 AI：${RESET}"
echo ""
echo -e "     打开飞书（或 Telegram），找到你的机器人，直接发消息就行 😄"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}🖥️  管理界面（切换模型 / 查看日志 / 管理配置）：${RESET}"
echo ""
echo -e "     ${CYAN}${BOLD}👉  ${MANAGER_URL}${RESET}"
echo ""
echo -e "     ${MANAGER_DIRECT_NOTE}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BG_RED}${BOLD}  ⚠️  以下命令是【恢复原状】用的，没问题请直接忽略  ${RESET}"
echo ""
echo -e "  ${RED}  出了问题才执行这条（粘贴到终端回车）：${RESET}"
echo -e "  ${RED}  cp ~/.openclaw/openclaw.json.before-apimart ~/.openclaw/openclaw.json && openclaw gateway restart${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  有问题？联系 APIMart 技术支持：${CYAN}https://apimart.ai${RESET}"
echo ""
