#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
LAUNCHER="$ROOT_DIR/Codex Proxy.app/Contents/MacOS/codex-proxy-launcher"
DIAGNOSTIC="$ROOT_DIR/diagnose-codex-network.command"
ROUTE_LIB="$ROOT_DIR/lib/proxy-route.zsh"
BEHAVIOR_TEST="$ROOT_DIR/tests/test-proxy-behavior.zsh"

fail() {
  echo "proxy contract failed: $1" >&2
  exit 1
}

[[ -x "$LAUNCHER" ]] || fail "launcher must be executable"
[[ -x "$DIAGNOSTIC" ]] || fail "diagnostic must be executable"
[[ -x "$ROUTE_LIB" ]] || fail "shared proxy route module must be executable"
[[ -x "$BEHAVIOR_TEST" ]] || fail "behavior test must be executable"

/bin/zsh -n "$LAUNCHER"
/bin/zsh -n "$DIAGNOSTIC"
/bin/zsh -n "$ROUTE_LIB"

if /usr/bin/grep -Eq '127\.0\.0\.1:7890|localhost:7890' \
  "$LAUNCHER" "$DIAGNOSTIC" "$ROUTE_LIB" "$ROOT_DIR/README.txt"; then
  fail "production files must not hard-code port 7890"
fi

if /usr/bin/grep -Eq '^[[:space:]]*export (WS_PROXY|WSS_PROXY|ALL_PROXY|ws_proxy|wss_proxy|all_proxy)=' \
  "$LAUNCHER" "$DIAGNOSTIC" "$ROUTE_LIB"; then
  fail "WS_PROXY, WSS_PROXY, and ALL_PROXY must never be exported"
fi

if /usr/bin/grep -Fq 'codex-proxy.log' "$LAUNCHER"; then
  fail "launcher must not append to the legacy full-output log"
fi

"$BEHAVIOR_TEST"
/bin/zsh "$ROOT_DIR/tests/test-shell-helpers.zsh"

echo "proxy contract: ok"
