# 参与维护

修改前先阅读 [README](README.md) 和 [架构说明](docs/ARCHITECTURE.md)。优先提交能复现的问题和范围明确的修复。

## 报告问题

请说明操作系统、桌面应用/CLI 版本、代理客户端、TUN 或系统代理模式、使用的入口，以及 HTTP/WebSocket 检查结果。描述预期行为与实际行为，能复现时附上操作步骤。

公开提交前检查内容，移除代理凭据、订阅链接、个人路径、账号信息和会话内容。不要上传 `auth.json`、`.env`、完整 doctor JSON 或启动日志。测试中的 `alice:secret` 是虚构占位数据，不是真实凭据。

## 本地验证

macOS：

```sh
./tests/test-proxy-contract.zsh
git diff --check
```

Windows PowerShell 5.1 或 PowerShell 7：

```powershell
.\tests\test-windows.ps1
git diff --check
```

测试应使用临时目录和替身，不要求用户关闭应用，不改系统代理、DNS、执行策略、Git 全局配置或认证信息。修改平台适配代码时，同时说明在哪个系统上做了真实验证。

## 维护约定

保持 macOS 与 Windows 的路线优先级一致。不要添加固定代理端口，除非它只出现在测试或明确标为示例的命令里。显式覆盖失败时应报错，不能偷偷换另一条路线。

新增代理客户端支持时，进程名和监听端口只用于发现候选项，使用前仍需验证。启动预检与 WebSocket 握手是两层证据，文案不能混为一谈。

依赖保持在系统工具和当前脚本语言范围内，避免为少量功能增加服务、安装器或常驻进程。行为变化要同步 README 和必要的目标测试。
