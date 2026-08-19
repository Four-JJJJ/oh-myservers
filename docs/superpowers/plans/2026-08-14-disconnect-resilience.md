# 掉线抗抖 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。未经用户明确要求不要 git commit。

**目标：** SSH 假死同轮可恢复；单轮失败不闪 `—`、不弹通知；连续两轮失败才确认离线。

**架构：** `SSHRetryPolicy` 决定是否重试；`ProcessSSHCollector` 失败时 `ssh -O exit` 并可能再试一次；`ReachabilityGate` 按 serverID 做 2 轮确认；`PollScheduler` 在告警前过门；`AlertEvaluator` 冷启动不通知。

**技术栈：** Swift 5.9+ / XCTest / `/usr/bin/ssh`，无新依赖。

**规格：** `docs/superpowers/specs/2026-08-14-disconnect-resilience-design.md`

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `Sources/OhMyServersCore/SSH/SSHRetryPolicy.swift` | 快速失败 + 可重试错误判断 |
| `Sources/OhMyServersCore/Monitor/ReachabilityGate.swift` | 连续失败确认门 |
| `Sources/OhMyServersCore/SSH/ProcessSSHCollector.swift` | keepalive、mux exit、同轮重试、SSH 失败保留缓存 |
| `Sources/OhMyServersCore/Monitor/PollScheduler.swift` | 采集后过 Gate 再告警 |
| `Sources/OhMyServersCore/Alert/AlertEvaluator.swift` | 无 previous 视为从未在线 |
| `Tests/OhMyServersCoreTests/SSHRetryPolicyTests.swift` | 重试策略 |
| `Tests/OhMyServersCoreTests/ReachabilityGateTests.swift` | 确认门 |
| `Tests/OhMyServersCoreTests/AlertEvaluatorTests.swift` | 冷启动不通知 |
| `Tests/OhMyServersCoreTests/PollSchedulerTests.swift` | 集成：先成功再失败仍可达 |
| `Tests/OhMyServersCoreTests/ProcessSSHCollectorTests.swift` | keepalive 常量；SSH 失败保留缓存 |

---

### 任务 1：SSHRetryPolicy

**文件：**
- 创建：`Sources/OhMyServersCore/SSH/SSHRetryPolicy.swift`
- 创建：`Tests/OhMyServersCoreTests/SSHRetryPolicyTests.swift`

- [ ] **步骤 1：写失败测试**

```swift
import XCTest
@testable import OhMyServersCore

final class SSHRetryPolicyTests: XCTestCase {
    func testRetriesTimeoutWhenFast() {
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "连接超时"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 0.4, message: "Connection timed out"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 2, message: "mux_client_request_session: session request failed"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 0.2, message: "Control socket connect failed: Connection refused"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "broken pipe"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "Connection reset by peer"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 5.9, message: "Network is unreachable"))
    }

    func testDoesNotRetrySlowTimeout() {
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 6, message: "连接超时"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 15, message: "Connection timed out"))
    }

    func testDoesNotRetryAuthOrParse() {
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "Permission denied"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "认证失败，请检查密码或密钥"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "Could not find identity file"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "缺少登录凭据"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "无法解析远端指标"))
    }
}
```

- [ ] **步骤 2：运行确认失败**

`swift test --filter SSHRetryPolicyTests`

预期：编译失败，找不到 `SSHRetryPolicy`。

- [ ] **步骤 3：实现**

```swift
import Foundation

public enum SSHRetryPolicy {
    public static let fastFailSeconds: TimeInterval = 6

    public static func shouldRetry(elapsed: TimeInterval, message: String) -> Bool {
        guard elapsed < fastFailSeconds else { return false }
        let lower = message.lowercased()
        if isNonRetryable(lower) { return false }
        return isRetryable(lower)
    }

    private static func isNonRetryable(_ lower: String) -> Bool {
        if lower.contains("permission denied") { return true }
        if lower.contains("认证失败") { return true }
        if lower.contains("identity") { return true }
        if lower.contains("找不到私钥") { return true }
        if lower.contains("缺少登录凭据") { return true }
        if lower.contains("无法解析远端指标") { return true }
        if lower.contains("failed to parse remote metrics") { return true }
        return false
    }

    private static func isRetryable(_ lower: String) -> Bool {
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("连接超时") { return true }
        if lower.contains("connection reset") { return true }
        if lower.contains("connection refused") { return true }
        if lower.contains("broken pipe") { return true }
        if lower.contains("mux") { return true }
        if lower.contains("control socket") { return true }
        if lower.contains("network is unreachable") || lower.contains("网络不可达") { return true }
        if lower.contains("connection closed") { return true }
        if lower.contains("no route to host") { return true }
        return false
    }
}
```

