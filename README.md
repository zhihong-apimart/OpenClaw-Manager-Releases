# 🦞 OpenClaw Manager

OpenClaw Manager 是 [OpenClaw](https://github.com/open-claw/openclaw) AI 网关的可视化管理工具。一键部署、配置和管理多个 AI 聊天机器人实例，支持 Telegram、Discord、飞书等平台。

## 下载

从 [Releases](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest) 下载最新版本：

| 平台 | 架构 | 下载 |
|------|------|------|
| **Windows** | x64 | [openclaw-manager-win-x64.exe](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-win-x64.exe) |
| **macOS** | Apple Silicon (M1/M2/M3/M4) | [openclaw-manager-macos-arm64.zip](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-macos-arm64.zip) |
| **macOS** | Intel | [openclaw-manager-macos-x64.zip](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-macos-x64.zip) |
| **Linux** | x64 | [openclaw-manager-linux-x64](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-linux-x64) |
| **Linux** | ARM64 | [openclaw-manager-linux-arm64](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-linux-arm64) |

## 快速开始

### Windows

1. 下载 `openclaw-manager-win-x64.exe`
2. 右键 → **以管理员身份运行**，浏览器会自动打开管理页面
3. 按照向导创建你的第一个实例

### macOS

1. 下载对应架构的 `.zip` 文件
2. 解压得到 `OpenClaw Manager.app`，拖入 `/Applications`
3. 终端执行以下命令移除隔离属性：
   ```bash
   sudo xattr -rd com.apple.quarantine "/Applications/OpenClaw Manager.app"
   ```
4. 双击打开，浏览器会自动打开管理页面

### Linux

```bash
# 下载（以 x64 为例）
wget https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/releases/latest/download/openclaw-manager-linux-x64
chmod +x openclaw-manager-linux-x64

# 运行（自动后台运行）
./openclaw-manager-linux-x64

# 查看状态
./openclaw-manager-linux-x64 --status

# 停止
./openclaw-manager-linux-x64 --stop
```

管理页面地址：`http://<服务器IP>:51942`

## 功能特性

- **多平台支持** — Telegram、Discord、飞书一键对接
- **多模型切换** — 支持 GPT-5、Claude、Gemini 等主流模型，实时切换
- **模型降级** — 主模型不可用时自动切换备用模型
- **可视化管理** — Web UI 管理所有实例，启停、配置、日志一目了然
- **自动更新** — 内置 OTA 更新，一键升级到最新版本
- **多语言** — 中文 / English / 日本語
- **零依赖部署** — 单文件二进制，自动安装 Node.js 和 openclaw

## 前置条件

OpenClaw Manager 会在首次启动时**自动检测并安装**以下依赖：

- **Node.js 22+** — 如未安装会自动下载安装
- **openclaw CLI** — 通过 npm 自动安装，每次启动自动检查更新

## 支持的模型

通过 [APIMart](https://apimart.ai) 统一接入：

| 厂商 | 模型 |
|------|------|
| OpenAI | GPT-5、GPT-5.1、GPT-5.2 |
| Anthropic | Claude Opus 4.6、Claude Sonnet 4.6、Claude Opus 4.5、Claude Haiku 4.5 |
| Google | Gemini 3 Pro、Gemini 3 Flash、Gemini 2.5 Flash |

## 常用命令（Linux）

```bash
# 前台运行（不自动后台化）
./openclaw-manager-linux-x64 --foreground

# 后台运行
./openclaw-manager-linux-x64 --daemon

# 查看运行状态
./openclaw-manager-linux-x64 --status

# 停止服务
./openclaw-manager-linux-x64 --stop
```

## 问题反馈

如遇到问题，请提交 [Issue](https://github.com/zhihong-apimart/zhihong-apimart-OpenClaw-Manager-Releases/issues)。

## License

MIT
