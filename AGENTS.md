# ShellDeck — macOS 原生 SSH 管理工具

## 构建
Xcode 26.5 项目（非 SPM），用 Xcode 打开 `ShellDeck.xcodeproj` 或：
```
xcodebuild -project ShellDeck.xcodeproj -scheme ShellDeck
```

## 目录布局
```
ShellDeck/
├── App/
│   ├── ShellDeckApp.swift            # 应用入口，SwiftData 容器初始化
│   └── Entitlements.entitlements     # 沙箱 + 网络权限
├── Models/
│   └── Server.swift                  # SwiftData 模型（仅非敏感字段）
├── Services/
│   ├── SSHService.swift              # SSH 连接与会话生命周期
│   ├── SFTPService.swift             # SFTP 文件读写
│   └── MonitorService.swift          # 定期拉取系统指标
├── Views/
│   ├── Sidebar/ServerSidebarView.swift
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift  # NSViewRepresentable 桥接 SwiftTerm
│   │   └── TerminalViewModel.swift
│   ├── FileManager/
│   │   ├── FileListView.swift
│   │   └── FileRowView.swift
│   └── Dashboard/SystemMonitorView.swift
├── Helpers/
│   ├── KeychainHelper.swift          # macOS Keychain 封装
│   └── Extensions.swift
└── ContentView.swift                 # NavigationSplitView 根布局
```

## 代码约定
- **状态管理**：Service/Observable 用 `@Observable` 宏，不用 `ObservableObject`/`@Published`。SwiftData `@Query` 直接在 View 层使用。
- **并发**：所有 I/O 用 `async/await`。更新 UI 属性需在 `@MainActor` 上执行。
- **错误处理**：Service 层 `throw` 自定义错误。View 层 `do-catch` → `@State errorMessage` → `.alert()`，禁止静默失败。

## 依赖
- `SSHClient`（已集成，v0.1.4）→ 底层 swift-nio-ssh / swift-nio / swift-crypto
- `SwiftTerm`（需添加 SPM 依赖）→ 终端模拟
- `SwiftData` / `Swift Charts`（内建）

## 安全与沙箱
- **敏感凭证**：密码/私钥通过 `KeychainHelper` 写入系统 Keychain（以 `Server.id.uuidString` 为 key）。Server 模型**只存**非敏感字段。连接时从 Keychain 读取，断开时销毁内存副本。
- **沙箱权限**：当前 `com.apple.security.app-sandbox` + `com.apple.security.files.user-selected.read-only` + `com.apple.security.network.client`（entitlements 文件：`ShellDeck/App/Entitlements.entitlements`）。
- **SFTP 下载**：用 `NSSavePanel` 让用户选保存路径（自动获取临时写入权），或写入 `FileManager.default.temporaryDirectory`。
