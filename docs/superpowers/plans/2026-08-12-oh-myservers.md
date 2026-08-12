# Oh My Servers 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 打造可在本机运行的 macOS 菜单栏 App，经 SSH 无 Agent 采集 Linux 服务器 CPU/Load/内存/磁盘/网络/uptime，并以 Graphite 深色风格展示多服务器状态与基础离线通知。

**架构：** Swift Package 拆成可测试的 `OhMyServersCore`（模型、解析、聚合、告警、存储、SSH 采集）与 `OhMyServers` 可执行菜单栏 App（SwiftUI `MenuBarExtra` + 设置窗）。凭据进 Keychain；服务器元数据进 Application Support JSON。

**技术栈：** Swift 5.9+ / SwiftUI / macOS 14+、Citadel（SSH）、Security.framework（Keychain）、UserNotifications、XCTest

**规格：** `docs/superpowers/specs/2026-08-12-oh-myservers-design.md`

---

## 文件结构

| 路径 | 职责 |
|------|------|
| `Package.swift` | SPM：Core 库、App 可执行目标、测试目标；依赖 Citadel |
| `Sources/OhMyServersCore/Models/ServerConfig.swift` | 服务器配置与认证类型 |
| `Sources/OhMyServersCore/Models/MetricsSnapshot.swift` | 单机指标快照与健康枚举 |
| `Sources/OhMyServersCore/Parser/MetricsParser.swift` | 解析 `/proc`、`df`、网络计数 |
| `Sources/OhMyServersCore/Aggregator/StatusAggregator.swift` | 菜单栏摘要与整体状态 |
| `Sources/OhMyServersCore/Alert/AlertEvaluator.swift` | 边沿告警判定（纯逻辑） |
| `Sources/OhMyServersCore/Store/ServerStore.swift` | JSON 持久化服务器列表 |
| `Sources/OhMyServersCore/Store/CredentialStore.swift` | Keychain 读写 |
| `Sources/OhMyServersCore/SSH/SSHCollecting.swift` | 采集协议（便于 mock） |
| `Sources/OhMyServersCore/SSH/CitadelSSHCollector.swift` | Citadel 实现 |
| `Sources/OhMyServersCore/SSH/RemoteMetricScripts.swift` | 远端采集命令脚本 |
| `Sources/OhMyServersCore/Monitor/PollScheduler.swift` | 定时并发轮询 |
| `Sources/OhMyServers/OhMyServersApp.swift` | `@main` App 入口 |
| `Sources/OhMyServers/Info.plist` | `LSUIElement` 等 |
| `Sources/OhMyServers/Views/MenuBarRootView.swift` | Graphite 下拉列表 |
| `Sources/OhMyServers/Views/SettingsView.swift` | 服务器 CRUD / 认证表单 |
| `Sources/OhMyServers/Services/AppModel.swift` | UI 状态与监控编排 |
| `Sources/OhMyServers/Services/NotificationService.swift` | 系统通知桥接 |
| `Tests/OhMyServersCoreTests/MetricsParserTests.swift` | 解析测试 |
| `Tests/OhMyServersCoreTests/StatusAggregatorTests.swift` | 摘要测试 |
| `Tests/OhMyServersCoreTests/AlertEvaluatorTests.swift` | 告警边沿测试 |
| `Tests/OhMyServersCoreTests/Fixtures/*.txt` | `/proc` 等样例 |
| `Scripts/run-app.sh` | 本地构建并启动 |
| `README.md` | 构建、权限、无开发者账号说明 |

---

### 任务 1：仓库脚手架与领域模型

**文件：**
- 创建：`Package.swift`
- 创建：`Sources/OhMyServersCore/Models/ServerConfig.swift`
- 创建：`Sources/OhMyServersCore/Models/MetricsSnapshot.swift`
- 创建：`Tests/OhMyServersCoreTests/ModelSmokeTests.swift`
- 修改：`.gitignore`（若需补全）