- [ ] **步骤 4：** `swift test --filter SSHRetryPolicyTests` 全绿

---

### 任务 2：ReachabilityGate

**文件：**
- 创建：`Sources/OhMyServersCore/Monitor/ReachabilityGate.swift`
- 创建：`Tests/OhMyServersCoreTests/ReachabilityGateTests.swift`

- [ ] **步骤 1：写失败测试**

```swift
import XCTest
@testable import OhMyServersCore

final class ReachabilityGateTests: XCTestCase {
    func testFirstSuccessPassesThrough() {
        var gate = ReachabilityGate()
        let id = UUID()
        let snap = MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 21)
        let out = gate.accept(snap)
        XCTAssertEqual(out.cpuPercent, 21)
        XCTAssertTrue(out.isReachable)
    }

    func testOneMissHoldsLastGoodIncludingCollectedAt() {
        var gate = ReachabilityGate()
        let id = UUID()
        let collectedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let good = MetricsSnapshot(
            serverID: id,
            collectedAt: collectedAt,
            isReachable: true,
            cpuPercent: 33
        )
        _ = gate.accept(good)
        let miss = MetricsSnapshot.unreachable(serverID: id, message: "连接超时")
        let out = gate.accept(miss)
        XCTAssertTrue(out.isReachable)
        XCTAssertEqual(out.cpuPercent, 33)
        XCTAssertEqual(out.collectedAt, collectedAt)
    }

    func testSecondMissGoesOffline() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        _ = gate.accept(.unreachable(serverID: id, message: "t1"))
        let out = gate.accept(.unreachable(serverID: id, message: "t2"))
        XCTAssertFalse(out.isReachable)
        XCTAssertEqual(out.errorMessage, "t2")
    }

    func testSuccessResetsMissCount() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        _ = gate.accept(.unreachable(serverID: id, message: "t1"))
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 44))
        let out = gate.accept(.unreachable(serverID: id, message: "t2"))
        XCTAssertTrue(out.isReachable)
        XCTAssertEqual(out.cpuPercent, 44)
    }

    func testFirstMissWithoutHistoryIsOffline() {
        var gate = ReachabilityGate()
        let id = UUID()
        let out = gate.accept(.unreachable(serverID: id, message: "连接超时"))
        XCTAssertFalse(out.isReachable)
    }

    func testPruneDropsState() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        gate.prune(keeping: [])
        let out = gate.accept(.unreachable(serverID: id, message: "t"))
        XCTAssertFalse(out.isReachable)
    }

    func testServersAreIndependent() {
        var gate = ReachabilityGate()
        let a = UUID()
        let b = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: a, isReachable: true, cpuPercent: 1))
        _ = gate.accept(MetricsSnapshot(serverID: b, isReachable: true, cpuPercent: 2))
        _ = gate.accept(.unreachable(serverID: a, message: "a1"))
        _ = gate.accept(.unreachable(serverID: a, message: "a2"))
        let stillB = gate.accept(.unreachable(serverID: b, message: "b1"))
        XCTAssertTrue(stillB.isReachable)
        XCTAssertEqual(stillB.cpuPercent, 2)
    }
}
```

- [ ] **步骤 2：** `swift test --filter ReachabilityGateTests` 预期找不到类型。

- [ ] **步骤 3：实现**

```swift
import Foundation

public struct ReachabilityGate: Sendable {
    public var confirmAfter: Int
    private var missCount: [UUID: Int] = [:]
    private var lastGood: [UUID: MetricsSnapshot] = [:]

    public init(confirmAfter: Int = 2) {
        self.confirmAfter = max(1, confirmAfter)
    }

    public mutating func accept(_ raw: MetricsSnapshot) -> MetricsSnapshot {
        let id = raw.serverID
        if raw.isReachable {
            missCount[id] = 0
            lastGood[id] = raw
            return raw
        }
        missCount[id, default: 0] += 1
        if missCount[id, default: 0] < confirmAfter, let held = lastGood[id] {
            return held
        }
        return raw
    }

    public mutating func prune(keeping ids: Set<UUID>) {
        missCount = missCount.filter { ids.contains($0.key) }
        lastGood = lastGood.filter { ids.contains($0.key) }
    }
}
```

- [ ] **步骤 4：** `swift test --filter ReachabilityGateTests` 全绿

---

### 任务 3：AlertEvaluator 冷启动

**文件：**
- 修改：`Sources/OhMyServersCore/Alert/AlertEvaluator.swift`
- 修改：`Tests/OhMyServersCoreTests/AlertEvaluatorTests.swift`

