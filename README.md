# Oh My Servers

macOS 菜单栏应用：添加任意公开 Komari 监控站点的地址，就能在菜单栏弹窗里直接看它的服务器卡片。支持多个站点，Graphite 深色紧凑风。

## 功能

- 添加 / 删除多个 Komari 站点地址（任何公开实例都可以用，不需要自己部署）
- 菜单栏弹窗内嵌站点卡片，实时刷新，样式与 Komari 网页一致
- 菜单栏摘要：如 `HK 23% · US 41%`，附整体在线状态点
- 刷新间隔可选 5 / 15 / 30 / 60 秒；睡眠唤醒后立刻再采一轮
- 开机自启（系统允许时）
- 本地 ad-hoc 签名即可使用，无需 Apple 开发者账号

> 说明：站点的 `/api/nodes` 与 `/api/clients` 是 Komari 前端的公开接口。对方若把站点设为私有（公开页关闭）或加了拦截防护，卡片和摘要都会取不到数据。

## 要求

- macOS 14+
- Xcode / Swift 5.9+ 命令行工具

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
2. 粘贴一个 Komari 站点地址（如 `https://komari.example.com`，可不带 scheme），可选填名称，点 **+**
3. 菜单栏弹窗即刻出现该站点的卡片；再加几个地址就按站点分组上下排列
4. 底部可调整刷新间隔与开机自启；站点行内开关可临时停用

站点列表保存在 UserDefaults（`komariSites`）。

## GitHub 分发（可选）

无开发者账号时可用 GitHub Releases 提供 `.app` zip，并在 Release 说明里写清：用户需右键打开或自行 `codesign --sign -`。若以后有开发者账号，再补公证（notarization）。
