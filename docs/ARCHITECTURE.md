# Codex Proxy Launcher 架构

## 定位与边界

Codex Proxy Launcher 提供 macOS 和 Windows 的一次性启动入口：在启动桌面应用前验证 OpenAI HTTP 路线，然后为该次进程树配置代理环境。WebSocket 由独立诊断入口检查，启动时的 HTTP 预检不能替代它。

它不是代理客户端或持续网络监控器，不修改 macOS 系统代理、DNS、ChatGPT.app 或用户的 Git 全局配置。它只能证明启动前检查时的路线可用，不保证之后的长连接始终正常。

## 模块与接口

### 路线模块

`lib/proxy-route.zsh` 是启动器、诊断脚本和交互式终端共享的深模块。调用方只需了解五个主要接口：

- `proxy_route_resolve`：发现并验证路线，每条结果为制表符分隔的 `mode`、`source`、`url`。
- `proxy_route_apply_shell_environment`：只把已选路线转换为当前 shell 的 HTTP 环境，不注入 Git 命令级配置。
- `proxy_route_apply_environment`：把已选路线转换为 ChatGPT/Codex 进程树需要的环境和 Git 命令级配置。
- `proxy_route_redact_url`：在日志或界面中隐去代理 URL 的账号密码。
- `proxy_route_describe`：生成可供启动器和诊断共用的脱敏路线摘要，并明确区分系统/TUN 与显式端口。

`proxy_route_resolve` 的退出状态是接口的一部分：

| 状态 | 含义 |
|---|---|
| `0` | 至少有一条已验证路线，标准输出包含结果 |
| `1` | 没有找到可用路线 |
| `2` | `HTTP_PROXY_URL` 已显式设置，但格式无效或无法连通；不允许自动回退 |

### 启动器

`Codex Proxy.app/Contents/MacOS/codex-proxy-launcher` 编排一次启动：

1. 检查共享路线模块和 ChatGPT 主程序。
2. 检查 ChatGPT 是否已在运行；若是，按 PID 核对已记录路线并显示状态，不启动第二个进程。
3. 调用路线模块；多条结果时通过 AppleScript 让用户选择。
4. 没有路线时，只在用户明确选择后打开 Shadowrocket 或 FlClash，再等待重新检测。
5. 应用该路线的环境，直接启动 ChatGPT 主程序并附加 `--disable-quic`。
6. 只把路线、脱敏 URL、启动请求和 PID 写入精简日志，并把 PID、时间和脱敏路线写入当前会话状态。
7. 通过 osascript 的 JavaScript for Automation 发送非阻塞 macOS 通知，显示“启动前已验证”和本次路线。

启动器是短命进程，当前没有菜单栏常驻状态或持续路线重验证。ChatGPT 已运行时再次点击启动器，只有当前 PID 与会话状态一致才会显示上次记录的路线；否则明确返回“无法确认”。

### 诊断脚本

`diagnose-codex-network.command` 复用同一路线模块，但不复用启动器的交互。如果有多条路线，它按解析顺序使用第一条，然后：

1. 核对 Git 有效 `http.proxy` 是否与路线一致。
2. 运行 ChatGPT 包内的 `codex doctor --json`。
3. 用 `jq` 读取 `network.provider_reachability` 和 `network.websocket_reachability`。
4. 只以这两项网络检查判定诊断成败，不把 doctor 的其他失败误判为代理失败。

## 路线解析数据流

解析顺序是有意设计的优先级：

1. **显式覆盖**：如果存在 `HTTP_PROXY_URL`，只验证它。无效时返回状态 `2`，不尝试其他路线。
2. **系统/TUN**：清除继承的代理变量后直接请求 OpenAI。成功时立即返回 `system/TUN`，不再枚举本地备选端口。
3. **macOS 系统代理**：从 `scutil --proxy` 读取已启用的 HTTPS 和 HTTP 代理。
4. **本地监听端口**：从 `lsof` 输出识别 Shadowrocket、FlClash 和 Clash/Mihomo 进程，将可用监听地址归一化为回环 URL。
5. **去重与真实验证**：按 URL 去重，再用 `curl --proxy` 请求 OpenAI。只返回 HTTP 状态码在 `200` 到 `499` 之间的路线，排除代理认证失败的 `407`；未鉴权时的 `401` 也能说明收到响应。

因此，进程正在监听某个端口只能证明它是候选项，不能证明它是可用代理。系统/TUN 成功时也不能从启动器证据中反推具体是哪个代理应用在提供 TUN。

## 环境语义

| 模式 | ChatGPT/Codex 环境 | Git 命令级配置 |
|---|---|---|
| `system` | 清除大小写的 HTTP、HTTPS、ALL、WS、WSS 和 NO_PROXY 变量，不注入显式代理 | 追加空的 `http.proxy`，屏蔽陈旧全局代理 |
| `explicit` | 设置大小写 `HTTP_PROXY` 和 `HTTPS_PROXY`，设置 `NO_PROXY/no_proxy`，不设置 ALL、WS 或 WSS | 追加与所选 URL 一致的 `http.proxy` |