- [ ] **步骤 1：加测试**

```swift
func testNoNotifyWhenNeverReachable() {
    let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
    let curr = [server.id: MetricsSnapshot.unreachable(serverID: server.id, message: "连接超时")]
    let events = AlertEvaluator().evaluate(servers: [server], previous: [:], current: curr)
    XCTAssertTrue(events.filter { $0.title.contains("离线") }.isEmpty)
}
```

- [ ] **步骤 2：** `swift test --filter AlertEvaluatorTests` 预期 `testNoNotifyWhenNeverReachable` 失败（当前 `?? true`）。

- [ ] **步骤 3：** 把 `previous[server.id]?.isReachable ?? true` 改为 `?? false`。

- [ ] **步骤 4：** `swift test --filter AlertEvaluatorTests` 全绿。高负载且 previous 为空时：`wasAbnormal` 对空数组是 false，current 若只有 unreachable 则 health offline → overall abnormal → 仍可能发「服务器状态异常」。规格要求冷启动失败不通知。

若空 previous + 仅 unreachable 会走 overall 边沿：`overallIsAbnormal` 对 `[offline]` 为 true，`prevSnaps` 为空时 `overallIsAbnormal([])` 现实现是 `false`（`guard !snapshots.isEmpty else { return false }`），然后 `!wasAbnormal && isAbnormal` 为 true，且 offline 事件被跳过所以 `events.isEmpty` 为 true，会发「服务器状态异常」。

**必须修：** 仅在「有 previous 快照」时才发整体异常；或冷启动不发整体异常。实现：`if !wasAbnormal && isAbnormal && !prevSnaps.isEmpty`。再加断言：`XCTAssertTrue(events.isEmpty)` 对 cold start。

---

### 任务 4：Collector keepalive / mux / 缓存

**文件：**
- 修改：`Sources/OhMyServersCore/SSH/ProcessSSHCollector.swift`
- 修改：`Tests/OhMyServersCoreTests/ProcessSSHCollectorTests.swift`

- [ ] **步骤 1：测试**

在 `ProcessSSHCollectorTests` 增加：

```swift
func testSSHFailureDoesNotClearSampleCache() {
    let collector = ProcessSSHCollector()
    let serverID = UUID()
    collector.storeSample(makeSample(sampledAt: Date()), for: serverID)
    collector.retainCacheAfterSSHFailure(serverID: serverID)
    XCTAssertNotNil(collector.cachedSample(for: serverID))
}

func testKeepaliveSeconds() {
    XCTAssertEqual(ProcessSSHCollector.serverAliveInterval, 30)
    XCTAssertEqual(ProcessSSHCollector.serverAliveCountMax, 3)
}
```

`retainCacheAfterSSHFailure` 若觉得多余：直接测 `collect` 的 catch 不再 `clearSample`。给 `ProcessSSHCollector` 抽出 `handleSSHFailure(serverID:error:)` 太重。更简单：**失败路径不再调用 `clearSample`**，测试改为文档化行为：现有 `testClearSampleDropsCachedEntry` 保留；新增注释性测试不可行则测静态 keepalive 常量 + 代码审查。

实现要点（`collect`）：

```swift
} catch {
    return .unreachable(
        serverID: server.id,
        message: SSHErrorLocalizer.message(from: error.localizedDescription)
    )
}
```

不要 `clearSample`。

抽出 `static let controlPath = "/tmp/ohmyservers-%C"`、`static let serverAliveInterval = 30`、`static let serverAliveCountMax = 3`。

`runSSH` 改为内部循环：

```swift
private func runSSH(...) async throws -> String {
    var lastError: Error?
    for attempt in 0..<2 {
        let started = Date()
        do {
            return try await runSSHOnce(...)
        } catch {
            lastError = error
            Self.exitMux(server: server)
            let elapsed = Date().timeIntervalSince(started)
            if attempt == 0, SSHRetryPolicy.shouldRetry(elapsed: elapsed, message: error.localizedDescription) {
                continue
            }
            throw error
        }
    }
    throw lastError ?? ProcessSSHError.failed("连接超时")
}
```

`exitMux`：`/usr/bin/ssh -O exit -o ControlPath=/tmp/ohmyservers-%C -p port user@host`，`ConnectTimeout=2`，忽略结果。不要走 password askpass。

`execute` 的 keepalive 改为 30 / 3。

- [ ] **步骤 2：** `swift test --filter ProcessSSHCollectorTests` 全绿

---

### 任务 5：PollScheduler 接入 Gate

