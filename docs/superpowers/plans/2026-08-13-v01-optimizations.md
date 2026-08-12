# Oh My Servers v0.1 全量优化实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 按已批准顺序落地采集复用、SSH 硬超时、刷新状态、负载按核着色、内存/磁盘用量、设置页体验、开机自启、可调间隔、唤醒立采、进度条、终端打开与 Dock 图标。

**架构：** Core 改为「单次 `/proc` 采样 + 跨轮询差分」。`ProcessSSHCollector` 缓存上一份 `MetricSample`，SSH 使用 `ControlMaster` 复用连接，并对整段进程加硬超时。App 层补刷新状态、设置偏好与 Graphite UI。

**技术栈：** Swift 5.9+ / SwiftUI / macOS 14+、`/usr/bin/ssh`、ServiceManagement（开机自启）、XCTest。

**工作目录：** `仓库根目录`  
**分支：** `feat/v01-optimizations`  
**不要做：** 历史曲线、可配置阈值告警、Docker/GPU、跳板机、内置终端。不要 push。

---

## 文件结构

| 路径 | 职责 |
|------|------|
| `Sources/OhMyServersCore/Parser/MetricsParser.swift` | `MetricSample`；跨样本解析 CPU/网速；磁盘字节；nproc |
| `Sources/OhMyServersCore/Models/MetricsSnapshot.swift` | 增加 `cpuCount`、`diskUsedBytes`、`diskTotalBytes`；负载参与 health |
| `Sources/OhMyServersCore/SSH/RemoteMetricScripts.swift` | 单次采样脚本 + 首次配对脚本 |
| `Sources/OhMyServersCore/SSH/ProcessSSHCollector.swift` | 样本缓存、ControlMaster、硬超时 |
| `Sources/OhMyServersCore/SSH/SSHErrorLocalizer.swift` | SSH 错误中文 |
| `Sources/OhMyServersCore/Monitor/PollScheduler.swift` | 壁钟间隔、刷新中状态、禁止重叠 |
| `Sources/OhMyServers/Services/AppModel.swift` | isRefreshing、间隔、唤醒、终端、开机自启 |
| `Sources/OhMyServers/Views/MenuBarRootView.swift` | 更新时间、转圈、用量、进度条、终端 |
| `Sources/OhMyServers/Views/SettingsView.swift` | 草稿列表、删除确认、间隔、开机自启 |
| `Sources/OhMyServers/Services/LaunchAtLogin.swift` | SMAppService 封装 |
| `Sources/OhMyServers/Theme/Graphite.swift` | 新增 L10n 文案 |
| `Sources/OhMyServers/Info.plist` + `Scripts/run-app.sh` | 图标打包 |
| `Tests/OhMyServersCoreTests/*` | 对应单元测试 |

---

### 任务 1：跨轮询差分、单次采样、ControlMaster、硬超时、中文错误

**文件：**
- 修改：`Sources/OhMyServersCore/Parser/MetricsParser.swift`
- 修改：`Sources/OhMyServersCore/Models/MetricsSnapshot.swift`
- 修改：`Sources/OhMyServersCore/SSH/RemoteMetricScripts.swift`
- 修改：`Sources/OhMyServersCore/SSH/ProcessSSHCollector.swift`
- 修改：`Sources/OhMyServersCore/Monitor/PollScheduler.swift`（仅 Missing credentials 文案）
- 创建：`Sources/OhMyServersCore/SSH/SSHErrorLocalizer.swift`
- 修改：`Tests/OhMyServersCoreTests/MetricsParserTests.swift`
- 修改：`Tests/OhMyServersCoreTests/RemoteMetricScriptsTests.swift`
- 修改：`Tests/OhMyServersCoreTests/ModelSmokeTests.swift`
- 创建：`Tests/OhMyServersCoreTests/SSHErrorLocalizerTests.swift`

**API 约定（必须遵守）：**

用 `MetricSample` 替换 `RemoteMetricRaw`：

```swift
public struct MetricSample: Sendable, Equatable {
    public var procStat: String
    public var procMeminfo: String
    public var procLoadavg: String
    public var procUptime: String
    public var procNetDev: String
    public var df: String
    public var nprocText: String
    public var sampledAt: Date
}
```

```swift
public enum MetricsParser {
    public static func parse(
        serverID: UUID,
        current: MetricSample,
        previous: MetricSample?,
        intervalSeconds: Double? = nil
    ) -> MetricsSnapshot
}
```

