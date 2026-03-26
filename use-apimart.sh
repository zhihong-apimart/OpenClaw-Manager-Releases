#!/usr/bin/env bash
# ============================================================
#  APIMart 一键接入脚本
#  将已安装的 OpenClaw 实例的模型配置替换为 APIMart 中转
#  用法:  bash use-apimart.sh [API_KEY]
# ============================================================
set -euo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------- 依赖检查（自动安装 jq）----------
if ! command -v jq &>/dev/null; then
  warn "未检测到 jq，尝试自动安装..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y jq -qq 2>/dev/null || apt-get install -y jq -qq 2>/dev/null
  elif command -v yum &>/dev/null; then
    sudo yum install -y jq -q 2>/dev/null || yum install -y jq -q 2>/dev/null
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y jq -q 2>/dev/null || dnf install -y jq -q 2>/dev/null
  elif command -v brew &>/dev/null; then
    brew install jq
  elif command -v apk &>/dev/null; then
    apk add --no-cache jq
  else
    err "无法自动安装 jq，请手动安装后重试: https://stedolan.github.io/jq/download/"
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    err "jq 安装失败，请手动安装: https://stedolan.github.io/jq/download/"
    exit 1
  fi
  ok "jq 已安装"
fi

# ---------- API Key ----------
API_KEY="${1:-}"
if [ -z "$API_KEY" ]; then
  read -rp "请输入 APIMart API Key: " API_KEY
fi
if [ -z "$API_KEY" ]; then
  err "API Key 不能为空"; exit 1
fi

# ---------- 节点选择 ----------
echo ""
echo "选择 APIMart 节点:"
echo "  1) 国际节点 (api.apimart.ai)  — 海外用户推荐"
echo "  2) 香港节点 (cn-api.apimart.ai) — 国内用户推荐"
read -rp "请选择 [1/2, 默认 2]: " NODE_CHOICE
case "${NODE_CHOICE:-2}" in
  1) HOST="api.apimart.ai" ;;
  *) HOST="cn-api.apimart.ai" ;;
esac
info "使用节点: $HOST"

# ---------- 构建 providers JSON (用 jq 安全注入变量，避免特殊字符破坏 JSON) ----------
PROVIDERS=$(jq -n \
  --arg host "$HOST" \
  --arg apiKey "$API_KEY" \
  '{
    "apimart": {
      "baseUrl": ("https://" + $host + "/v1"),
      "api": "openai-completions",
      "apiKey": $apiKey,
      "models": [
        {"id": "gpt-5.3-codex", "name": "GPT-5.3 Codex"},
        {"id": "gpt-5.3", "name": "GPT-5.3"},
        {"id": "gpt-5.2", "name": "GPT-5.2"},
        {"id": "gpt-5.1", "name": "GPT-5.1"},
        {"id": "gpt-5", "name": "GPT-5"},
        {"id": "deepseek-v3.2", "name": "DeepSeek V3.2"},
        {"id": "deepseek-v3-0324", "name": "DeepSeek V3-0324"},
        {"id": "deepseek-r1-0528", "name": "DeepSeek R1-0528"},
        {"id": "glm-5", "name": "GLM-5"},
        {"id": "kimi-k2.5", "name": "Kimi K2.5"},
        {"id": "minimax-m2.5", "name": "MiniMax M2.5"}
      ]
    },
    "apimart-claude": {
      "baseUrl": ("https://" + $host),
      "api": "anthropic-messages",
      "apiKey": $apiKey,
      "models": [
        {"id": "claude-opus-4-6", "name": "Claude Opus 4.6"},
        {"id": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6"},
        {"id": "claude-opus-4-5-20251101", "name": "Claude Opus 4.5"},
        {"id": "claude-sonnet-4-5-20250929", "name": "Claude Sonnet 4.5"},
        {"id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5"}
      ]
    },
    "apimart-gemini": {
      "baseUrl": ("https://" + $host + "/v1beta"),
      "api": "google-generative-ai",
      "apiKey": $apiKey,
      "models": [
        {"id": "gemini-2.5-pro", "name": "Gemini 2.5 Pro"},
        {"id": "gemini-2.5-flash", "name": "Gemini 2.5 Flash"},
        {"id": "gemini-3.1-flash-preview", "name": "Gemini 3.1 Flash Preview"},
        {"id": "gemini-3.1-pro-preview", "name": "Gemini 3.1 Pro Preview"}
      ]
    }
  }'
)

