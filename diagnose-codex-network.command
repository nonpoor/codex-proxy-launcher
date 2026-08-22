#!/bin/zsh
set -euo pipefail

CODEX_BIN="/Applications/ChatGPT.app/Contents/Resources/codex"
PROXY_URL="${HTTP_PROXY_URL:-http://127.0.0.1:7890}"
NO_PROXY_HOSTS="${NO_PROXY_HOSTS:-localhost,127.0.0.1,api.github.com}"
REPORT_FILE="$(/usr/bin/mktemp -t codex-network-doctor)"
trap '/bin/rm -f "$REPORT_FILE"' EXIT

if [[ -x "/opt/homebrew/bin/jq" ]]; then
  JQ_BIN="/opt/homebrew/bin/jq"
elif [[ -x "/usr/local/bin/jq" ]]; then
  JQ_BIN="/usr/local/bin/jq"
else
  JQ_BIN="$(command -v jq 2>/dev/null || true)"
fi

if [[ ! -x "$CODEX_BIN" ]]; then
  echo "找不到 Codex：$CODEX_BIN"
  exit 1
fi

if [[ -z "$JQ_BIN" ]]; then
  echo "找不到 jq，无法读取 Codex doctor 的 JSON 结果。"
  exit 1
fi

if ! /usr/bin/nc -z 127.0.0.1 7890 >/dev/null 2>&1; then
  echo "代理端口不可用：127.0.0.1:7890"
  exit 1
fi

echo "Codex：$("$CODEX_BIN" --version 2>/dev/null || true)"
echo "代理端口：127.0.0.1:7890 可用"
echo "正在检查 HTTP 与 Responses WebSocket……"

set +e
/usr/bin/env \
  -u WS_PROXY -u WSS_PROXY -u ALL_PROXY \
  -u ws_proxy -u wss_proxy -u all_proxy \
  HTTP_PROXY="$PROXY_URL" \
  HTTPS_PROXY="$PROXY_URL" \
  http_proxy="$PROXY_URL" \
  https_proxy="$PROXY_URL" \
  NO_PROXY="$NO_PROXY_HOSTS" \
  no_proxy="$NO_PROXY_HOSTS" \
  "$CODEX_BIN" doctor --json > "$REPORT_FILE"
DOCTOR_EXIT=$?
set -e

if ! "$JQ_BIN" -e '.checks["network.provider_reachability"] and .checks["network.websocket_reachability"]' "$REPORT_FILE" >/dev/null 2>&1; then
  echo "Codex doctor 没有返回可读取的网络诊断结果（退出码：$DOCTOR_EXIT）。"
  exit 1
fi

"$JQ_BIN" -r '
  .checks as $checks |
  "HTTP：\($checks["network.provider_reachability"].status) — \($checks["network.provider_reachability"].summary)",
  "WebSocket：\($checks["network.websocket_reachability"].status) — \($checks["network.websocket_reachability"].summary)",
  "握手结果：\($checks["network.websocket_reachability"].details["handshake result"] // "无")",
  "握手耗时：\($checks["network.websocket_reachability"].durationMs) ms",
  "识别到的代理变量：\($checks["network.websocket_reachability"].details["proxy env vars present"] // "无")"
' "$REPORT_FILE"

RESULT=0
if ! "$JQ_BIN" -e '.checks["network.websocket_reachability"].status == "ok"' "$REPORT_FILE" >/dev/null; then
  RESULT=1
fi

echo
if (( RESULT == 0 )); then
  echo "结论：当前 Responses WebSocket 已通过代理完成握手。"
else
  echo "结论：当前 WebSocket 未通过检查；HTTPS 回退仍可能可用。"
fi

if [[ -t 0 ]]; then
  read -r "?按回车键关闭……"
fi

exit "$RESULT"
