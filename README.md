# ShellDeck

[![Platform](https://img.shields.io/badge/macOS-26.4%2B-111111?style=flat-square&logo=apple)](https://developer.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?style=flat-square&logo=swift)](https://developer.apple.com/swift)
[![Build](https://img.shields.io/badge/Build-XcodeCodeGen-0A84FF?style=flat-square)](https://developer.apple.com/xcode)
[![Version](https://img.shields.io/github/v/release/begitcn/ShellDeck?style=flat-square&logo=github)](https://github.com/begitcn/ShellDeck/releases)
[![Stars](https://img.shields.io/github/stars/begitcn/ShellDeck?style=flat-square&logo=github)](https://github.com/begitcn/ShellDeck/stargazers)

macOS 原生 SSH 管理工具 — 终端、文件管理、系统监控，三合一。

> 本项目是一个纯 AI Vibe Coding 产物，全部代码由 AI 生成，未经人工审查。项目在需求梳理、架构设计、功能实现、文档维护等环节全程与 AI 协作。

---

## 功能

| 功能 | 说明 |
|---|---|
| **SSH 终端** | 基于 SwiftTerm 的终端模拟器，支持多会话、复制粘贴、主题切换 |
| **SFTP 文件管理** | 远程文件浏览、上传下载、拖拽传输、进度追踪 |
| **系统监控** | 实时 CPU / 内存 / 磁盘 / 网络指标监控（图表展示） |
| **本地终端** | 内置本地 macOS 终端，支持多标签页 |
| **服务器管理** | SwiftData 持久化存储服务器列表，Keychain 凭证安全存储 |
| **信息面板** | 快速查看已保存的服务器配置详情 |
| **快捷切换** | Command + 数字键快速在服务器间跳转 |

## 键盘快捷键

> 快捷键是 ShellDeck 的核心效率工具，以下为全局可用快捷键：

| 快捷键 | 作用 |
|---|---|
| **⌘ + `** | 在侧边栏的 SSH / 本地终端模式间切换 |
| **⌘ + 1 ~ 9** | 按索引选择侧边栏第 1–9 项（本地终端或 SSH 服务器） |
| **⌘ + F** | 切换到当前选中 SSH 服务器的文件管理器（SFTP）标签页 |
| **⌘ + T** | 本地模式下新建终端标签页；SSH 模式下切换到终端标签页 |

## 截图

（待补充）

---

## 系统要求

- macOS 26.4 及以上
- Apple Silicon (arm64) 或 Intel (x86_64)

## 安装

### Homebrew（推荐）

```bash
brew tap begitcn/homebrew-tap
brew install --cask shelldeck
```

### DMG

从 [GitHub Releases](https://github.com/begitcn/ShellDeck/releases) 下载 `.dmg` 文件，挂载后将 `ShellDeck.app` 拖入 `/Applications`。

### 本地构建

```bash
git clone https://github.com/begitcn/ShellDeck.git
cd ShellDeck
bash build-release.sh
# 产物在 dist/ 目录
```

### 首次打开问题

由于 GitHub Actions 构建版本未经 Apple 公证，macOS 可能拦截。请按以下顺序尝试：

1. **系统提示"无法验证开发者"**：打开 **系统设置 → 隐私与安全性**，点击「仍要打开」。
2. **提示"已损坏"**：终端执行 `sudo xattr -dr com.apple.quarantine /Applications/ShellDeck.app`

## 卸载

```bash
# 退出应用
killall ShellDeck 2>/dev/null

# 删除应用与数据
rm -rf /Applications/ShellDeck.app
rm -rf ~/Library/Application\ Support/com.chaogeek.ShellDeck/
rm -rf ~/Library/Caches/com.chaogeek.ShellDeck/
rm -rf ~/Library/Preferences/com.chaogeek.ShellDeck.plist
```

Homebrew 安装用户先执行 `brew uninstall --cask shelldeck`，再参照上方清理残余文件。

## 架构

### 进程模型

```
ShellDeck.app          (用户态, GUI)
    │
    ├── SSHService         (SSH 连接与会话生命周期管理)
    ├── SFTPService        (SFTP 文件传输)
    ├── MonitorService     (定期拉取系统指标)
    └── LocalTerminalManager (本地终端多标签管理)
```

- **SSHService**：基于 SSHClient（Citadel/swift-nio-ssh）实现异步 SSH 连接、远程终端会话与命令执行
- **SFTPService**：基于 SSHClient SFTP 模块实现远程文件浏览、上传、下载
- **MonitorService**：通过 SSH 远程执行系统命令采集 CPU、内存、磁盘、网络等指标
- **LocalTerminalManager**：基于 SwiftTerm `LocalProcessTerminalView` 的本地终端多标签管理

### 技术栈

- **前端**：SwiftUI + AppKit（NavigationSplitView 布局，NSViewRepresentable 桥接终端）
- **SSH**：SSHClient v0.1.4（基于 Citadel / swift-nio-ssh / swift-nio / swift-crypto）
- **终端**：SwiftTerm（终端模拟）
- **持久化**：SwiftData（服务器列表） + Keychain（凭证安全存储）
- **图表**：Swift Charts（系统监控）
- **构建**：Xcode 26.5 项目，无外部依赖管理工具

### 数据目录

| 路径 | 说明 |
|---|---|
| `~/Library/Application Support/com.chaogeek.ShellDeck/` | SwiftData 持久化存储 |
| `~/Library/Keychains/` | SSH 凭证（通过 KeychainHelper 写入系统 Keychain） |

## 开发

```bash
# 克隆并打开
open ShellDeck.xcodeproj

# 或命令行构建
xcodebuild -project ShellDeck.xcodeproj -scheme ShellDeck -configuration Release build
```

项目使用 Xcode 26.5 原生项目（非 XcodeGen / SPM 项目），直接打开 `.xcodeproj` 即可开发。

## 致谢

- [SSHClient](https://github.com/glm4/SSHClient) — Swift SSH/SFTP 客户端库
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — 终端模拟器引擎
- [Citadel](https://github.com/nickname22/Citadel) — 底层 Swift-NIO SSH 实现
