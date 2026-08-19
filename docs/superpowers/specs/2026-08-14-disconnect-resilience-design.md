# Oh My Servers — 掉线抗抖设计

**日期：** 2026-08-14  
**状态：** 已批准（方案 3：同轮重试 + 两轮确认）  
**平台：** 现有 macOS 菜单栏 App（OhMyServersCore + App）

## 1. 目标

出口抖动、SSH 复用连接假死时，菜单栏不要立刻变成 `HK — · US —`，也不要连续弹「已离线」。真断线在连续两轮探测失败后确认。

成功标准：

- 单轮 SSH 失败（且此前在线）：菜单栏仍显示上次 CPU，不通知
- 连续两轮失败：该机变为 `—`，并边沿通知一次
- 从未成功过的失败：显示 `—`，不通知
- 已离线期间的持续失败：不重复通知
- 恢复在线：不通知
- 僵死 ControlMaster：同轮内快速失败则丢掉 mux 再试一次，成功则本轮算在线

## 2. 范围

包含：

- SSH keepalive 放宽、失败时退出 mux、符合条件时同轮重试一次
- SSH 失败不再清掉 `/proc` 样本缓存
- 每台服务器连续失败确认门（2 次）
- 告警：从未在线过 → 离线 不通知

不包含：

- 新设置项、可配置确认次数
- 菜单栏黄色「不稳定」态
- 恢复在线通知
- 按墙钟 30 秒而不是按轮次确认
- 跳板机、历史曲线、改默认刷新间隔

确认次数写死为 2。刷新间隔改为 5 / 60 秒时，宽限期随之变为约 10 秒 / 2 分钟。

## 3. 架构

```
SSH collect (+ mux 退出 / 同轮最多 1 次重试)
  → raw MetricsSnapshot
    → ReachabilityGate（按 serverID：失败计数 + 上次成功快照）
      → PollScheduler.latest
        → 菜单栏 / 下拉 / AlertEvaluator
```

Gate 只改「对外展示是否可达」。Collector 的 raw 失败仍是失败；UI 在宽限期内看到的是上一份成功快照（含原来的 `collectedAt`）。

## 4. 组件

### 4.1 `SSHRetryPolicy`

纯函数，无 I/O。

- `fastFailSeconds = 6`
- `shouldRetry(elapsed:message:) -> Bool`

可重试（大小写不敏感，对原文或已本地化文案都成立）：`timeout` / `timed out` / `连接超时`、`connection reset`、`connection refused`、`broken pipe`、`mux`、`control socket`、`network is unreachable` / `网络不可达`、`connection closed`、`no route to host`。

不可重试：`permission denied` / `认证失败`、私钥/identity、`缺少登录凭据`、`无法解析远端指标`。

重试条件：`elapsed < 6` 且可重试且本轮尚未重试。整段 15 秒硬超时不算快速失败，不重试。

### 4.2 `ProcessSSHCollector`

SSH 选项改为：

- `ControlMaster=auto`
- `ControlPath=/tmp/ohmyservers-%C`
- `ControlPersist=120`
- `ServerAliveInterval=30`
- `ServerAliveCountMax=3`

`ConnectTimeout` 仍为 10，整段硬超时仍为 15 秒（每一次 attempt）。

行为：

1. 任一次 SSH 失败（含硬超时）：best-effort `ssh -O exit`（同一 `ControlPath` / host / port / user），忽略退出码。
2. 若 `shouldRetry`：再 `execute` 一次，不再重试。
3. SSH 失败（`catch`）：**不清** `previousSamples`。解析失败仍清缓存。

`ssh -O exit` 使用同一套 ControlPath，短超时（约 2 秒），失败忽略。

### 4.3 `ReachabilityGate`

每台服务器：

- `missCount: Int`
- `lastGood: MetricsSnapshot?`

`confirmAfter = 2`。

```
accept(raw):
  if raw.isReachable:
    missCount = 0
    lastGood = raw
    return raw
  missCount += 1
  if missCount < confirmAfter AND lastGood != nil:
    return lastGood          // 宽限：仍可达，collectedAt 不变
  return raw                 // 离线
```

`prune(keeping: Set<UUID>)`：丢掉已删除/未启用服务器的状态。

冷启动无 `lastGood`：第一次失败直接离线展示，不进入宽限。

### 4.4 `PollScheduler`

`pollOnce` 在收集完 raw 快照后、写入 `latest` / 调用 `AlertEvaluator` 之前，对每台 enabled 服务器 `gate.accept`，然后 `prune`。

`previous` 存的是 **gate 之后** 的快照。因此：

- 第 1 次失败：current 仍是 lastGood（可达）→ 无通知
- 第 2 次失败：current 不可达、previous 可达 → 通知一次

### 4.5 `AlertEvaluator`

`wasReachable` 在没有 previous 时改为 `false`（现在是 `true`）。

这样冷启动第一轮失败不会弹「已离线」。其余边沿逻辑不变：可达→不可达通知；持续离线不通知；高负载边沿仍通知；恢复不通知。

### 4.6 UI

不改 `StatusAggregator` / `MenuBarRootView`。宽限期内对外仍是可达快照，菜单栏继续显示上次 CPU；下拉里「N 秒前」会变大。确认离线后才是 `—` 和错误文案。

## 5. 数据流（单轮）

1. 并发采集各 enabled 服务器（缺凭据 → raw 不可达「缺少登录凭据」）
2. 每台 raw → `ReachabilityGate.accept`
3. `prune` 非 enabled id
4. `AlertEvaluator.evaluate(previousGated, currentGated)`
5. `onUpdate`

Mac 唤醒后的立刻再采保持不变。若 mux 已死：快速失败 → `-O exit` → 同轮重试，多数情况下一轮内恢复，不进宽限。

## 6. 错误处理

| 情况 | 采集 | Gate | 通知 |
|---|---|---|---|
| mux 假死，重试成功 | 本轮成功 | 在线 | 无 |
| 出口抖 1 轮 | raw 失败 | 宽限（有 lastGood） | 无 |
| 连续 2 轮失败 | raw 失败 | 离线 | 一次「已离线」 |
| 认证失败 | 不可重试 | 同确认门 | 仅确认后一次 |
| 解析失败 | 清样本缓存，不可达 | 同确认门 | 仅确认后一次 |
| 缺凭据 | raw 不可达 | 同确认门 | 仅确认后一次 |
| 睡眠后第一轮失败 | 可能重试 | 宽限 | 无 |

两台服务器状态独立：一台离线不影响另一台的宽限计数。

## 7. 测试

- `SSHRetryPolicy`：可重试/不可重试文案、elapsed 边界（5.9s 可重试，6s 不可）
- `ReachabilityGate`：成功；成功后 1 次失败仍返回 lastGood 且 `collectedAt` 不变；第 2 次失败返回不可达；再成功清零；无 lastGood 的首次失败返回不可达；prune 掉计数
- `AlertEvaluator`：无 previous 的不可达不通知；可达→不可达仍通知；持续离线不通知
- `PollScheduler`：mock 先成功再失败一次，`onUpdate` 第二次仍 `isReachable == true` 且 CPU 为旧值；再失败一次才不可达并产生离线事件

## 8. 技术选型

沿用现有 Swift 5.9 / actor `PollScheduler` / `/usr/bin/ssh`。Gate 为可变 struct，仅由 `PollScheduler` actor 持有。不引入新依赖。
