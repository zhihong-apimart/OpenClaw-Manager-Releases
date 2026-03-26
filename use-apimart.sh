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
section() { echo -e "\n${CYAN}${BOLD}>>> $* ${RESET}"; }
step()    { echo -e "    ${BOLD}...${RESET} $*"; }

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
#  Step 1: 安装依赖 jq（自动处理，无需手动）
# =============================================================================
section "Step 1/4  检查依赖环境"

if ! command -v jq &>/dev/null; then
    step "正在自动安装 jq（JSON 处理工具）..."
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y -qq -o Dpkg::Use-Pty=0 jq 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y -q jq 2>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y -q jq 2>/dev/null
    elif command -v zypper &>/dev/null; then
        zypper install -y -q jq 2>/dev/null
    elif command -v apk &>/dev/null; then
        apk add -q jq 2>/dev/null
    elif command -v brew &>/dev/null; then
        brew install jq -q 2>/dev/null
    else
        error "无法自动安装 jq，请手动执行: sudo apt install jq  或  brew install jq"
    fi
    command -v jq &>/dev/null || error "jq 安装失败，请联系技术支持"
fi
info "jq 就绪 ✓"

if ! command -v openclaw &>/dev/null; then
    error "未检测到 OpenClaw，请先安装: curl -fsSL https://openclaw.ai/install.sh | bash"
fi
info "OpenClaw $(openclaw --version 2>/dev/null || echo '已安装') ✓"

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
info "API Key 已获取 ✓"

# =============================================================================
#  Step 3: 选择节点和模型
# =============================================================================
section "Step 3/4  配置节点与模型"

echo ""
echo -e "  ${BOLD}选择 APIMart 节点：${RESET}"
echo "    1) 国际节点  ← 海外服务器 / 国际用户"
echo "    2) 香港节点  ← 国内用户 / 国内服务器"
echo ""
read -rp "  请输入选项 [1/2，直接回车默认国际节点]: " NODE_CHOICE
case "${NODE_CHOICE:-1}" in
    2) HOST="cn-api.apimart.ai" ; NODE_NAME="香港节点" ;;
    *) HOST="api.apimart.ai"    ; NODE_NAME="国际节点" ;;
esac
info "已选: ${NODE_NAME} ✓"

echo ""
echo -e "  ${BOLD}选择默认对话模型：${RESET}"
echo "    1) GPT-5.3            — OpenAI 旗舰，最强综合能力"
echo "    2) Claude Sonnet 4.6  — Anthropic Claude，擅长写作/分析"
echo "    3) DeepSeek V3.2      — 国产精品，高性价比"
echo "    4) Gemini 2.5 Pro     — Google 最新旗舰"
echo ""
read -rp "  请输入选项 [1-4，直接回车默认 GPT-5.3]: " MODEL_CHOICE
case "${MODEL_CHOICE:-1}" in
    2) DEFAULT_MODEL="apimart-claude/claude-sonnet-4-6" ; MODEL_NAME="Claude Sonnet 4.6" ;;
    3) DEFAULT_MODEL="apimart/deepseek-v3.2"            ; MODEL_NAME="DeepSeek V3.2" ;;
    4) DEFAULT_MODEL="apimart-gemini/gemini-2.5-pro"    ; MODEL_NAME="Gemini 2.5 Pro" ;;
    *) DEFAULT_MODEL="apimart/gpt-5.3"                  ; MODEL_NAME="GPT-5.3" ;;
esac
info "已选: ${MODEL_NAME} ✓"