- [ ] **步骤 1：写入 `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OhMyServers",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OhMyServersCore", targets: ["OhMyServersCore"]),
        .executable(name: "OhMyServers", targets: ["OhMyServers"])
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "OhMyServersCore",
            dependencies: [
                .product(name: "Citadel", package: "Citadel")
            ]
        ),
        .executableTarget(
            name: "OhMyServers",
            dependencies: ["OhMyServersCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "OhMyServersCoreTests",
            dependencies: ["OhMyServersCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **步骤 2：定义模型**

`ServerConfig`：`id: UUID`、`name`、`host`、`port: UInt16 = 22`、`username`、`label`（摘要用，如 `HK`）、`authMethod`（`.password` / `.privateKey`）、`privateKeyPath: String?`、`isEnabled: Bool`。

`MetricsSnapshot`：`serverID`、`collectedAt`、`isReachable`、`cpuPercent: Double?`、`load1/5/15: Double?`、`memoryUsedBytes/memoryTotalBytes: UInt64?`、`diskUsedPercent: Double?`（根分区）、`netRxBytesPerSec/netTxBytesPerSec: Double?`、`uptimeSeconds: UInt64?`、`errorMessage: String?`。

`ServerHealth`：`.online` / `.high` / `.offline`（CPU≥85% 或内存≥90% 或磁盘≥90% → high；不可达 → offline）。

- [ ] **步骤 3：写冒烟测试并运行**

```swift
import XCTest
@testable import OhMyServersCore

final class ModelSmokeTests: XCTestCase {
    func testServerConfigCodableRoundTrip() throws {
        let s = ServerConfig(
            id: UUID(),
            name: "Hong Kong",
            host: "hk.example.com",
            port: 22,
            username: "ubuntu",
            label: "HK",
            authMethod: .password,
            privateKeyPath: nil,
            isEnabled: true
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded.host, "hk.example.com")
        XCTAssertEqual(decoded.label, "HK")
    }
}
```

运行：`swift test --filter ModelSmokeTests`  
预期：PASS（需先有最小可编译实现）

- [ ] **步骤 4：Commit**

```bash
git add Package.swift Sources/OhMyServersCore/Models Tests/OhMyServersCoreTests/ModelSmokeTests.swift .gitignore
git commit -m "$(cat <<'EOF'
chore: scaffold SPM package and core models

EOF
)"
```

---

### 任务 2：MetricsParser（TDD）

**文件：**
- 创建：`Sources/OhMyServersCore/Parser/MetricsParser.swift`
- 创建：`Tests/OhMyServersCoreTests/MetricsParserTests.swift`
- 创建：`Tests/OhMyServersCoreTests/Fixtures/proc_stat.txt`、`proc_meminfo.txt`、`proc_loadavg.txt`、`proc_uptime.txt`、`proc_net_dev.txt`、`df.txt`（两份 net_dev 用于速率差）

- [ ] **步骤 1：准备 Fixtures**  
使用典型 Linux 样例文本（含 `cpu ` 行、MemTotal/MemAvailable、loadavg、uptime、`eth0` 行列、`df -BP` 根分区）。

- [ ] **步骤 2：编写失败测试**

覆盖：CPU 百分比（两次 `proc_stat` 差分）、内存已用百分比、load 三值、uptime、磁盘%、网速（两次 `proc_net_dev` + 间隔秒数）。

- [ ] **步骤 3：运行确认失败** → `swift test --filter MetricsParserTests`

- [ ] **步骤 4：实现 `MetricsParser`**  
输入为结构化原始字符串集合 `RemoteMetricRaw`，输出填充可选字段的快照片段；单项失败不抛致命错误。

- [ ] **步骤 5：测试通过后 Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add Linux metrics parser with fixtures

EOF
)"
```

---

### 任务 3：StatusAggregator + AlertEvaluator（TDD）

**文件：**
- 创建：`Sources/OhMyServersCore/Aggregator/StatusAggregator.swift`
- 创建：`Sources/OhMyServersCore/Alert/AlertEvaluator.swift`
- 创建：对应测试文件

- [ ] **步骤 1：摘要测试**  
多机 → `"HK 23% · US 41%"`（优先 CPU%；离线显示 `"HK —"`）；空列表 → 占位如 `"No servers"`。

- [ ] **步骤 2：健康状态测试**  
online / high / offline 边界。

- [ ] **步骤 3：告警边沿测试**  
仅当某机 `reachable true→false` 或整体从正常→异常时 `shouldNotify == true`；持续 offline 不重复通知。

- [ ] **步骤 4：实现并 `swift test` 全绿后 Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add status aggregator and edge alert evaluator

EOF
)"
```

---

### 任务 4：ServerStore + CredentialStore

**文件：**
- 创建：`Sources/OhMyServersCore/Store/ServerStore.swift`
- 创建：`Sources/OhMyServersCore/Store/CredentialStore.swift`
- 创建：`Tests/OhMyServersCoreTests/ServerStoreTests.swift`

- [ ] **步骤 1：`ServerStore`**  
路径：`~/Library/Application Support/OhMyServers/servers.json`；CRUD + `Codable`；原子写入。

- [ ] **步骤 2：测试用临时目录注入 `fileURL`**

- [ ] **步骤 3：`CredentialStore`**  
Keychain service：`app.ohmyservers.credentials`；account：`server.<uuid>.password` / `server.<uuid>.keyPassphrase`；提供 `save/load/delete`。单元测试可在 CI 跳过 Keychain（用 `#if` 或协议 mock）；至少编译通过。

