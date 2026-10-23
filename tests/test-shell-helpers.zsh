#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/shell/proxy.zsh"
[[ "$CODEX_PROXY_ROUTE_LIB" == "$ROOT_DIR/lib/proxy-route.zsh" ]]
source "$CODEX_PROXY_ROUTE_LIB"
proxy_route_probe_code_ok 401
if proxy_route_probe_code_ok 407; then
  print -u2 -- 'proxy authentication error must not pass route validation'
  exit 1
fi
proxy_route_resolve() { print -r -- $'system\tsystem/TUN\t-'; }
# Source normally restores real implementations, so use a temporary fake module.
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/routes.zsh" <<'FAKE'
proxy_route_resolve() { print -r -- $'explicit\ttest\thttp://localhost:4567'; }
proxy_route_apply_shell_environment() { export HTTPS_PROXY="$2"; }
proxy_route_describe() { print -r -- "$2"; }
proxy_route_clear_environment() { unset HTTPS_PROXY; }
FAKE
CODEX_PROXY_ROUTE_LIB="$TEST_DIR/routes.zsh"
HTTPS_PROXY=http://old.invalid:9999
proxy_auto >/dev/null
[[ "$HTTPS_PROXY" == http://localhost:4567 ]]
proxy_off >/dev/null
[[ -z "${HTTPS_PROXY:-}" ]]
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/codex" <<'FAKE'
#!/bin/zsh
print -r -- "$HTTPS_PROXY|$*"
FAKE
chmod +x "$TEST_DIR/bin/codex"
export PATH="$TEST_DIR/bin:$PATH"
export HTTPS_PROXY=http://old.invalid:9999
[[ "$(codex_auto --version | tail -n 1)" == 'http://localhost:4567|--version' ]]
[[ "$HTTPS_PROXY" == http://old.invalid:9999 ]]
source "$ROOT_DIR/lib/codex-runtime.zsh"
CODEX_PROXY_CODEX_BIN="$TEST_DIR/bin/codex"
[[ "$(codex_runtime_find)" == "$TEST_DIR/bin/codex" ]]
CODEX_PROXY_CODEX_BIN="$TEST_DIR/missing"
if codex_runtime_find; then
  print -u2 -- 'bad explicit runtime must fail'
  exit 1
fi
print -r -- 'shell helpers: ok'
