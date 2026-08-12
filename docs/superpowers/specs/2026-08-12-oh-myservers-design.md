# Oh My Servers — 产品设计规格

**日期：** 2026-08-12  
**状态：** 已批准  
**平台：** macOS 菜单栏 App（本地使用；无 Apple 开发者账号分发要求）

## 1. 目标

在 Mac 菜单栏直观查看香港、美国等 Linux 服务器的运行状态。纯状态监控（不对标完整 SSH 终端），支持多服务器与密码/密钥登录。

## 2. 范围

### 第一版包含

- 原生 SwiftUI 菜单栏应用（`MenuBarExtra`）
- 无 Agent：经 SSH 读取 Linux `/proc` 等并解析指标
- 认证：密码登录、私钥登录（口令存 Keychain）
- 多服务器增删改；标签用于摘要（如 `HK` / `US`）
- 实时快照指标：CPU、Load（1/5/15）、内存、磁盘容量、网络吞吐、uptime/连通性
- 菜单栏展示：状态点 + 摘要文字（如 `HK 23% · US 41%`）
- 视觉：Graphite（深色紧凑）
- 基础通知：连通性从可达变为不可达，或整体判定异常时发一条 macOS 通知（边沿触发，不刷屏）
- 本地 ad-hoc 签名即可运行；README 说明构建与可选 GitHub 分发注意点

### 第一版不包含

- 内置 SSH 终端
- 历史曲线 / 长时间存储
- Docker / GPU 监控
- 可配置阈值告警（CPU/内存百分比阈值）
- ProxyJump / 跳板机 / 多跳 SSH
- iCloud 同步、App Store 分发

## 3. 架构

```
MenuBar UI (Graphite)
  → Monitor Core (PollScheduler / StatusAggregator / AlertService)
    → SSH Collector (password | private key)
      → Linux hosts (HK / US / …)
CredentialStore (Keychain) + ServerStore (本地配置)
```

- **MenuBar UI：** 图标 + 摘要；下拉按服务器分块展示快照；设置窗口管理服务器
- **Monitor Core：** 默认约 15s 轮询；汇总健康状态；边沿告警
- **SSH Collector：** 建立会话、执行采集、解析为 `MetricsSnapshot`
- **存储：** 密钥材料相关秘密进 Keychain；主机元数据进本地配置文件

## 4. 组件职责

| 组件 | 职责 |
|------|------|
| `ServerStore` | 服务器列表（主机、端口、用户、标签、认证类型、启用状态） |
| `CredentialStore` | Keychain 读写密码、私钥口令 |
| `SSHSession` | SSH 连接与远端命令执行 |
| `MetricsParser` | 解析 `/proc`、`df` 等输出 |
| `PollScheduler` | 并发轮询多台服务器 |
| `StatusAggregator` | 菜单栏摘要与每机健康状态 |
| `AlertService` | 状态边沿 → 用户通知 |
| `MenuBarView` / `SettingsView` | Graphite UI |

## 5. 界面

- **菜单栏：** 状态点 + 摘要；全部异常时偏红/错误语义
- **下拉：** 每台服务器一块：Online/Offline/High 等状态 + CPU / Load / 内存 / 磁盘 / 网络 / uptime
- **设置：** 添加/编辑/删除；选择密码或密钥；标签用于摘要缩写
- **无**独立大仪表盘窗口作为主体验

## 6. 数据流（单轮）

1. Scheduler 取出启用中的服务器  
2. 按认证类型从 Keychain 取凭据并建立 SSH  
3. 远端读取指标所需文件/命令  
4. Parser → `MetricsSnapshot`  
5. Aggregator 更新摘要与列表  
6. 若可达→不可达（或整体异常边沿）→ 通知一次  

## 7. 错误处理

- 单机超时/认证失败：该机 Offline，不影响其他机
- 解析单项失败：该项显示 `—`，其余继续
- Keychain 失败：明确提示，不把明文密码写入普通配置
- 睡眠/网络切换后：下一轮轮询自动恢复
- 通知仅边沿触发

## 8. 测试与验收

### 自动化

- `MetricsParser` 样例驱动单元测试
- `StatusAggregator` 摘要与健康状态
- `AlertService` 边沿触发逻辑

### 手动

1. 密码与密钥登录各至少验证一台  
2. 菜单栏摘要正确  
3. 故障注入 → Offline + 单次通知；恢复后不再刷屏  
4. CRUD 多服务器后轮询与摘要正确  
5. 无开发者账号下本机可常驻运行  

## 9. 技术选型

- 语言/UI：Swift / SwiftUI，macOS 14+
- SSH：本机 `/usr/bin/ssh`（与系统 SSH 配置一致；避免 NIOSSH 与新版 OpenSSH 密钥交换不兼容）
- 采集：SSH + Linux `/proc` / `df` 等，服务器零安装
- 发布：本地构建；可选 GitHub Releases + 自行签名说明
