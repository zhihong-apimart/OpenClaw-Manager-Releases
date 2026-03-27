#!/usr/bin/env bash
# =============================================================================
#  APIMart 一键接入脚本
#  将已安装的 OpenClaw 切换为 APIMart 中转节点
#  支持: Ubuntu / Debian / CentOS / RHEL / Rocky / Alma / OpenSUSE / macOS
#  用法: bash <(curl -fsSL https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/use-apimart.sh) YOUR_API_KEY
# =============================================================================
set -euo pipefail

# ---------- 颜色（终端不支持时自动降级）----------
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
    BG_RED='\033[41m'; WHITE='\033[0;37m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
    BG_RED=''; WHITE=''
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
section "Step 1/4  检查环境"

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
#  Step 3: 选择节点和默认模型
# =============================================================================
section "Step 3/4  选择节点与默认模型"

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
section "Step 4/4  写入配置并重启"

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

# 写入
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

# 确保 gateway.mode=local（OpenClaw 要求，否则 gateway 无法启动）
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
    print("gateway.mode patched")
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

# =============================================================================
#  获取本机 IP（用于显示 Manager UI 地址）
# =============================================================================
GATEWAY_PORT=18789
# 优先用公网 IP，其次局域网 IP
SERVER_IP=""
# 尝试获取公网 IP（多个来源容错）
for ip_url in "https://api.ipify.org" "https://ip.sb" "https://ifconfig.me"; do
    SERVER_IP=$(curl -fsS --max-time 3 "$ip_url" 2>/dev/null | tr -d '[:space:]') && break || true
done
# 公网获取失败则用局域网 IP
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || SERVER_IP="你的服务器IP"
fi
MANAGER_URL="http://${SERVER_IP}:${GATEWAY_PORT}"

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
echo -e "  ${BOLD}🎯 接下来只需 2 步，就能开始聊天：${RESET}"
echo ""
echo -e "  ${BOLD}第 1 步${RESET}  打开飞书（或 Telegram），找到你的机器人，直接发消息就行"
echo -e "  ${BOLD}第 2 步${RESET}  没有更多步骤了，就这样 😄"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}🖥️  管理界面地址（用浏览器打开）：${RESET}"
echo ""
echo -e "    ${CYAN}${BOLD}  👉  ${MANAGER_URL}  ${RESET}"
echo ""
echo -e "  可以在这里查看运行状态、切换模型、管理频道"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# 恢复命令 —— 用红色背景高亮，明确告知"没问题不要动"
echo -e "  ${BG_RED}${BOLD}  ⚠️  以下是【恢复原状】命令，没问题请忽略，不要随手复制执行  ${RESET}"
echo ""
echo -e "  ${RED}${BOLD}  如果出了问题，才执行下面这条命令（粘贴到终端回车）：${RESET}"
echo ""
echo -e "  ${RED}  cp ~/.openclaw/openclaw.json.before-apimart ~/.openclaw/openclaw.json && openclaw gateway restart${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  有问题？联系 APIMart 技术支持：${CYAN}https://apimart.ai${RESET}"
echo ""
