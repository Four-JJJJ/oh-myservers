# Oh My Servers

macOS 菜单栏应用：通过 SSH（无 Agent）查看 Linux 服务器实时状态。风格参考 ServerCat，界面为 Graphite 深色紧凑风。

## 功能（v0.1）

- 菜单栏摘要：如 `HK 23% · US 41%`
- 多服务器管理；密码 / 私钥（Ed25519、RSA）登录
- 指标：CPU、Load、内存、磁盘、网络吞吐、uptime / 连通性
- 连通失败或整体异常时边沿触发系统通知
- 本地 ad-hoc 签名即可使用，无需 Apple 开发者账号

## 要求

- macOS 14+
- Xcode / Swift 5.9+ 命令行工具
- 目标服务器为 Linux（读 `/proc`）

## 本地运行

```bash
./Scripts/run-app.sh
```

脚本会 release 构建、打包 `OhMyServers.app`、ad-hoc 签名并打开。首次打开若被 Gatekeeper 拦截：系统设置 → 隐私与安全性 → 仍要打开。

仅跑测试：

```bash
swift test
```

## 使用

1. 点击菜单栏摘要 → **Settings**
2. **Add** 服务器：填写 Name、Label（摘要缩写，如 `HK`/`US`）、Host、用户名
3. 选择 Password 或 Private Key，保存
4. 约 15 秒内出现指标；离线会变红并通知一次

凭据保存在 macOS Keychain（`app.ohmyservers.credentials`）；服务器列表在  
`~/Library/Application Support/OhMyServers/servers.json`。

## 明确不做（一期）

内置终端、历史曲线、Docker/GPU、阈值告警、跳板机。

## GitHub 分发（可选）

无开发者账号时可用 GitHub Releases 提供 `.app` zip，并在 Release 说明里写清：用户需右键打开或自行 `codesign --sign -`。若以后有开发者账号，再补公证（notarization）。

## 架构摘要

详见 `docs/superpowers/specs/2026-08-12-oh-myservers-design.md` 与实现计划  
`docs/superpowers/plans/2026-08-12-oh-myservers.md`。
