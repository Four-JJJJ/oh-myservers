# Oh My Servers

macOS 菜单栏应用：通过 SSH（无 Agent）查看 Linux 服务器实时状态。风格参考 ServerCat，界面为 Graphite 深色紧凑风。

## 功能（v0.1）

- 菜单栏摘要：如 `HK 23% · US 41%`
- 多服务器管理；密码 / 私钥（Ed25519、RSA）登录
- 指标：CPU、按核着色的负载、内存 / 磁盘已用与总量、网络吞吐、uptime / 连通性
- 壁钟刷新：默认 15 秒，可在设置中改为 5 / 15 / 30 / 60 秒；采集耗时从间隔中扣除
- 唤醒后立刻再采一轮
- 连通失败或整体异常时边沿触发系统通知
- 开机自启（系统允许时）
- 「终端」在系统「终端」App 中执行 `ssh`，不是内置终端
- 本地 ad-hoc 签名即可使用，无需 Apple 开发者账号

## 要求

- macOS 14+
- Xcode / Swift 5.9+ 命令行工具
- 目标服务器为 Linux（读 `/proc`）

## 本地运行

```bash
./Scripts/run-app.sh
```

脚本会 release 构建、打包 `OhMyServers.app`（含 App 图标）、ad-hoc 签名并打开。首次打开若被 Gatekeeper 拦截：系统设置 → 隐私与安全性 → 仍要打开。

仅跑测试：

```bash
swift test
```

重新生成 Dock / Finder 图标：

```bash
python3 Scripts/generate-app-icon.py
```

## 使用

1. 点击菜单栏摘要 → **设置**
2. **添加**服务器：填写名称、摘要标签（如 `HK` / `US`）、主机、用户名
3. 选择密码或密钥登录，保存
4. 按所选刷新间隔出现指标（默认约 15 秒）；离线会变红并通知一次
5. 需要时打开「终端」连上该主机，或在「监控」里调整刷新间隔 / 开机自启

凭据保存在 macOS Keychain（`app.ohmyservers.credentials`）；服务器列表在  
`~/Library/Application Support/OhMyServers/servers.json`。

## 明确不做（一期）

内置终端、历史曲线、Docker/GPU、阈值告警、跳板机。

## GitHub 分发（可选）

无开发者账号时可用 GitHub Releases 提供 `.app` zip，并在 Release 说明里写清：用户需右键打开或自行 `codesign --sign -`。若以后有开发者账号，再补公证（notarization）。

## 架构摘要

详见 `docs/superpowers/specs/2026-08-12-oh-myservers-design.md` 与实现计划  
`docs/superpowers/plans/2026-08-12-oh-myservers.md`。