- [ ] **步骤 4：Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: persist servers to disk and secrets to Keychain

EOF
)"
```

---

### 任务 5：SSH 采集层

**文件：**
- 创建：`Sources/OhMyServersCore/SSH/SSHCollecting.swift`
- 创建：`Sources/OhMyServersCore/SSH/RemoteMetricScripts.swift`
- 创建：`Sources/OhMyServersCore/SSH/CitadelSSHCollector.swift`
- 创建：`Sources/OhMyServersCore/Monitor/PollScheduler.swift`
- 创建：`Tests/OhMyServersCoreTests/PollSchedulerTests.swift`（用 mock collector）

- [ ] **步骤 1：定义协议**

```swift
public protocol SSHCollecting: Sendable {
    func collect(from server: ServerConfig, credential: SSHCredential) async throws -> MetricsSnapshot
}
```

- [ ] **步骤 2：远端脚本**  
一次 SSH 执行复合命令，输出带分隔符的块：`STAT`/`STAT2`（短间隔采样）、`MEMINFO`、`LOADAVG`、`UPTIME`、`NET`/`NET2`、`DF`，供 Parser 使用。

- [ ] **步骤 3：Citadel 实现**  
密码与私钥文件登录；超时（如 10s）映射为不可达快照而非崩溃。

- [ ] **步骤 4：`PollScheduler`**  
`AsyncStream` 或回调发布 `[MetricsSnapshot]`；`TaskGroup` 并发；可 `start/stop`；默认 15s。

- [ ] **步骤 5：Mock 测试 Scheduler 并发与错误隔离后 Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add SSH collector and poll scheduler

EOF
)"
```

---

### 任务 6：菜单栏 App UI（Graphite）

**文件：**
- 创建：`Sources/OhMyServers/OhMyServersApp.swift`
- 创建：`Sources/OhMyServers/Info.plist`
- 创建：`Sources/OhMyServers/Services/AppModel.swift`
- 创建：`Sources/OhMyServers/Services/NotificationService.swift`
- 创建：`Sources/OhMyServers/Views/MenuBarRootView.swift`
- 创建：`Sources/OhMyServers/Views/ServerRowView.swift`
- 创建：`Sources/OhMyServers/Views/SettingsView.swift`
- 创建：`Scripts/run-app.sh`

- [ ] **步骤 1：`AppModel`**  
加载 Store、启动 Scheduler、应用 Aggregator/AlertEvaluator、调用 NotificationService。

- [ ] **步骤 2：`MenuBarExtra`**  
label：状态点 + `menuBarTitle`；下拉 Graphite 深色列表；每机一行指标网格。

- [ ] **步骤 3：`SettingsView`**  
表单：名称、host、port、user、label、认证方式、密码或私钥路径、启用开关；保存时写 Store + Keychain。

- [ ] **步骤 4：通知权限请求 + 边沿发通知**

- [ ] **步骤 5：`Scripts/run-app.sh`**  
`swift build -c release`，组装最小 `.app`（可执行文件 + Info.plist），`codesign --force --deep --sign -`，`open`。

- [ ] **步骤 6：本机启动冒烟（无真服务器也可打开设置）后 Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add Graphite menu bar app and settings UI

EOF
)"
```

---

### 任务 7：README 与验收收尾

**文件：**
- 创建：`README.md`

- [ ] **步骤 1：写清**  
功能简介、系统要求、`./Scripts/run-app.sh`、密码/密钥配置、通知权限、无开发者账号说明、后续 GitHub Release 注意 Gatekeeper。

- [ ] **步骤 2：跑 `swift test` 全绿**

- [ ] **步骤 3：对照规格验收清单勾选（能本地验证的项）**

- [ ] **步骤 4：Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: add README for local build and usage

EOF
)"
```

---

## 自检

1. **规格覆盖：** 监控定位、摘要菜单栏、SwiftUI、通知边沿、六指标、多服务器、密码/密钥、Graphite、本地运行 —— 均有对应任务。  
2. **无占位：** 无 TODO/待定步骤。  
3. **类型一致：** `ServerConfig` / `MetricsSnapshot` / `SSHCollecting` 在各任务命名统一。
