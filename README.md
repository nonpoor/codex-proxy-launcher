# Codex Proxy Launcher

启动 Codex / ChatGPT 桌面应用前，找一条能访问 OpenAI 的网络路线，再把代理环境传给本次启动的进程。适合代理客户端已开启，但 Codex 仍反复显示 reconnect 的情况。

提供 macOS App、Windows 双击入口和命令行诊断。需要自行安装桌面应用与代理客户端，并使用自己的账号登录。

## 先选对应入口

| 你要做什么 | macOS | Windows |
| --- | --- | --- |
| 启动桌面应用 | `Codex Proxy.app` | `windows/Start-CodexProxy.cmd` |
| 检查 HTTP 与 WebSocket | `diagnose-codex-network.command` | `windows/Diagnose-CodexNetwork.cmd` |
| 在终端使用同一套路线检测 | `shell/proxy.zsh` | `windows/Start-CodexCLI.ps1` |

下载时保留整个目录。macOS App 需要旁边的 `lib/`，Windows 入口需要同目录的 PowerShell 脚本，单独复制一个入口文件无法运行。

## Windows 快速开始

需要 Windows 10/11、Windows PowerShell 5.1 或 PowerShell 7，以及已安装的 Codex / ChatGPT 桌面应用。使用原生 Windows 入口，WSL 内的代理环境不在本项目覆盖范围内。

1. 在 GitHub 页面选择 **Code > Download ZIP**，解压到普通用户目录，比如 `C:\Tools\codex-proxy-launcher`。
2. 打开 FlClash 或其他代理客户端，确认节点可用。系统代理、TUN 或可用的本地 HTTP 代理端口均可。
3. 手动退出正在运行的 Codex / ChatGPT，包括托盘里的后台进程。
4. 双击 `windows/Start-CodexProxy.cmd`。多条路线可用时，在窗口中输入编号。
5. 双击 `windows/Diagnose-CodexNetwork.cmd`，检查结果。HTTP 和 WebSocket 都为 `ok` 才算全部通过。

启动器会查找常见安装位置，以及当前用户安装的 OpenAI Store 包中的应用清单。安装位置无法自动识别时，在项目目录打开 PowerShell，手动指定真实的可执行文件：

```powershell
.\windows\Start-CodexProxy.ps1 -AppPath 'C:\实际安装目录\Codex.exe'
```

也可以在命令提示符中使用双击入口传参，路径带空格时保留引号：

```bat
windows\Start-CodexProxy.cmd -AppPath "C:\实际安装目录\Codex.exe"
```

明确指定代理时，替换下面示例中的端口。这里的 `12345` 只是示例，不是项目默认值：

```powershell
.\windows\Start-CodexProxy.ps1 -ProxyUrl 'http://127.0.0.1:12345'
.\windows\Diagnose-CodexNetwork.ps1 -ProxyUrl 'http://127.0.0.1:12345'
```

诊断会查找桌面应用内的 Codex CLI，再查找 PATH 上的 CLI。如果提示找不到，可以显式指定：

```powershell
.\windows\Diagnose-CodexNetwork.ps1 -CodexPath 'C:\实际目录\codex.exe'
```

`.cmd` 入口只为本次 PowerShell 子进程设置 `ExecutionPolicy Bypass`，不会永久更改执行策略。若设备受组织策略管理，请遵循管理员要求。Store 包如不允许直接启动 `.exe`，入口会报错；目前没有实现带自定义环境的 Store 激活桥接，也不会通过修改全局环境来绕过它。

## macOS 快速开始

需要已安装的 ChatGPT 桌面应用，默认位置是 `/Applications/ChatGPT.app`。启动器本身声明最低 macOS 12.0，实际运行条件还取决于你安装的桌面应用。启动使用系统自带的 `zsh`、`curl`、`scutil`、`lsof` 和 `osascript`，诊断额外需要 `jq`。

1. 下载或克隆整个仓库，解压到准备长期保留的位置。
2. 打开代理客户端，确认节点可用。
3. 手动退出 ChatGPT，再双击 `Codex Proxy.app`。
4. 多条路线可用时，选择本次使用的路线。没有可用路线时，可以选择打开 Shadowrocket、FlClash 或重新检测。
5. 运行 `diagnose-codex-network.command` 查看 HTTP 和 WebSocket 结果。

