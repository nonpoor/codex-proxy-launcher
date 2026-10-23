#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
ROUTE_LIB="$ROOT_DIR/lib/proxy-route.zsh"
GIT_BIN="${CODEX_PROXY_GIT_BIN:-/usr/bin/git}"
NO_PROXY_HOSTS="${NO_PROXY_HOSTS:-localhost,127.0.0.1,::1}"
REPORT_FILE="$(/usr/bin/mktemp -t codex-network-doctor)"
trap '/bin/rm -f "$REPORT_FILE"' EXIT

if [[ ! -r "$ROUTE_LIB" ]]; then
  echo "找不到代理路由模块：$ROUTE_LIB"
  exit 1
fi
source "$ROUTE_LIB"
source "$ROOT_DIR/lib/codex-runtime.zsh"
CODEX_BIN="$(codex_runtime_find)" || {
  echo "找不到 Codex CLI。请安装桌面应用或 CLI，或设置 CODEX_PROXY_CODEX_BIN。"
  exit 1
}

if [[ -n "${CODEX_PROXY_JQ_BIN:-}" ]]; then
  JQ_BIN="$CODEX_PROXY_JQ_BIN"
elif [[ -x "/opt/homebrew/bin/jq" ]]; then
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

if [[ -z "$JQ_BIN" || ! -x "$JQ_BIN" ]]; then
  echo "找不到 jq，无法读取 Codex doctor 的 JSON 结果。"
  exit 1
fi

ROUTE_RESULT=0
ROUTE_OUTPUT="$(proxy_route_resolve)" || ROUTE_RESULT=$?
case "$ROUTE_RESULT" in
  0)
    ;;
  2)
    echo "HTTP_PROXY_URL 已设置，但格式无效或当前无法连通。"
    exit 1
    ;;
  *)
    echo "没有检测到可访问 OpenAI 的系统/TUN 或本地 HTTP 代理。"
    echo "请先打开 Shadowrocket 或 FlClash，再重新运行诊断。"
    exit 1
    ;;
esac

typeset -a ROUTE_MODES ROUTE_SOURCES ROUTE_URLS
while IFS=$'\t' read -r route_mode route_source route_url; do
  [[ -n "$route_mode" && -n "$route_source" && -n "$route_url" ]] || continue
  ROUTE_MODES+=("$route_mode")
  ROUTE_SOURCES+=("$route_source")
  ROUTE_URLS+=("$route_url")
done <<< "$ROUTE_OUTPUT"

if (( ${#ROUTE_MODES} == 0 )); then
  echo "代理路由检测返回了空结果。"
  exit 1
fi

SELECTED_MODE="$ROUTE_MODES[1]"
SELECTED_SOURCE="$ROUTE_SOURCES[1]"
SELECTED_URL="$ROUTE_URLS[1]"
DISPLAY_URL="$(proxy_route_redact_url "$SELECTED_URL")"
ROUTE_SUMMARY="$(proxy_route_describe "$SELECTED_MODE" "$SELECTED_SOURCE" "$SELECTED_URL")"

if ! proxy_route_apply_environment "$SELECTED_MODE" "$SELECTED_URL" "$NO_PROXY_HOSTS"; then
  echo "无法应用检测到的代理路线。"
  exit 1
fi

echo "Codex：$("$CODEX_BIN" --version 2>/dev/null || true)"
echo "网络路线：$ROUTE_SUMMARY"
if [[ -x "$GIT_BIN" ]]; then
  EFFECTIVE_GIT_PROXY="$("$GIT_BIN" config --get-urlmatch http.proxy \
    https://github.com/openai/skills.git 2>/dev/null || true)"
  if [[ "$SELECTED_MODE" == "system" ]]; then
    if [[ -n "$EFFECTIVE_GIT_PROXY" ]]; then
      echo "Git 路线：与系统/TUN 不一致 — $(proxy_route_redact_url "$EFFECTIVE_GIT_PROXY")"
      exit 1
    fi
    echo "Git 路线：未固定代理，跟随系统/TUN"
  else
    if [[ "$EFFECTIVE_GIT_PROXY" != "$SELECTED_URL" ]]; then
      echo "Git 路线：与所选代理不一致 — $(proxy_route_redact_url "$EFFECTIVE_GIT_PROXY")"
      exit 1
    fi
    echo "Git 路线：跟随本次代理 — $DISPLAY_URL"
  fi
else
  echo "Git 路线：未检查（找不到 Git）"
fi
if (( ${#ROUTE_MODES} > 1 )); then
  echo "另有 $(( ${#ROUTE_MODES} - 1 )) 条路线通过探测；诊断按检测顺序使用第一条。"
fi
echo "正在检查 HTTP 与 Responses WebSocket……"

set +e
"$CODEX_BIN" doctor --json > "$REPORT_FILE"
DOCTOR_EXIT=$?
set -e

if ! "$JQ_BIN" -e \
  '.checks["network.provider_reachability"] and .checks["network.websocket_reachability"]' \
  "$REPORT_FILE" >/dev/null 2>&1; then
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
if ! "$JQ_BIN" -e '
  .checks["network.provider_reachability"].status == "ok" and
  .checks["network.websocket_reachability"].status == "ok"
' "$REPORT_FILE" >/dev/null; then
  RESULT=1
fi

echo
if (( RESULT == 0 )); then
  if [[ "$SELECTED_MODE" == "system" ]]; then
    echo "结论：当前系统/TUN 路线的 HTTP 与 Responses WebSocket 检查均通过。"
  else
    echo "结论：当前 HTTP 与 Responses WebSocket 已通过所选 HTTP 代理完成检查。"
  fi
else
  echo "结论：HTTP 或 WebSocket 至少有一项未通过检查。"
fi

if [[ -t 0 ]]; then
  read -r "?按回车键关闭……"
fi

exit "$RESULT"
