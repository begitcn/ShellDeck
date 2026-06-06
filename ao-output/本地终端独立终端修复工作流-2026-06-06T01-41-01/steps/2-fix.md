> 🔧 **终端修复专家** | 步骤 2/3 | 25.9s

---

**核心修复：确保每个终端标签拥有独立的 PTY 进程，避免复用**  

```diff
- // ❌ 错误的全局单例 PTY
- class TerminalService {
-   private ptyProcess = pty.spawn('bash', [], {});
-   attach(terminalView) { /* 所有视图共享同一进程 */ }
- }

+ // ✅ 修复：每个标签独立 PTY，ID 隔离，生命周期管理
+ import * as pty from 'node-pty';
+ import { v4 as uuidv4 } from 'uuid';
+
+ class TerminalManager {
+   private terminals = new Map<string, pty.IPty>();
+
+   createTerminal(cols = 80, rows = 24): string {
+     const id = uuidv4();
+     const shell = process.env.SHELL || 'bash';
+     // 1️⃣ 独立的伪终端（PTY 隔离）
+     const ptyProcess = pty.spawn(shell, [], {
+       name: 'xterm-color',
+       cols,
+       rows,
+       cwd: process.env.HOME,
+       env: { ...process.env }  // 环境变量副本隔离
+     });
+
+     this.terminals.set(id, ptyProcess);
+
+     // 数据路由到对应的前端 Terminal（通过 socket 等）
+     ptyProcess.on('data', (data) => {
+       sendToTerminalUI(id, data);   // 仅发送给对应 ID 的视图
+     });
+
+     ptyProcess.on('exit', () => {
+       this.terminals.delete(id);
+       notifyTerminalClosed(id);
+     });
+
+     return id;
+   }
+
+   // 2️⃣ 进程 ID 绑定：写入/调整大小/销毁均按 ID 操作
+   write(terminalId: string, data: string): void {
+     this.terminals.get(terminalId)?.write(data);
+   }
+
+   resize(terminalId: string, cols: number, rows: number): void {
+     this.terminals.get(terminalId)?.resize(cols, rows);
+   }
+
+   // 3️⃣ 销毁时强制 kill 进程，释放 PTY
+   destroyTerminal(terminalId: string): void {
+     const proc = this.terminals.get(terminalId);
+     if (proc) {
+       proc.kill();
+       this.terminals.delete(terminalId);
+     }
+   }
+ }
+
+ // 前端：每个标签创建独立的 xterm.js Terminal 实例
+ class TerminalTab {
+   id: string;
+   terminal: Terminal;
+
+   constructor(container: HTMLElement) {
+     this.terminal = new Terminal();
+     this.terminal.open(container);
+     // 通过 socket 请求后端创建独立 PTY
+     socket.emit('create', {}, (res: { id: string }) => {
+       this.id = res.id;
+       // 数据流严格按 ID 绑定
+       socket.on('data', (msg) => msg.id === this.id && this.terminal.write(msg.data));
+       this.terminal.onData((data) => socket.emit('write', { id: this.id, data }));
+     });
+   }
+
+   close() {
+     socket.emit('destroy', { id: this.id });
+     this.terminal.dispose();
+   }
+ }
```

**关键改动**：  
1. 🔒 **独立的 PTY 创建** – 每次 `createTerminal` 生成新的 `pty.spawn`，杜绝全局共享。  
2. 🆔 **ID 严格映射** – 每个终端唯一 ID，数据只路由到对应前端视图。  
3. 🧹 **生命周期管理** – `destroyTerminal` 显式 `kill` 进程，关闭事件自动清理 Map，避免僵尸进程。  

此模式与 VS Code 终端实现一致，确保多标签完全隔离。