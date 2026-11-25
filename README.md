# LiteControl

LiteControl 是面向 Apple Silicon、macOS 14 及以上版本的原生菜单栏工具，管理 LiteTick、LitePark、LiteNum、LiteCount、LiteFocus、LiteCal、LiteStick 和 LitePost。

从 [GitHub Releases](https://github.com/victor-zhang-2026/LiteControl/releases/latest) 下载适用于 Apple Silicon 的 ZIP，解压后将 `LiteControl.app` 拖入「应用程序」并打开。

点击菜单栏的滑杆图标查看已安装应用。开关控制原生应用的启动和正常退出。LitePost 的开关控制 Hammerspoon 中的记录窗口，沿用既有快捷键和未保存提醒。「发现更多 Lite 应用」默认折叠，展开后可访问各产品的 GitHub Releases。点击应用图标或名称可打开对应的 GitHub 仓库主页。面板会自动刷新安装状态。

本机专用应用可登记在 `~/Library/Application Support/LiteControl/local-products.json`。文件是 JSON 数组，每项含 `name`、`bundleID` 和可选的 GitHub 仓库地址 `repository`。启动 LiteControl 时加载配置，已安装的条目参与单项和批量控制。

用 Xcode 打开 `LiteControl.xcodeproj`，或执行 `./scripts/build-app.sh` 生成 `build/LiteControl.app`。日常使用时从 `/Applications` 运行，可在面板底部设置开机启动。