- `previous == nil` 且未传入 `intervalSeconds`：`cpuPercent`、`netRxBytesPerSec`、`netTxBytesPerSec` 为 `nil`，其余字段照常。
- 有 previous：间隔 = `intervalSeconds ?? current.sampledAt.timeIntervalSince(previous.sampledAt)`；间隔 `<= 0` 则 CPU/网速为 nil。
- 磁盘：从 `df -Pk` 根分区解析 `diskUsedPercent`、`diskUsedBytes`、`diskTotalBytes`（1024-blocks × 1024）。
- `cpuCount`：解析 `nprocText` 第一个整数。
- 现有 `cpuTimes` / `memory` / `loadAverage` / `uptime` / `primaryInterfaceCounters` 逻辑保持，只是输入从双样本改成 current+previous。

`MetricsSnapshot` 增加：

```swift
public var cpuCount: Int?
public var diskUsedBytes: UInt64?
public var diskTotalBytes: UInt64?
```

`health`：不可达 → offline；CPU≥85 或 内存≥90 或 磁盘≥90 或（`cpuCount != nil && cpuCount > 0 && load1 >= Double(cpuCount)`）→ high；否则 online。

远端脚本：

`collectCommand`（稳态，无 sleep）：

```
set -e
echo '___PROC_STAT___'
cat /proc/stat
echo '___PROC_NET_DEV___'
cat /proc/net/dev
echo '___PROC_MEMINFO___'
cat /proc/meminfo
echo '___PROC_LOADAVG___'
cat /proc/loadavg
echo '___PROC_UPTIME___'
cat /proc/uptime
echo '___DF___'
df -Pk /
echo '___NPROC___'
nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
echo '___END___'
```

`collectCommandInitial`：在 NET 第一次之后 `sleep 1`，再采 STAT/NET 第二次（区块名 `PROC_STAT_1/2`、`PROC_NET_DEV_1/2`），其余同稳态。用于该 server 缓存为空的第一次采集，保证首屏就有 CPU/网速。

`parseSections(_: ) -> MetricSample?`  
`parseInitialSections(_: ) -> (MetricSample, MetricSample)?` —— 两个 sample 的 `sampledAt` 可同为 `Date()`，调用方传 `intervalSeconds: 1`。

`ProcessSSHCollector` 改为 `final class`（`@unchecked Sendable`），内部 `NSLock` 保护 `[UUID: MetricSample]` 缓存：

- 无缓存：跑 `collectCommandInitial`，`parse(current: sample2, previous: sample1, intervalSeconds: 1)`，缓存 sample2。
- 有缓存：跑 `collectCommand`，用实际时间差 parse，缓存 current。
- SSH 参数增加：
  - `-o ControlMaster=auto`
  - `-o ControlPath=/tmp/ohmyservers-%C`
  - `-o ControlPersist=120`
  - `-o ServerAliveInterval=5`
  - `-o ServerAliveCountMax=2`
- 整段硬超时：`overallTimeoutSeconds` 默认 15。`process.run()` 后用 `DispatchGroup.wait(timeout:)`；超时则 `terminate()`，0.2s 后若仍在运行则 `kill(pid, SIGKILL)`，抛出本地化「连接超时」。
- 所有失败消息经 `SSHErrorLocalizer.message(from:)`。
- `PollScheduler` 缺凭据消息改为 `"缺少登录凭据"`。

`SSHErrorLocalizer` 映射（大小写不敏感）：

| 包含 | 中文 |
|------|------|
| permission denied | 认证失败，请检查密码或密钥 |
| timed out / timeout / 连接超时 | 连接超时 |
| connection refused | 连接被拒绝 |
| could not resolve / nodename nor servname | 无法解析主机名 |
| network is unreachable | 网络不可达 |
| no such file / identity | 找不到私钥文件 |
| missing credentials / 缺少登录凭据 | 缺少登录凭据 |
| 其他 | `SSH 失败：原文本`（截断到 160 字符） |

- [ ] **步骤 1：先写失败测试（TDD）**