Git 配置通过 `GIT_CONFIG_COUNT` 及其索引键追加，不修改 `~/.gitconfig`，也不覆盖已有的命令级非代理配置。

`shell/proxy.zsh` 提供可分享的终端适配层：`proxy_auto` 解析第一条可用路线并调用 `proxy_route_apply_shell_environment`，`codex_auto` 用子 shell 将环境限制在单次 CLI 调用中。文件位置根据 source 路径计算，不依赖作者的目录。项目不修改 shell profile、pnpm 或编辑器配置。

### Windows 适配

`windows/ProxyRoute.ps1` 实现同样的路线优先级，使用 .NET HTTP 探测、只读 WinINET 注册表设置、`Get-NetTCPConnection` 和进程名发现代理。不执行 PAC，也不修改系统代理。

桌面入口从常见目录或 OpenAI Appx 包清单找到可执行文件，也接受 `-AppPath`。通过 `ProcessStartInfo.UseShellExecute=false` 启动子进程，使其继承本次环境；随后在 `finally` 中恢复调用方的环境。不能直接启动的 Store 包会失败，目前不提供特殊激活桥接。

PowerShell 5.1 的环境 API 无法保留空值，因此系统/TUN 路线使用 `GIT_CONFIG_PARAMETERS` 中的空 `http.proxy` 覆盖旧 Git 代理。显式路线使用 `GIT_CONFIG_COUNT` 追加代理，其他已有配置保持原样。URL 专用 Git 配置可能仍然优先，诊断时应检查最终有效值。

Windows 诊断使用原生 JSON 解析，要求两个网络检查都为 `ok`。原生命令的其他 doctor 错误不改变这一判定；缺字段、格式错误和任意网络告警均不会被当作全部通过。

### 运行时定位

macOS 的 `lib/codex-runtime.zsh` 按显式覆盖、新版应用内 CLI、旧版 CLI、PATH 的顺序查找。Windows 的 `Get-CodexCommand` 按显式覆盖、应用内候选位置和 PATH 查找。定位器只查路径，不安装程序、不升级应用。

### 用户安装与发布包

`Install-Windows.cmd` 调用 `windows/Install-CodexProxy.ps1`，将白名单文件复制到用户本地应用目录，并通过 WScript.Shell 创建桌面与开始菜单快捷方式。`InstallSupport.ps1` 负责文件安装与快捷方式；对非空且没有项目标记的目标目录，安装器拒绝覆盖。重新安装只更新项目文件，保留日志和额外文件。

Windows 的 `CodexProxy.ico` 直接封装 macOS 原图中的 PNG 帧，包含 16、32、64、128、256 像素尺寸。安装器将其复制到稳定的安装目录，并设置两个快捷方式的 `IconLocation`；更新旧版安装时也会改写图标引用，避免依赖下载目录或默认命令行图标。

桌面入口自动查找失败时，Windows 文件选择框让用户选择应用，路径保存到独立的用户本地设置目录。显式传入的路径始终优先，旧路径失效后重新尝试自动发现。配置文件不包含代理凭据。

`scripts/build-release.py` 用明确的文件清单生成分平台 ZIP 和 `SHA256SUMS.txt`。发布包不包含源码测试、`.git`、本机日志、旧图标草稿或个人配置。Windows 批处理统一转换为 CRLF，macOS 启动文件保留执行权限。

## 日志与敏感信息

- 当前日志为 `logs/launcher.log`，大小达到 1 MiB 时轮转，保留三个历史文件。
- `logs/current-session.state` 原子替换上次会话记录，只包含 PID、时间和脱敏路线，不作为持续健康状态。
- 代理 URL 中的凭据在进入日志或界面前必须经过 `proxy_route_redact_url`，Windows 使用 `Protect-ProxyUrl`。
- ChatGPT/Codex 的标准输出和错误输出被丢弃，不进入启动器日志。
- `logs/codex-proxy.log` 是旧日志，现有脚本不再写入。

## 验证面

`tests/test-proxy-contract.zsh` 是统一验证入口：

```sh
./tests/test-proxy-contract.zsh
```

它先对生产脚本执行 Zsh 语法检查和静态约束，再运行 `tests/test-proxy-behavior.zsh`。行为测试用本地假实现替代 `curl`、`scutil`、`lsof`、`osascript`、ChatGPT 和 Codex，因此不需要改动系统代理，也不依赖真实代理节点。

自动化测试验证路线选择、环境语义、日志脱敏和诊断判定，但不能替代真实 macOS 通知、Dock 交互或当前网络路线的人工验收。

`tests/test-windows.ps1` 在 PowerShell 5.1/7 上解析脚本并运行无网络行为测试。GitHub Actions 在 macOS 和 Windows runner 上执行对应检查；Store 包激活、桌面通知和真实代理长连接仍需人工验证。