App 未签名，也未公证。如果 macOS 阻止打开，可在终端从项目目录运行脚本；按系统提示确认来源后再决定是否允许打开，不需要关闭 Gatekeeper：

```sh
/bin/zsh './Codex Proxy.app/Contents/MacOS/codex-proxy-launcher'
/bin/zsh ./diagnose-codex-network.command
```

可以把 App 拖到 Dock。Dock 保存的是入口位置，移动整个项目后需要重新添加。

诊断同时兼容新版 `Contents/Resources/codex-cli/bin/codex`、旧版 `Contents/Resources/codex` 和 PATH 中的 CLI。可以用 `CODEX_PROXY_CODEX_BIN` 指定其他位置；桌面应用路径可以用 `CODEX_PROXY_APP_BUNDLE` 或 `CODEX_PROXY_APP_BIN` 覆盖。

## 为什么浏览器能用，Codex 还会重连

浏览器、桌面界面和 Codex 后端可能使用不同的网络组件。代理客户端打开系统 HTTP/HTTPS 代理后，不能据此确认每个组件都读到了相同设置。WebSocket 还需要完成握手并维持连接，普通 HTTP 请求成功不足以证明它能用。

本项目的显式代理模式设置 `HTTP_PROXY`、`HTTPS_PROXY` 及其小写形式，并清除继承的 `ALL_PROXY`、`WS_PROXY`、`WSS_PROXY`。对读取 `HTTPS_PROXY` 的安全 WebSocket 客户端，连接可以通过 HTTP 代理的 CONNECT 隧道到达服务器，再完成 WebSocket 握手。无需因为目标是 `wss://`，就额外设置一组 `WS_PROXY` 变量。