`MetricsParserTests`：
1. 用现有 fixture：`previous = sample(stat1, net1)`，`current = sample(stat2, net2)`，`intervalSeconds: 1` → CPU ≈ 65.625，net rx 5000、tx 10000（与现在相同）。
2. `previous: nil` → cpu/net 为 nil，load/mem/uptime 仍有值。
3. df fixture → `diskUsedBytes == 22528000 * 1024`，`diskTotalBytes == 51200000 * 1024`。
4. `nprocText: "4\n"` → `cpuCount == 4`。

`ModelSmokeTests`：`load1: 4, cpuCount: 2, cpuPercent: 10` → health `.high`；`load1: 0.5, cpuCount: 2` → `.online`。

`RemoteMetricScriptsTests`：稳态脚本输出（单段 STAT/NET + NPROC）能 parse；初始脚本双段能 parseInitialSections。

`SSHErrorLocalizerTests`：上表每条至少一例。

- [ ] **步骤 2：运行测试确认失败**  
`swift test --filter MetricsParserTests --filter ModelSmokeTests --filter RemoteMetricScriptsTests --filter SSHErrorLocalizerTests`

- [ ] **步骤 3：实现最少代码让测试通过，并改 collector**  
更新所有 `RemoteMetricRaw` 引用。不要改 UI。

- [ ] **步骤 4：`swift test` 全绿**

- [ ] **步骤 5：Commit**

```
feat: sample metrics across polls with ssh reuse and timeout
```

---

### 任务 2：壁钟轮询间隔、isRefreshing、唤醒立采

**文件：**
- 修改：`Sources/OhMyServersCore/Monitor/PollScheduler.swift`
- 修改：`Tests/OhMyServersCoreTests/PollSchedulerTests.swift`
- 修改：`Sources/OhMyServers/Services/AppModel.swift`
- 修改：`Sources/OhMyServers/OhMyServersApp.swift`（若在此注册唤醒观察者也可以，优先放 AppModel）

**行为：**

1. 间隔是**壁钟**：一轮 `pollOnce` 结束后，只 sleep `max(0, interval - elapsed)`。不再是「采集完再固定睡 15 秒」。
2. `start` 增加 `onRefreshing: (@Sendable (Bool) -> Void)? = nil`。每次 `pollOnce` 前 `true`，结束后（无论成功失败）`false`。
3. 禁止重叠：`pollOnce` 进行中再次调用（含 `refresh`）直接 return。
4. `intervalNanoseconds` 可在运行中更新（`setIntervalSeconds`），下一轮生效。
5. AppModel：`@Published var isRefreshing = false`；`onRefreshing` 切回 MainActor 赋值。
6. AppModel 监听 `NSWorkspace.didWakeNotification`，唤醒后 `refreshNow()`。
7. 本任务**不要**做间隔设置 UI（任务 4）。间隔仍默认 15。可先加 `pollIntervalSeconds` 属性，供任务 4 绑定。

- [ ] **步骤 1：测试**  
- 慢 collector（sleep 0.3s）+ interval 0.4s：两次 onUpdate 的间隔应 < 0.7s（证明不是 0.3+0.4）。  
- 重叠：collector 卡住 0.4s 时连续 `refresh` 两次，collector 调用次数为 1。  
- isRefreshing：start 后先收到 true 再收到 finished。

用 mock collector 记录调用次数与时间。

- [ ] **步骤 2：确认失败 → 实现 → `swift test` → commit**

```
feat: use wall-clock poll interval and expose refresh state
```

---

### 任务 3：菜单栏 UI

**文件：**
- 修改：`Sources/OhMyServers/Views/MenuBarRootView.swift`
- 修改：`Sources/OhMyServers/Theme/Graphite.swift`（L10n）
- 修改：`Sources/OhMyServers/Services/AppModel.swift`（`openInTerminal`）
- 可选创建：`Sources/OhMyServers/Views/MetricFormatters.swift`

**行为（Graphite 风格，中文，宽度仍约 320）：**