# ---------- 默认模型 ----------
echo ""
echo "选择默认模型:"
echo "  1) gpt-5.3          — OpenAI 最新"
echo "  2) claude-sonnet-4-6 — Claude 性价比之选"
echo "  3) deepseek-v3.2    — 国产高性价比"
echo "  4) gemini-2.5-pro   — Google 最强"
read -rp "请选择 [1-4, 默认 1]: " MODEL_CHOICE
case "${MODEL_CHOICE:-1}" in
  2) DEFAULT_MODEL="apimart-claude/claude-sonnet-4-6" ;;
  3) DEFAULT_MODEL="apimart/deepseek-v3.2" ;;
  4) DEFAULT_MODEL="apimart-gemini/gemini-2.5-pro" ;;
  *) DEFAULT_MODEL="apimart/gpt-5.3" ;;
esac
info "默认模型: $DEFAULT_MODEL"

# ---------- 查找 openclaw 配置 ----------
HOME_DIR="$HOME"
ALL_CONFIGS=()
ALL_NAMES=()

# 默认实例
if [ -f "$HOME_DIR/.openclaw/openclaw.json" ]; then
  ALL_CONFIGS+=("$HOME_DIR/.openclaw/openclaw.json")
  ALL_NAMES+=("default")
fi

# 命名实例 ~/.openclaw-{name}/openclaw.json
for d in "$HOME_DIR"/.openclaw-*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}openclaw.json" ]; then
    ALL_CONFIGS+=("${d}openclaw.json")
    name=$(basename "$d")
    name="${name#.openclaw-}"
    ALL_NAMES+=("$name")
  fi
done

if [ ${#ALL_CONFIGS[@]} -eq 0 ]; then
  err "未找到任何 OpenClaw 配置文件 (~/.openclaw/openclaw.json 或 ~/.openclaw-*/openclaw.json)"
  err "请确认已安装 OpenClaw"
  exit 1
fi

echo ""
info "找到 ${#ALL_CONFIGS[@]} 个实例:"
echo "  0) 全部替换"
for i in "${!ALL_NAMES[@]}"; do
  echo "  $((i+1))) ${ALL_NAMES[$i]}  — ${ALL_CONFIGS[$i]}"
done

read -rp "请选择要替换的实例 [0-${#ALL_CONFIGS[@]}, 默认 0]: " INST_CHOICE
INST_CHOICE="${INST_CHOICE:-0}"

CONFIGS=()
if [ "$INST_CHOICE" = "0" ]; then
  CONFIGS=("${ALL_CONFIGS[@]}")
elif [ "$INST_CHOICE" -ge 1 ] 2>/dev/null && [ "$INST_CHOICE" -le "${#ALL_CONFIGS[@]}" ]; then
  CONFIGS+=("${ALL_CONFIGS[$((INST_CHOICE-1))]}")
else
  err "无效选择"; exit 1
fi

echo ""
info "将替换以下配置:"
for c in "${CONFIGS[@]}"; do
  echo "    $c"
done

echo ""
read -rp "确认？[y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY] ]]; then
  info "已取消"; exit 0
fi

# ---------- 执行替换 ----------
UPDATED=0
for cfg in "${CONFIGS[@]}"; do
  # 备份
  cp "$cfg" "${cfg}.bak.$(date +%Y%m%d%H%M%S)"

  # 用 jq 替换 models.providers 和 agents.defaults.model.primary
  TEMP=$(mktemp)
  if jq --argjson providers "$PROVIDERS" \
     --arg model "$DEFAULT_MODEL" \
     '
     .models.providers = $providers
     | .agents.defaults.model.primary = $model
     ' "$cfg" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
    mv "$TEMP" "$cfg"
    ok "已更新: $cfg"
    UPDATED=$((UPDATED + 1))
  else
    rm -f "$TEMP"
    err "更新失败: $cfg (jq 处理出错，请检查文件是否为有效 JSON)"
  fi
done
echo ""
if [ "$UPDATED" -gt 0 ]; then
  ok "完成! 已更新 $UPDATED 个配置文件"
  echo ""
  warn "请重启 OpenClaw 使配置生效:"
  echo "    openclaw stop && openclaw start"
  echo ""
  info "备份文件保存在原目录 (.bak.* 后缀)，可随时恢复"
else
  err "没有配置被更新"
fi