# =============================================================================
#  构建 providers JSON
# =============================================================================
PROVIDERS=$(jq -n \
  --arg host "$HOST" \
  --arg apiKey "$API_KEY" \
  '{
    "apimart": {
      "baseUrl": ("https://" + $host + "/v1"),
      "api": "openai-completions",
      "apiKey": $apiKey,
      "models": [
        {"id": "gpt-5.3-codex",  "name": "GPT-5.3 Codex"},
        {"id": "gpt-5.3",        "name": "GPT-5.3"},
        {"id": "gpt-5.2",        "name": "GPT-5.2"},
        {"id": "gpt-5.1",        "name": "GPT-5.1"},
        {"id": "gpt-5",          "name": "GPT-5"},
        {"id": "deepseek-v3.2",  "name": "DeepSeek V3.2"},
        {"id": "deepseek-v3-0324","name": "DeepSeek V3-0324"},
        {"id": "deepseek-r1-0528","name": "DeepSeek R1-0528"},
        {"id": "glm-5",          "name": "GLM-5"},
        {"id": "kimi-k2.5",      "name": "Kimi K2.5"},
        {"id": "minimax-m2.5",   "name": "MiniMax M2.5"}
      ]
    },
    "apimart-claude": {
      "baseUrl": ("https://" + $host),
      "api": "anthropic-messages",
      "apiKey": $apiKey,
      "models": [
        {"id": "claude-opus-4-6",          "name": "Claude Opus 4.6"},
        {"id": "claude-sonnet-4-6",        "name": "Claude Sonnet 4.6"},
        {"id": "claude-opus-4-5-20251101", "name": "Claude Opus 4.5"},
        {"id": "claude-sonnet-4-5-20250929","name": "Claude Sonnet 4.5"},
        {"id": "claude-haiku-4-5-20251001","name": "Claude Haiku 4.5"}
      ]
    },
    "apimart-gemini": {
      "baseUrl": ("https://" + $host + "/v1beta"),
      "api": "google-generative-ai",
      "apiKey": $apiKey,
      "models": [
        {"id": "gemini-2.5-pro",           "name": "Gemini 2.5 Pro"},
        {"id": "gemini-2.5-flash",         "name": "Gemini 2.5 Flash"},
        {"id": "gemini-3.1-flash-preview", "name": "Gemini 3.1 Flash Preview"},
        {"id": "gemini-3.1-pro-preview",   "name": "Gemini 3.1 Pro Preview"}
      ]
    }
  }')

# =============================================================================
#  Step 4: 写入配置并重启
# =============================================================================
section "Step 4/4  写入配置并重启 OpenClaw"

HOME_DIR="$HOME"
ALL_CONFIGS=()

if [ -f "$HOME_DIR/.openclaw/openclaw.json" ]; then
    ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
fi
for d in "$HOME_DIR"/.openclaw-*/; do
    [ -d "$d" ] || continue
    [ -f "${d}openclaw.json" ] && ALL_CONFIGS+=("${d}openclaw.json")
done

# 没有配置则自动创建
if [ ${#ALL_CONFIGS[@]} -eq 0 ]; then
    step "未找到 OpenClaw 配置，自动初始化..."
    mkdir -p "$HOME_DIR/.openclaw"
    echo '{"models":{},"agents":{"defaults":{"model":{"primary":""}}}}' \
        > "$HOME_DIR/.openclaw/openclaw.json"
    ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
    info "配置目录已创建 ✓"
fi

# 写入配置（备份用固定名称，恢复命令始终一致）
UPDATED=0
for cfg in "${ALL_CONFIGS[@]}"; do
    cp "$cfg" "${cfg}.before-apimart" 2>/dev/null || true
    TEMP=$(mktemp)
    if jq --argjson providers "$PROVIDERS" \
          --arg model "$DEFAULT_MODEL" \
          '.models.providers = $providers | .agents.defaults.model.primary = $model' \
          "$cfg" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
        mv "$TEMP" "$cfg"
        info "配置已更新 ✓"
        UPDATED=$((UPDATED + 1))
    else
        rm -f "$TEMP"
        warn "更新失败: $cfg（文件格式异常，已跳过）"
    fi
done

[ "$UPDATED" -eq 0 ] && error "没有配置被更新，请检查 OpenClaw 是否正确安装"

# 自动重启 gateway
step "正在重启 OpenClaw Gateway..."
if openclaw gateway restart &>/dev/null 2>&1; then
    sleep 2
    info "OpenClaw Gateway 已重启 ✓"
elif openclaw gateway start &>/dev/null 2>&1; then
    sleep 2
    info "OpenClaw Gateway 已启动 ✓"
else
    warn "Gateway 未能自动重启，请手动执行: openclaw gateway restart"
fi

# =============================================================================
#  完成
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║                                                      ║"
echo "  ║      🎉  接入成功！刷新 OpenClaw 即可使用            ║"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  已接入模型：${BOLD}GPT / Claude / Gemini / DeepSeek${RESET} 等"
echo -e "  默认模型：  ${CYAN}${BOLD}${MODEL_NAME}${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🆘 遇到问题？复制以下命令处理${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}模型列表没更新 / 连不上？重启 OpenClaw：${RESET}"
echo -e "  ${CYAN}openclaw gateway restart${RESET}"
echo ""
echo -e "  ${BOLD}出问题想恢复到接入前的状态：${RESET}"
echo -e "  ${CYAN}cp ~/.openclaw/openclaw.json.before-apimart ~/.openclaw/openclaw.json && openclaw gateway restart${RESET}"
echo ""
