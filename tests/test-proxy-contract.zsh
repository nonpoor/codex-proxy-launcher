#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
LAUNCHER="$ROOT_DIR/Codex Proxy.app/Contents/MacOS/codex-proxy-launcher"
DIAGNOSTIC="$ROOT_DIR/diagnose-codex-network.command"

fail() {
  echo "proxy contract failed: $1" >&2
  exit 1
}

/bin/zsh -n "$LAUNCHER"
/bin/zsh -n "$DIAGNOSTIC"

/usr/bin/grep -Fq 'export HTTP_PROXY="$HTTP_PROXY_URL"' "$LAUNCHER" \
  || fail "launcher must export HTTP_PROXY"
/usr/bin/grep -Fq 'export HTTPS_PROXY="$HTTP_PROXY_URL"' "$LAUNCHER" \
  || fail "launcher must export HTTPS_PROXY"
/usr/bin/grep -Fq 'unset WS_PROXY WSS_PROXY ALL_PROXY ws_proxy wss_proxy all_proxy' "$LAUNCHER" \
  || fail "launcher must clear unsupported or fallback proxy variables"

if /usr/bin/grep -Eq '^export (WS_PROXY|WSS_PROXY|ALL_PROXY|ws_proxy|wss_proxy|all_proxy)=' "$LAUNCHER"; then
  fail "launcher must not export WS_PROXY, WSS_PROXY, or ALL_PROXY"
fi

if /usr/bin/grep -Fq 'SOCKS_PROXY_URL' "$LAUNCHER"; then
  fail "launcher must not retain the old SOCKS proxy path"
fi

/usr/bin/grep -Fq 'HTTPS_PROXY="$PROXY_URL"' "$DIAGNOSTIC" \
  || fail "diagnostic must exercise HTTPS_PROXY"

echo "proxy contract: ok"
