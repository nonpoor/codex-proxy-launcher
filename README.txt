ChatGPT / Codex Proxy Launcher

用途：
双击 "Codex Proxy.app" 启动新版 ChatGPT 桌面应用（内含 Chat、Work 和 Codex），并给该应用的进程树注入本机代理环境变量和 --disable-quic。
它不设置全局 GUI 环境变量，不改 ChatGPT.app，不改系统代理。
由于 Codex 已并入 ChatGPT 桌面应用，代理会作用于整个统一应用，不能再只作用于 Codex 功能。

当前 Codex 的 wss:// 连接通过 HTTPS_PROXY 选择代理：先连接本机 HTTP 代理，再以 CONNECT 建立 TLS 隧道，最后完成 WebSocket Upgrade。WS_PROXY/WSS_PROXY 不是当前 Codex 识别的代理变量。

使用：
1. 先启动 FlClash，确认 127.0.0.1:7890 可用。
2. 双击本目录下的 "Codex Proxy.app"。
3. 如果 ChatGPT 已经在运行，启动器只会提示你先手动退出 ChatGPT，不会自动关闭当前会话。
4. 可以把 "Codex Proxy.app" 拖到 Dock，以后点它启动。

日志：
/Users/nonpoor/daily/codex-proxy-launcher/logs/codex-proxy.log

当前代理参数：
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,api.github.com
no_proxy=localhost,127.0.0.1,api.github.com

启动器会清除继承到进程中的 WS_PROXY、WSS_PROXY 和 ALL_PROXY，避免统一应用里的不同网络组件在 HTTP 与 SOCKS 两条路径之间分流。

分流原则：
- ChatGPT / Codex 的 HTTPS 与 WebSocket、GitHub 网页与 Raw 内容、npm registry 继续走 127.0.0.1:7890。
- 仅 api.github.com 绕过显式代理，避免共享代理出口耗尽 GitHub 匿名 REST API 配额。
- 不要把 github.com 或 *.githubusercontent.com 整体加入 NO_PROXY。

--disable-quic 作用于 ChatGPT 的 Electron 网络栈；Codex Responses WebSocket 使用 TCP/TLS，它的代理入口由 HTTPS_PROXY 决定。

DNS：
- 启动器不设置或写死 DNS，域名解析沿用 macOS 当前的系统 / DHCP DNS。
- 校园网 DNS 地址变化时不需要修改启动器；切换网络后重新运行下方验证即可。

验证：
双击 diagnose-codex-network.command，或在终端执行：
/Users/nonpoor/daily/codex-proxy-launcher/diagnose-codex-network.command

脚本只显示脱敏后的 HTTP 与 WebSocket 检查结果，不输出登录 token。预期结果：
- HTTP 状态为 ok。
- WebSocket 状态为 ok。
- 握手结果为 HTTP 101 Switching Protocols。

成功边界：
- HTTP 101 证明检查时的 Responses WebSocket 已经经过代理并完成升级。
- 启动器不能保证长连接之后永不中断；代理节点、网络切换或上游关闭连接仍可能触发 Codex 的 5 次重试和 HTTPS 回退。
- 附件密集任务如果把大量渲染图片保留在活动上下文中，会增加 WebSocket 传输压力；遇到反复重连时应先压缩上下文或新建任务继续。