**文件：**
- 修改：`Sources/OhMyServersCore/Monitor/PollScheduler.swift`
- 修改：`Tests/OhMyServersCoreTests/PollSchedulerTests.swift`

- [ ] **步骤 1：加可变 mock**

```swift
private final class SequenceCollector: SSHCollecting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    let snapshots: [MetricsSnapshot]

    init(snapshots: [MetricsSnapshot]) {
        self.snapshots = snapshots
    }

    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        let i = lock.withLock { idx -> Int in
            let current = idx
            idx += 1
            return current
        }
        if i < snapshots.count { return snapshots[i] }
        return snapshots.last ?? .unreachable(serverID: server.id, message: "empty")
    }
}

func testOneFailureAfterSuccessStaysReachableAndSilent() async {
    let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
    let good = MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 19)
    let collector = SequenceCollector(snapshots: [
        good,
        .unreachable(serverID: server.id, message: "连接超时")
    ])
    let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in .password("x") }
    let updates = Box<([UUID: MetricsSnapshot], [AlertEvent])>()
    let expectation = expectation(description: "two updates")
    expectation.expectedFulfillmentCount = 2
    await scheduler.start(serversProvider: { [server] }) { snaps, events in
        updates.append((snaps, events))
        expectation.fulfill()
    }
    await scheduler.refresh(servers: [server])
    await fulfillment(of: [expectation], timeout: 2)
    await scheduler.stop()
    XCTAssertEqual(updates.snapshot.count, 2)
    XCTAssertEqual(updates.snapshot[1].0[server.id]?.cpuPercent, 19)
    XCTAssertTrue(updates.snapshot[1].0[server.id]?.isReachable ?? false)
    XCTAssertTrue(updates.snapshot[1].1.isEmpty)
}

func testTwoFailuresAfterSuccessGoOfflineAndNotify() async {
    let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
    let good = MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 19)
    let collector = SequenceCollector(snapshots: [
        good,
        .unreachable(serverID: server.id, message: "t1"),
        .unreachable(serverID: server.id, message: "t2")
    ])
    let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in .password("x") }
    let updates = Box<([UUID: MetricsSnapshot], [AlertEvent])>()
    let expectation = expectation(description: "three updates")
    expectation.expectedFulfillmentCount = 3
    await scheduler.start(serversProvider: { [server] }) { snaps, events in
        updates.append((snaps, events))
        expectation.fulfill()
    }
    await scheduler.refresh(servers: [server])
    await scheduler.refresh(servers: [server])
    await fulfillment(of: [expectation], timeout: 2)
    await scheduler.stop()
    XCTAssertEqual(updates.snapshot.count, 3)
    XCTAssertFalse(updates.snapshot[2].0[server.id]?.isReachable ?? true)
    XCTAssertTrue(updates.snapshot[2].1.contains(where: { $0.title.contains("离线") }))
}
```

注意：`start` 会立刻 `pollOnce` 一次，所以第一次 refresh 可能被 `isPolling` 丢掉。现有 `testRefreshDuringPollDoesNotOverlap` 已覆盖此点。

更稳：不要 `start` 循环，只 `refresh` 三次。`refresh` 即 `pollOnce`。`onUpdate` 只在 `start` 时设置。因此必须 `start`，但把 interval 设很大，并在第一次 onUpdate 后再 refresh。

实现时：第一次 start 触发 poll 1；等 expectation 的 progress 或 sleep 50ms 后再 refresh，避免 overlap。测试里用 `intervalSeconds: 60`，在第一次 fulfill 后 `refresh`。`testRefreshDuringPollDoesNotOverlap` 说明 refresh 在 poll 中会被丢。所以：

```
await start(...)
await fulfillment(first)
await refresh()  // poll 2
await fulfillment(second)
```

不要在 start 后立刻连续 refresh。

- [ ] **步骤 2：** 测试失败（第二次仍不可达）。

- [ ] **步骤 3：** `PollScheduler` 增加 `private var gate = ReachabilityGate()`。`pollOnce` 在 task group 结束后：

```swift
var gated: [UUID: MetricsSnapshot] = [:]
for server in enabled {
    if let raw = next[server.id] {
        gated[server.id] = gate.accept(raw)
    }
}
gate.prune(keeping: Set(enabled.map(\.id)))
next = gated
```

然后照旧 previous/latest/evaluate。

- [ ] **步骤 4：** `swift test --filter PollSchedulerTests` 全绿

---

### 任务 6：全量验证

- [ ] **步骤 1：** `swift test` 全部通过
- [ ] **步骤 2：** 对照规格第 1、2、4、6、7 节，确认无设置项、无黄色态、无恢复通知、SSH 失败不清缓存

不要 commit，除非用户要求。