“重连五次后才成功”与 WebSocket 路线失败、重试或回退相符，但单凭次数无法判断根因。Codex 官方文档记录了 [WebSocket 回退 HTTP 的指标](https://learn.chatgpt.com/docs/config-file/config-advanced#runtime-and-model-transport)，实际行为仍取决于应用版本、配置和错误类型。不要把 FlClash 统一描述成不支持 WebSocket，也不要把本工具理解成关闭 WebSocket。

## 路线怎样选择

按以下顺序检测，端口是否正在监听只用于发现候选项：

1. 如果显式传入代理 URL，只验证这一条，失败就停止。
2. 清除显式代理影响，检查系统网络或 TUN 是否已能访问 OpenAI。成功就直接使用。
3. 读取系统当前启用的 HTTP/HTTPS 代理，再检查 FlClash、Clash/Mihomo 等进程的本地监听端口。
4. 对候选代理发起真实 HTTP 请求，只保留通过探测的路线。

探测默认访问 `https://api.openai.com/v1/models`。未登录请求返回 `401` 也说明已得到 HTTP 响应，但这不代表账号、模型权限或 WebSocket 正常。启动入口只做 HTTP 预检，**完整的 HTTP 与 WebSocket 检查需要另跑诊断入口**。

桌面应用通过这个入口启动后，子进程才能继承选定环境。应用已运行时再次点击入口，只会提示状态或要求手动退出，不会给现有进程补上代理。

## 终端用法

### macOS / Zsh

在项目根目录执行一次：

```zsh
source ./shell/proxy.zsh
proxy_auto
codex_auto --version
proxy_off
```

`proxy_auto` 修改当前终端的代理变量，`proxy_off` 清除它们。`codex_auto` 在子 shell 中选择路线并运行 PATH 上的 `codex`，结束后不改变父终端环境。项目不会自动编辑 `~/.zshrc`；需要每次可用时，可自行把上述 `source` 改为项目的绝对路径并加入自己的 shell 配置。

### Windows / PowerShell

```powershell
.\windows\Start-CodexCLI.ps1 -CodexArguments '--version'
```

也可传入 `-CodexPath`、`-ProxyUrl`。本次命令结束后会恢复调用它的 PowerShell 进程环境。

## 诊断与常见问题

| 结果或现象 | 接下来检查什么 |
| --- | --- |
| 没有可用路线 | 代理客户端是否已运行、节点是否可用；试着显式指定真实 HTTP 端口 |
| HTTP 通过，WebSocket 失败 | 代理规则、CONNECT 支持、TLS 拦截、上游服务和应用版本 |
| WebSocket 显示 `HTTP 101 Switching Protocols` | 这次握手成功；之后的断流仍需检查网络切换和长连接稳定性 |
| HTTP 为 `warning` | 查看摘要，可能是更新/CDN 等额外端点失败；不能仅据此判断模型请求失败 |
| 找不到 `codex doctor` 或 JSON 字段 | 使用带该命令的 CLI 版本，或显式指定 `CodexPath` / `CODEX_PROXY_CODEX_BIN` |
| Windows 桌面应用找不到或打不开 | 指定 `-AppPath`；确认安装包允许直接运行对应 `.exe` |
| 应用已运行 | 手动退出后从本入口重新启动，现有进程不会继承新环境 |

诊断只按 `network.provider_reachability` 和 `network.websocket_reachability` 判断，不把 doctor 的其他本机检查失败算成网络故障。两项中有 `warning` 或 `fail` 时，诊断返回非零退出码。

## 配置与边界

| 参数或变量 | 作用 |
| --- | --- |
| `HTTP_PROXY_URL` | 明确指定本次 HTTP 代理；Windows 也可用 `-ProxyUrl` |
| `NO_PROXY_HOSTS` | 临时覆盖绕过代理的主机列表，默认 `localhost,127.0.0.1,::1` |
| `CODEX_PROXY_APP_BIN` | 桌面应用可执行文件；Windows 也可用 `-AppPath` |
| `CODEX_PROXY_CODEX_BIN` | 诊断或 CLI 使用的 Codex 路径；Windows 也可用 `-CodexPath` |

Windows 当前支持 `http://` 代理 URL，通过 CONNECT 承载 HTTPS/WSS；macOS 路线模块也接受 `https://` 代理 URL。自动发现不解析 PAC 脚本，也不支持 SOCKS-only 端口。此时可以使用 TUN，或提供代理客户端的 HTTP/mixed 端口。

显式路线会让本次桌面应用及子进程使用同一 HTTP 代理。系统/TUN 模式会清除旧代理变量。桌面启动与诊断还会设置进程级 Git 代理，避免历史全局固定端口干扰，不修改 `~/.gitconfig`；URL 专用 Git 配置和命令显式覆盖仍可能优先，需要结合有效配置检查。

启动入口保留 `--disable-quic` 参数，它针对使用该参数的 Chromium 网络栈，不能用来证明 Codex 的 WebSocket 路线正确。本项目不修改系统代理、DNS、桌面应用文件、账号配置或代理订阅，也不持续监控或切换网络。ChatGPT 统一桌面应用中的其他功能也可能继承本次环境。

## 日志与反馈

精简启动日志保存在项目的 `logs/` 下，单个日志达到 1 MiB 后轮转，最多保留三个历史文件。日志只记录启动事件、PID 和脱敏路线，不捕获应用完整输出。macOS 另外保存一次启动状态，供再次点击时核对 PID。

报告问题时，请提供系统版本、桌面应用/CLI 版本、代理客户端及模式、两个网络检查的状态和错误摘要。提交前自行检查输出，隐藏用户名、私人路径、代理账号密码和其他个人信息。不要上传 `auth.json`、完整 doctor 报告、会话内容、订阅链接或 `logs/`。

## 开发与验证

```sh
# macOS: syntax, route behavior and shell helpers
./tests/test-proxy-contract.zsh
```

```powershell
# Windows PowerShell 5.1 / PowerShell 7
.\tests\test-windows.ps1
```

测试用替身模拟网络、系统代理和进程，不改系统配置，也不消耗模型请求。GitHub Actions 会在 macOS 和原生 Windows runner 上执行相应测试；这些测试不包含真实桌面应用、Store 激活或代理节点的验收。

进一步阅读：[架构与维护](docs/ARCHITECTURE.md)、[功能阶段与技术说明](docs/PROJECT_OVERVIEW.md)、[贡献说明](CONTRIBUTING.md)。

这是独立社区工具，与 OpenAI、FlClash 等项目无隶属关系。代码和文档采用 [MIT License](LICENSE)；历史图标素材的说明见 [NOTICE](NOTICE.md)。
