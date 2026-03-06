#!/usr/bin/env bash
# =============================================================================
#  OpenClaw Manager — 一键卸载脚本
#  用法: curl -fsSL https://raw.githubusercontent.com/zhihong-apimart/OpenClaw-Manager-Releases/main/uninstall.sh | sudo bash
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }

[[ $EUID -ne 0 ]] && { echo -e "${RED}[✗]${RESET} 请使用 sudo 或 root 用户运行此脚本。" >&2; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║    OpenClaw Manager — 卸载程序               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""

SERVICE_NAME="openclaw-manager"
INSTALL_DIR="/opt/openclaw-manager"
LOG_FILE="/var/log/openclaw-manager.log"
PIDFILE="/var/run/openclaw-manager.pid"

# 停止并禁用服务
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME" && info "服务已停止"
fi
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME" --quiet && info "服务已禁用（开机不再自启）"
fi
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
info "systemd unit 已删除"

# Kill 残留进程
pkill -f "openclaw-manager" 2>/dev/null && info "残留进程已清理" || true
rm -f "$PIDFILE"

# 删除程序目录（保留日志，除非用户确认）
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    info "程序目录已删除: $INSTALL_DIR"
fi

echo ""
echo -e "${BOLD}${GREEN}✅  OpenClaw Manager 已卸载完成。${RESET}"
echo ""
warn "日志文件已保留（如需删除：sudo rm -f ${LOG_FILE}）"
echo ""
