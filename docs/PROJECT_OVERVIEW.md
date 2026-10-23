# 功能阶段与技术说明

## 项目解决的问题

代理客户端已经运行，浏览器也能访问网站，Codex 却仍然反复重连。这时需要确认的是：桌面应用中的 Codex 进程究竟使用了哪条路线，这条路线是否支持所需的 HTTP 请求和 WebSocket 握手。

启动器把路线发现、HTTP 预检和进程环境设置放在同一条流程中，诊断入口再检查 Codex 自己的 HTTP 与 Responses WebSocket 结果。它减少手动找端口、配置环境变量和猜测连接状态的工作。

## 功能怎样演进

下表按职责划分阶段。Git 历史目前只保留早期基线，不能据此推断每个阶段的开发日期。

| 阶段 | 实现内容 | 技术 | 解决的问题 |
| --- | --- | --- | --- |
| 基础启动 | 给桌面应用传递 HTTP/HTTPS 代理环境，清除竞争代理变量 | Zsh、macOS App Bundle、`nohup` | GUI 启动与终端环境不同，Codex 进程未必使用预期代理 |
| 动态路线 | 优先系统/TUN，随后读取系统代理和代理进程监听端口，逐条 HTTP 验证 | `curl`、`scutil`、`lsof`、`awk` | 固定端口不通、代理客户端切换、端口在监听但节点不可用 |
| 环境一致 | 启动、诊断共用路线模块，为子进程追加 Git 代理配置 | 共享函数、环境变量、`GIT_CONFIG_COUNT` | 不同入口走不同路线，旧 Git 全局代理继续干扰 |
| 状态与排障 | 重复点击核对 PID、精简日志、脱敏和轮转、独立 WebSocket 诊断 | AppleScript、JXA、`codex doctor --json`、`jq` | 只有重连提示，缺少可核对的启动路线与握手结果 |
| 终端复用 | 提供可 source 的 `proxy_auto`、`proxy_off`、`codex_auto` | Zsh 函数、子 shell | 原本只存在于个人 shell 配置里的命令无法直接分享 |
| Windows | 桌面双击入口、系统代理与监听发现、临时环境注入、诊断与 CLI | PowerShell 5.1/7、.NET、注册表只读查询、Appx 清单 | macOS 的工具链和 App Bundle 无法直接运行在 Windows |
| 开源交付 | 完整使用说明、许可证、隐私约束、跨平台测试 | Markdown、GitHub Actions、测试替身 | 接收者不知道安装条件、运行入口和成功边界 |
| 用户安装 | 分平台 Release 压缩包、Windows 当前用户安装器与快捷方式、应用路径记忆 | Python 标准库、PowerShell、WScript.Shell | 接收者需要自己配置路径、长期保留下载目录和寻找脚本入口 |

## WebSocket 与 HTTP 代理是什么关系

安全 WebSocket 的目标通常是 `wss://`。读取 `HTTPS_PROXY` 的客户端可以先连接 HTTP 代理，通过 CONNECT 建立到目标的隧道，在隧道里完成 TLS 和 WebSocket 握手。HTTP 代理与 WebSocket 并不天然冲突。

需要区分三种状态：

- 代理进程和端口存在，只证明本机有人在监听。
- 对 OpenAI 的 HTTP 请求收到响应，说明该次 HTTP 探测有结果，不能替代 WebSocket 测试。
- WebSocket 返回 HTTP 101，说明该次握手完成，不能保证后续长连接稳定。

Codex 的实际传输方式由版本、配置和服务端决定。官方文档中的 [传输指标](https://learn.chatgpt.com/docs/config-file/config-advanced#runtime-and-model-transport) 包括 WebSocket 回退 HTTP 的计数，但没有据此保证任意版本都固定在第 5 次重连后回退。因此，本项目把重复重连当作待诊断现象，不把它当成确定根因。

## 当前实现的边界

macOS 与 Windows 共用路线语义，各自使用本机工具实现。Windows 不依赖 Zsh、Homebrew 或 `jq`，通过 .NET 处理 HTTP 探测和 JSON。macOS 的系统/TUN 探测用 `curl --noproxy '*'`，显式代理探测用空的 `--noproxy` 列表，防止继承的绕过规则改变结果。

Windows 桌面入口根据常见安装目录和已注册的 OpenAI Appx 包寻找 `.exe`，通过 `UseShellExecute=false` 启动以传递环境。某些 Store 包可能要求激活服务；这种情况需要在真实设备上验证，本项目没有为它实现环境注入桥接。WSL 与远程执行环境也不承诺继承 Windows 原生进程环境。

测试覆盖路线选择、错误覆盖不回退、代理变量清理、Git 配置保留、环境恢复、日志和诊断判断。模拟测试与原生 Windows runner 能发现脚本问题，真实桌面应用的登录、联网和持续响应仍需要用户设备上的验收。