1. 顶栏右侧或底栏显示相对时间：`刚刚` / `N秒前` / `N分钟前`。用 `TimelineView(.periodic(from: .now, by: 1))`。无快照时不显示。
2. `isRefreshing` 时顶栏或刷新按钮旁显示小 `ProgressView`；「刷新」按钮 disabled。
3. 内存：`3.2 / 8.0 GB`（`memoryUsedBytes` / `memoryTotalBytes`）。不足 1GB 用 MB。无字节时回退百分比。
4. 磁盘：同样 `已用 / 总量`，无字节时回退百分比。
5. CPU / 内存 / 磁盘各自一条高度 3pt 的圆角进度条（Graphite.accent 或按阈值变 high/offline 色），无数据则空条。
6. 负载：显示 `1.23 / 0.80 / 0.50`；数值颜色：`cpuCount` 已知时，`load1/cpuCount >= 1` 用 `Graphite.high`，`>= 1.5` 用 `Graphite.offline`，否则 `Graphite.text`。无核数则 `Graphite.text`。
7. 每台服务器标题行右侧加「终端」文字按钮，调用 `AppModel.openInTerminal(server:)`：用 `NSAppleScript` 让 Terminal 执行 `ssh [-p port] [-i key] user@host`。路径/主机中的引号要转义。不要做内置终端。
8. 错误文案直接显示 snapshot.errorMessage（此时已是中文）。

格式化规则：
- GB：`value / 1_073_741_824`，一位小数
- MB：`value / 1_048_576`，一位小数
- 相对时间：`< 5s` → `刚刚`；`< 60s` → `N秒前`；否则 `N分钟前`

- [ ] **步骤 1：实现 UI + `openInTerminal`**
- [ ] **步骤 2：`swift test` 仍全绿（UI 无单测要求）**
- [ ] **步骤 3：Commit**

```
feat: show freshness, usage totals, load color, and terminal open
```

---

### 任务 4：设置页、刷新间隔、开机自启、图标、README

**文件：**
- 修改：`Sources/OhMyServers/Views/SettingsView.swift`
- 创建：`Sources/OhMyServers/Services/LaunchAtLogin.swift`
- 修改：`Sources/OhMyServers/Services/AppModel.swift`
- 修改：`Sources/OhMyServers/Theme/Graphite.swift`
- 修改：`Sources/OhMyServers/Info.plist`
- 修改：`Scripts/run-app.sh`
- 修改：`README.md`
- 创建：`Resources/AppIcon.icns`（或 `Sources/OhMyServers/Resources/`）

**设置页：**

1. 「添加」后草稿立刻出现在左侧列表（未保存不写盘）。选中草稿可继续编辑；点删除则丢掉草稿。点其他已保存服务器再回来，草稿仍在，直到保存或删除。
2. 删除已保存服务器：`confirmationDialog`「确定删除「{name}」？此操作不可撤销。」
3. 新区块「监控」：
   - 刷新间隔：`Picker` 5 / 15 / 30 / 60 秒，绑定 `AppModel.pollIntervalSeconds`，写入 `UserDefaults` key `pollIntervalSeconds`，并 `scheduler.setIntervalSeconds`。
   - 开机自启：`Toggle`，调用 `LaunchAtLogin`。失败时在编辑区显示中文错误，不崩溃。
4. 打开设置时若有服务器且 `editingID == nil`，自动选中第一台。

**开机自启：**

```swift
import ServiceManagement
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setEnabled(_ enabled: Bool) throws
}
```

ad-hoc 签名可能失败，必须 catch。

**AppModel.pollIntervalSeconds：** 启动时从 UserDefaults 读，非法值回退 15。变更时重启或 `setIntervalSeconds`。

**图标：** 深色 Graphite 圆角矩形 + 浅色服务器/状态点意象。提供 `AppIcon.icns`。`Info.plist` 加 `CFBundleIconFile`。`run-app.sh` 复制到 `Contents/Resources/`。

**README：** 更新刷新行为（壁钟 15s 默认可调）、唤醒立采、用量展示、开机自启、终端打开。设置按钮文案改为「设置」不是 Settings。

- [ ] **步骤 1：实现设置与偏好**
- [ ] **步骤 2：图标 + 打包脚本**
- [ ] **步骤 3：`swift test` 全绿**
- [ ] **步骤 4：Commit**

```
feat: polish settings, poll interval, launch at login, and app icon
```

---

## 自检

1. **规格覆盖：** 连接复用/去 sleep、硬超时、更新时间/转圈/负载按核、内存磁盘用量、设置草稿/删除确认/中文错误/Dock 图标、开机自启、间隔、唤醒立采、进度条、终端打开 —— 均有任务。历史曲线等明确不做。
2. **占位符：** 无 TODO/待定步骤。
3. **类型一致：** `MetricSample`、`parse(current:previous:intervalSeconds:)`、`isRefreshing`、`pollIntervalSeconds`、`openInTerminal` 名称跨任务统一。
