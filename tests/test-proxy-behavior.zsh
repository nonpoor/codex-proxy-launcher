#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
ROUTE_LIB="$ROOT_DIR/lib/proxy-route.zsh"
LAUNCHER="$ROOT_DIR/Codex Proxy.app/Contents/MacOS/codex-proxy-launcher"
DIAGNOSTIC="$ROOT_DIR/diagnose-codex-network.command"
TEST_TMP="$(/usr/bin/mktemp -d -t codex-proxy-tests)"
FAKE_BIN_DIR="$TEST_TMP/bin"
TEST_GIT_CONFIG="$TEST_TMP/gitconfig"
typeset -i ASSERTIONS=0

cleanup() {
  [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && /bin/rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
  echo "proxy behavior failed: $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  (( ASSERTIONS += 1 ))
  [[ "$actual" == "$expected" ]] \
    || fail "$message (expected=${(qqq)expected}, actual=${(qqq)actual})"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  (( ASSERTIONS += 1 ))
  [[ "$haystack" == *"$needle"* ]] || fail "$message (missing=${(qqq)needle})"
}

assert_file_exists() {
  local path="$1"
  local message="$2"
  (( ASSERTIONS += 1 ))
  [[ -f "$path" ]] || fail "$message ($path)"
}

assert_file_absent() {
  local path="$1"
  local message="$2"
  (( ASSERTIONS += 1 ))
  [[ ! -e "$path" ]] || fail "$message ($path)"
}

wait_for_file() {
  local path="$1"
  local attempt
  for attempt in {1..100}; do
    [[ -f "$path" ]] && return 0
    /bin/sleep 0.02
  done
  return 1
}

/bin/mkdir -p "$FAKE_BIN_DIR"
/usr/bin/git config --file "$TEST_GIT_CONFIG" http.proxy http://127.0.0.1:1082

FAKE_CURL="$FAKE_BIN_DIR/curl"
FAKE_SCUTIL="$FAKE_BIN_DIR/scutil"
FAKE_LSOF="$FAKE_BIN_DIR/lsof"
FAKE_OSASCRIPT="$FAKE_BIN_DIR/osascript"
FAKE_OPEN="$FAKE_BIN_DIR/open"
FAKE_APP="$FAKE_BIN_DIR/ChatGPT-test"
FAKE_CODEX="$FAKE_BIN_DIR/codex-test"

/bin/cat > "$FAKE_CURL" <<'FAKE'
#!/bin/zsh
set -u
[[ "${1:-}" == "--disable" ]] || exit 90
proxy_url=""
while (( $# > 0 )); do
  case "$1" in
    --proxy)
      proxy_url="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$proxy_url" ]]; then
  code="${FAKE_CURL_DIRECT_CODE:-000}"
  print -nr -- "$code"
  [[ "$code" != "000" ]]
  exit $?
fi

valid_proxy=""
for valid_proxy in ${(s:,:)FAKE_CURL_VALID_PROXIES:-}; do
  if [[ "$proxy_url" == "$valid_proxy" ]]; then
    print -nr -- "401"
    exit 0
  fi
done

print -nr -- "000"
exit 7
FAKE

/bin/cat > "$FAKE_SCUTIL" <<'FAKE'
#!/bin/zsh
set -u
[[ "${1:-}" == "--proxy" ]] || exit 2
print -r -- "${FAKE_SCUTIL_OUTPUT:-}"
FAKE

/bin/cat > "$FAKE_LSOF" <<'FAKE'
#!/bin/zsh
set -u
print -r -- "${FAKE_LSOF_OUTPUT:-}"
FAKE

/bin/cat > "$FAKE_OSASCRIPT" <<'FAKE'
#!/bin/zsh
set -u
args="$*"
if [[ -n "${FAKE_OSASCRIPT_FIXED_RESPONSE:-}" ]]; then
  print -r -- "$FAKE_OSASCRIPT_FIXED_RESPONSE"
elif [[ -n "${FAKE_OSASCRIPT_CHOICE_ONCE:-}" && "$args" == *"打开 Shadowrocket"* ]]; then
  if [[ ! -e "${FAKE_OSASCRIPT_STATE:?}" ]]; then
    /usr/bin/touch "$FAKE_OSASCRIPT_STATE"
    print -r -- "$FAKE_OSASCRIPT_CHOICE_ONCE"
  fi
fi
exit 0
FAKE

/bin/cat > "$FAKE_OPEN" <<'FAKE'
#!/bin/zsh
set -u
print -r -- "$*" >> "${FAKE_OPEN_CAPTURE:?}"
FAKE

/bin/cat > "$FAKE_APP" <<'FAKE'
#!/bin/zsh
set -u
git_http_proxy="$(/usr/bin/git config --get-urlmatch http.proxy https://github.com/openai/skills.git 2>/dev/null || true)"
{
  print -r -- "HTTP_PROXY=${HTTP_PROXY-unset}"
  print -r -- "HTTPS_PROXY=${HTTPS_PROXY-unset}"
  print -r -- "http_proxy=${http_proxy-unset}"
  print -r -- "https_proxy=${https_proxy-unset}"
  print -r -- "ALL_PROXY=${ALL_PROXY-unset}"
  print -r -- "WS_PROXY=${WS_PROXY-unset}"
  print -r -- "NO_PROXY=${NO_PROXY-unset}"
  print -r -- "HTTP_PROXY_URL=${HTTP_PROXY_URL-unset}"
  print -r -- "NO_PROXY_HOSTS=${NO_PROXY_HOSTS-unset}"
  print -r -- "GIT_HTTP_PROXY=$git_http_proxy"
  print -r -- "ARGS=$*"
} > "${FAKE_APP_CAPTURE:?}"
print -r -- "application stdout must stay out of launcher.log"
FAKE

/bin/cat > "$FAKE_CODEX" <<'FAKE'
#!/bin/zsh
set -u
if [[ "${1:-}" == "--version" ]]; then
  print -r -- "codex-test 1.0"
  exit 0
fi

if [[ "${1:-}" == "doctor" && "${2:-}" == "--json" ]]; then
  git_http_proxy="$(/usr/bin/git config --get-urlmatch http.proxy https://github.com/openai/skills.git 2>/dev/null || true)"
  {
    print -r -- "HTTP_PROXY=${HTTP_PROXY-unset}"
    print -r -- "HTTPS_PROXY=${HTTPS_PROXY-unset}"
    print -r -- "ALL_PROXY=${ALL_PROXY-unset}"
    print -r -- "WS_PROXY=${WS_PROXY-unset}"
    print -r -- "HTTP_PROXY_URL=${HTTP_PROXY_URL-unset}"
    print -r -- "NO_PROXY_HOSTS=${NO_PROXY_HOSTS-unset}"
    print -r -- "GIT_HTTP_PROXY=$git_http_proxy"
  } > "${FAKE_CODEX_CAPTURE:?}"
  print -r -- '{"checks":{"network.provider_reachability":{"status":"ok","summary":"provider reachable"},"network.websocket_reachability":{"status":"ok","summary":"websocket reachable","durationMs":12,"details":{"handshake result":"HTTP 101 Switching Protocols","proxy env vars present":"test"}}}}'
  exit "${FAKE_DOCTOR_EXIT:-0}"
fi

exit 2
FAKE

/bin/chmod +x \
  "$FAKE_CURL" "$FAKE_SCUTIL" "$FAKE_LSOF" "$FAKE_OSASCRIPT" \
  "$FAKE_OPEN" "$FAKE_APP" "$FAKE_CODEX"

typeset RESOLVE_OUTPUT=""
typeset -i RESOLVE_STATUS=0

resolve_with() {
  local direct_code="$1"
  local valid_proxies="$2"
  local scutil_output="$3"
  local lsof_output="$4"
  local override_url="$5"
  local -a override_args

  if [[ -n "$override_url" ]]; then
    override_args=("HTTP_PROXY_URL=$override_url")
  else
    override_args=(-u HTTP_PROXY_URL)
  fi

  set +e
  RESOLVE_OUTPUT="$(/usr/bin/env \
    "${override_args[@]}" \
    PROXY_ROUTE_CURL_BIN="$FAKE_CURL" \
    PROXY_ROUTE_SCUTIL_BIN="$FAKE_SCUTIL" \
    PROXY_ROUTE_LSOF_BIN="$FAKE_LSOF" \
    FAKE_CURL_DIRECT_CODE="$direct_code" \
    FAKE_CURL_VALID_PROXIES="$valid_proxies" \
    FAKE_SCUTIL_OUTPUT="$scutil_output" \
    FAKE_LSOF_OUTPUT="$lsof_output" \
    "$ROUTE_LIB" resolve 2>/dev/null)"
  RESOLVE_STATUS=$?
  set -e
}

# A working system/TUN path wins and needs no explicit proxy variables.
resolve_with "401" "" "" "" ""
assert_eq "0" "$RESOLVE_STATUS" "system route should resolve"
assert_eq $'system\tsystem/TUN\t-' "$RESOLVE_OUTPUT" "system route contract"

# An explicit override is authoritative and can use any validated port.
resolve_with "000" "http://127.0.0.1:1082" "" "" "http://127.0.0.1:1082"
assert_eq "0" "$RESOLVE_STATUS" "explicit override should resolve"
assert_eq $'explicit\tHTTP_PROXY_URL\thttp://127.0.0.1:1082' "$RESOLVE_OUTPUT" \
  "explicit override contract"

# A broken override must not silently fall back to another route.
resolve_with "401" "" "" "" "http://127.0.0.1:6553"
assert_eq "2" "$RESOLVE_STATUS" "broken explicit override should be a configuration error"
assert_eq "" "$RESOLVE_OUTPUT" "broken override should emit no candidate"

SCUTIL_PROXY=$'<dictionary> {\n  HTTPEnable : 0\n  HTTPSEnable : 1\n  HTTPSPort : 8087\n  HTTPSProxy : 127.0.0.1\n}'
resolve_with "000" "http://127.0.0.1:8087" "$SCUTIL_PROXY" "" ""
assert_eq "0" "$RESOLVE_STATUS" "macOS HTTPS proxy should resolve"
assert_eq $'explicit\tmacOS HTTPS proxy\thttp://127.0.0.1:8087' "$RESOLVE_OUTPUT" \
  "macOS proxy contract"

SHADOWROCKET_LSOF=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nMacPacket 101 user 8u IPv4 0x1 0t0 TCP 127.0.0.1:1082 (LISTEN)'
resolve_with "000" "http://127.0.0.1:1082" "" "$SHADOWROCKET_LSOF" ""
assert_eq "0" "$RESOLVE_STATUS" "Shadowrocket listener should resolve"
assert_eq $'explicit\tShadowrocket\thttp://127.0.0.1:1082' "$RESOLVE_OUTPUT" \
  "Shadowrocket listener contract"

DUAL_STACK_LSOF=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nMacPacket 101 user 8u IPv6 0x1 0t0 TCP [::1]:1082 (LISTEN)\nMacPacket 101 user 9u IPv4 0x2 0t0 TCP 127.0.0.1:1082 (LISTEN)'
resolve_with "000" "http://127.0.0.1:1082,http://[::1]:1082" "" "$DUAL_STACK_LSOF" ""
assert_eq "0" "$RESOLVE_STATUS" "dual-stack listener should resolve"
assert_eq $'explicit\tShadowrocket\thttp://127.0.0.1:1082' "$RESOLVE_OUTPUT" \
  "dual-stack copies of one listener should collapse to the IPv4 route"

FLCLASH_LSOF=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\npostgres 10 user 8u IPv4 0x1 0t0 TCP 127.0.0.1:5432 (LISTEN)\nFlClash 11 user 9u IPv4 0x2 0t0 TCP 127.0.0.1:6244 (LISTEN)\nmihomo 12 user 9u IPv4 0x3 0t0 TCP *:9090 (LISTEN)'
resolve_with "000" "http://127.0.0.1:6244" "" "$FLCLASH_LSOF" ""
assert_eq "0" "$RESOLVE_STATUS" "FlClash listener should resolve"
assert_eq $'explicit\tFlClash\thttp://127.0.0.1:6244' "$RESOLVE_OUTPUT" \
  "only a validated loopback proxy listener should be returned"

WILDCARD_LSOF=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nFlClash 11 user 9u IPv4 0x2 0t0 TCP *:6255 (LISTEN)'
resolve_with "000" "http://127.0.0.1:6255" "" "$WILDCARD_LSOF" ""
assert_eq "0" "$RESOLVE_STATUS" "validated wildcard listener should resolve through loopback"
assert_eq $'explicit\tFlClash\thttp://127.0.0.1:6255' "$RESOLVE_OUTPUT" \
  "wildcard listener should be normalized to loopback"

resolve_with "000" "" "" "" ""
assert_eq "1" "$RESOLVE_STATUS" "missing route should be reported"
assert_eq "" "$RESOLVE_OUTPUT" "missing route should emit no candidate"

# Environment application is shared by the launcher and diagnostic.
SYSTEM_ENV_OUTPUT="$(/usr/bin/env \
  HTTP_PROXY=http://127.0.0.1:7890 HTTPS_PROXY=http://127.0.0.1:7890 \
  ALL_PROXY=socks5://127.0.0.1:7890 WS_PROXY=http://127.0.0.1:7890 \
  HTTP_PROXY_URL=http://127.0.0.1:1082 NO_PROXY_HOSTS=localhost \
  GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
  ROUTE_LIB="$ROUTE_LIB" \
  /bin/zsh -c '
    source "$ROUTE_LIB"
    proxy_route_apply_environment system - "localhost,127.0.0.1"
    git_http_proxy="$(/usr/bin/git config --get-urlmatch http.proxy https://github.com/openai/skills.git 2>/dev/null || true)"
    print -r -- "${HTTP_PROXY-unset}|${HTTPS_PROXY-unset}|${ALL_PROXY-unset}|${WS_PROXY-unset}|${NO_PROXY-unset}|${HTTP_PROXY_URL-unset}|${NO_PROXY_HOSTS-unset}|$git_http_proxy"
  ')"
assert_eq "unset|unset|unset|unset|unset|unset|unset|" "$SYSTEM_ENV_OUTPUT" \
  "system route should clear inherited environment and Git proxies"

EXPLICIT_ENV_OUTPUT="$(/usr/bin/env \
  ALL_PROXY=socks5://127.0.0.1:9999 WS_PROXY=http://127.0.0.1:9999 \
  HTTP_PROXY_URL=http://127.0.0.1:1082 NO_PROXY_HOSTS=localhost \
  GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
  ROUTE_LIB="$ROUTE_LIB" \
  /bin/zsh -c '
    source "$ROUTE_LIB"
    proxy_route_apply_environment explicit "http://127.0.0.1:6244" "localhost,127.0.0.1"
    git_http_proxy="$(/usr/bin/git config --get-urlmatch http.proxy https://github.com/openai/skills.git 2>/dev/null || true)"
    print -r -- "${HTTP_PROXY-unset}|${HTTPS_PROXY-unset}|${http_proxy-unset}|${https_proxy-unset}|${ALL_PROXY-unset}|${WS_PROXY-unset}|${NO_PROXY-unset}|${HTTP_PROXY_URL-unset}|${NO_PROXY_HOSTS-unset}|$git_http_proxy"
  ')"
assert_eq "http://127.0.0.1:6244|http://127.0.0.1:6244|http://127.0.0.1:6244|http://127.0.0.1:6244|unset|unset|localhost,127.0.0.1|unset|unset|http://127.0.0.1:6244" \
  "$EXPLICIT_ENV_OUTPUT" "explicit route should align environment and Git proxies"

GIT_APPEND_OUTPUT="$(/usr/bin/env \
  GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=user.email \
  GIT_CONFIG_VALUE_0=probe@example.invalid \
  ROUTE_LIB="$ROUTE_LIB" \
  /bin/zsh -c '
    source "$ROUTE_LIB"
    proxy_route_apply_environment explicit "http://127.0.0.1:6244" "localhost,127.0.0.1"
    git_http_proxy="$(/usr/bin/git config --get-urlmatch http.proxy https://github.com/openai/skills.git 2>/dev/null || true)"
    print -r -- "${GIT_CONFIG_COUNT-unset}|${GIT_CONFIG_KEY_0-unset}|${GIT_CONFIG_VALUE_0-unset}|${GIT_CONFIG_KEY_1-unset}|${GIT_CONFIG_VALUE_1-unset}|$git_http_proxy"
  ')"
assert_eq "2|user.email|probe@example.invalid|http.proxy|http://127.0.0.1:6244|http://127.0.0.1:6244" \
  "$GIT_APPEND_OUTPUT" "route injection should preserve existing command-scope Git config"

run_launcher() {
  local test_dir="$1"
  local direct_code="$2"
  local valid_proxies="$3"
  local lsof_output="$4"
  local override_url="$5"
  local fixed_response="$6"
  local choice_once="$7"
  local -a override_args

  /bin/mkdir -p "$test_dir/logs"
  if [[ -n "$override_url" ]]; then
    override_args=("HTTP_PROXY_URL=$override_url")
  else
    override_args=(-u HTTP_PROXY_URL)
  fi

  /usr/bin/env \
    "${override_args[@]}" \
    HTTP_PROXY=http://127.0.0.1:7890 \
    HTTPS_PROXY=http://127.0.0.1:7890 \
    ALL_PROXY=socks5://127.0.0.1:7890 \
    WS_PROXY=http://127.0.0.1:7890 \
    GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=user.email \
    GIT_CONFIG_VALUE_0=probe@example.invalid \
    CODEX_PROXY_APP_BIN="$FAKE_APP" \
    CODEX_PROXY_OSASCRIPT_BIN="$FAKE_OSASCRIPT" \
    CODEX_PROXY_OPEN_BIN="$FAKE_OPEN" \
    CODEX_PROXY_LOG_DIR="$test_dir/logs" \
    CODEX_PROXY_LOG_MAX_BYTES=64 \
    CODEX_PROXY_WAIT_ATTEMPTS=1 \
    CODEX_PROXY_WAIT_DELAY=0 \
    PROXY_ROUTE_CURL_BIN="$FAKE_CURL" \
    PROXY_ROUTE_SCUTIL_BIN="$FAKE_SCUTIL" \
    PROXY_ROUTE_LSOF_BIN="$FAKE_LSOF" \
    FAKE_CURL_DIRECT_CODE="$direct_code" \
    FAKE_CURL_VALID_PROXIES="$valid_proxies" \
    FAKE_SCUTIL_OUTPUT="" \
    FAKE_LSOF_OUTPUT="$lsof_output" \
    FAKE_APP_CAPTURE="$test_dir/app.env" \
    FAKE_OPEN_CAPTURE="$test_dir/open.args" \
    FAKE_OSASCRIPT_FIXED_RESPONSE="$fixed_response" \
    FAKE_OSASCRIPT_CHOICE_ONCE="$choice_once" \
    FAKE_OSASCRIPT_STATE="$test_dir/osascript.state" \
    "$LAUNCHER"
}

# Launcher uses the selected validated route, rotates only its compact log, and
# never captures ChatGPT stdout or writes credentials to the log.
LAUNCH_OVERRIDE_DIR="$TEST_TMP/launcher-override"
/bin/mkdir -p "$LAUNCH_OVERRIDE_DIR/logs"
/usr/bin/printf '%080d' 0 > "$LAUNCH_OVERRIDE_DIR/logs/launcher.log"
print -r -- "legacy log must remain unchanged" \
  > "$LAUNCH_OVERRIDE_DIR/logs/codex-proxy.log"
SECRET_PROXY="http://alice:secret@127.0.0.1:1082"
run_launcher "$LAUNCH_OVERRIDE_DIR" "000" "$SECRET_PROXY" "" "$SECRET_PROXY" "" ""
wait_for_file "$LAUNCH_OVERRIDE_DIR/app.env" || fail "launcher did not start the fake app"
APP_ENV="$(<"$LAUNCH_OVERRIDE_DIR/app.env")"
assert_contains "$APP_ENV" "HTTP_PROXY=$SECRET_PROXY" "launcher should inject selected proxy"
assert_contains "$APP_ENV" "GIT_HTTP_PROXY=$SECRET_PROXY" \
  "launcher should override stale global Git proxy for its process tree"
assert_contains "$APP_ENV" "ALL_PROXY=unset" "launcher should clear ALL_PROXY"
assert_contains "$APP_ENV" "WS_PROXY=unset" "launcher should clear WS_PROXY"
assert_contains "$APP_ENV" "HTTP_PROXY_URL=unset" \
  "launcher should not leak the explicit override variable to ChatGPT"
assert_contains "$APP_ENV" "NO_PROXY_HOSTS=unset" \
  "launcher should not leak its custom bypass input to ChatGPT"
assert_contains "$APP_ENV" "ARGS=--disable-quic" "launcher should preserve --disable-quic"
assert_file_exists "$LAUNCH_OVERRIDE_DIR/logs/launcher.log.1" "compact log should rotate"
assert_eq "legacy log must remain unchanged" "$(<"$LAUNCH_OVERRIDE_DIR/logs/codex-proxy.log")" \
  "legacy log should not be touched"
NEW_LOG="$(<"$LAUNCH_OVERRIDE_DIR/logs/launcher.log")"
[[ "$NEW_LOG" != *"secret"* ]] || fail "launcher log leaked proxy credentials"
[[ "$NEW_LOG" != *"application stdout"* ]] || fail "launcher captured app stdout"
(( ASSERTIONS += 2 ))

# A healthy system/TUN route starts ChatGPT with stale proxy variables removed.
SYSTEM_LAUNCH_DIR="$TEST_TMP/launcher-system"
run_launcher "$SYSTEM_LAUNCH_DIR" "401" "" "" "" "" ""
wait_for_file "$SYSTEM_LAUNCH_DIR/app.env" || fail "system route did not start the fake app"
SYSTEM_APP_ENV="$(<"$SYSTEM_LAUNCH_DIR/app.env")"
assert_contains "$SYSTEM_APP_ENV" "HTTP_PROXY=unset" \
  "system route launcher should clear stale HTTP_PROXY"
assert_contains "$SYSTEM_APP_ENV" "ALL_PROXY=unset" \
  "system route launcher should clear stale ALL_PROXY"
assert_contains "$SYSTEM_APP_ENV" "NO_PROXY=unset" \
  "system route launcher should not leave stale NO_PROXY"
assert_contains "$SYSTEM_APP_ENV" "GIT_HTTP_PROXY=" \
  "system route launcher should neutralize stale global Git proxy"

# When more than one validated listener exists, the user's route choice wins.
MULTI_DIR="$TEST_TMP/launcher-multiple"
MULTI_LSOF=$'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nMacPacket 101 user 8u IPv4 0x1 0t0 TCP 127.0.0.1:1082 (LISTEN)\nFlClash 102 user 9u IPv4 0x2 0t0 TCP 127.0.0.1:6244 (LISTEN)'
run_launcher "$MULTI_DIR" "000" "http://127.0.0.1:1082,http://127.0.0.1:6244" \
  "$MULTI_LSOF" "" "FlClash — http://127.0.0.1:6244" ""
wait_for_file "$MULTI_DIR/app.env" || fail "launcher did not start after route selection"
MULTI_ENV="$(<"$MULTI_DIR/app.env")"
assert_contains "$MULTI_ENV" "HTTP_PROXY=http://127.0.0.1:6244" \
  "launcher should honor the selected FlClash route"
assert_contains "$MULTI_ENV" "GIT_HTTP_PROXY=http://127.0.0.1:6244" \
  "Git should honor the selected FlClash route"

# With no valid route, the user can open a proxy app, but ChatGPT must remain stopped.
NO_ROUTE_DIR="$TEST_TMP/launcher-no-route"
run_launcher "$NO_ROUTE_DIR" "000" "" "" "" "" "打开 Shadowrocket"
assert_file_absent "$NO_ROUTE_DIR/app.env" "launcher must not start ChatGPT without a route"
assert_file_exists "$NO_ROUTE_DIR/open.args" "launcher should invoke open after an explicit choice"
assert_contains "$(<"$NO_ROUTE_DIR/open.args")" "-b com.liguangming.Shadowrocket" \
  "launcher should open Shadowrocket by bundle identifier"

NO_ROUTE_FLCLASH_DIR="$TEST_TMP/launcher-no-route-flclash"
run_launcher "$NO_ROUTE_FLCLASH_DIR" "000" "" "" "" "" "打开 FlClash"
assert_file_absent "$NO_ROUTE_FLCLASH_DIR/app.env" \
  "launcher must remain stopped after opening FlClash without a route"
assert_contains "$(<"$NO_ROUTE_FLCLASH_DIR/open.args")" "-b com.follow.clash" \
  "launcher should open FlClash by bundle identifier"

# Diagnostic uses the same system route and judges only the two network checks,
# not unrelated doctor failures.
JQ_BIN="$(command -v jq 2>/dev/null || true)"
[[ -n "$JQ_BIN" ]] || fail "jq is required for diagnostic behavior tests"
DIAGNOSTIC_DIR="$TEST_TMP/diagnostic-system"
/bin/mkdir -p "$DIAGNOSTIC_DIR"
set +e
DIAGNOSTIC_OUTPUT="$(/usr/bin/env \
  HTTP_PROXY=http://127.0.0.1:7890 HTTPS_PROXY=http://127.0.0.1:7890 \
  ALL_PROXY=socks5://127.0.0.1:7890 WS_PROXY=http://127.0.0.1:7890 \
  GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
  CODEX_PROXY_CODEX_BIN="$FAKE_CODEX" \
  CODEX_PROXY_JQ_BIN="$JQ_BIN" \
  PROXY_ROUTE_CURL_BIN="$FAKE_CURL" \
  PROXY_ROUTE_SCUTIL_BIN="$FAKE_SCUTIL" \
  PROXY_ROUTE_LSOF_BIN="$FAKE_LSOF" \
  FAKE_CURL_DIRECT_CODE=401 \
  FAKE_CURL_VALID_PROXIES="" \
  FAKE_SCUTIL_OUTPUT="" \
  FAKE_LSOF_OUTPUT="" \
  FAKE_CODEX_CAPTURE="$DIAGNOSTIC_DIR/codex.env" \
  FAKE_DOCTOR_EXIT=1 \
  "$DIAGNOSTIC" 2>&1)"
DIAGNOSTIC_STATUS=$?
set -e
assert_eq "0" "$DIAGNOSTIC_STATUS" "unrelated doctor failure should not fail healthy network checks"
assert_contains "$DIAGNOSTIC_OUTPUT" "system/TUN" "diagnostic should report the selected system route"
DIAGNOSTIC_ENV="$(<"$DIAGNOSTIC_DIR/codex.env")"
assert_contains "$DIAGNOSTIC_ENV" "HTTP_PROXY=unset" "system diagnostic should clear stale HTTP_PROXY"
assert_contains "$DIAGNOSTIC_ENV" "ALL_PROXY=unset" "system diagnostic should clear stale ALL_PROXY"
assert_contains "$DIAGNOSTIC_ENV" "GIT_HTTP_PROXY=" \
  "system diagnostic should neutralize stale global Git proxy"

DIAGNOSTIC_EXPLICIT_DIR="$TEST_TMP/diagnostic-explicit"
/bin/mkdir -p "$DIAGNOSTIC_EXPLICIT_DIR"
set +e
DIAGNOSTIC_EXPLICIT_OUTPUT="$(/usr/bin/env \
  HTTP_PROXY_URL=http://127.0.0.1:1082 \
  GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
  CODEX_PROXY_CODEX_BIN="$FAKE_CODEX" \
  CODEX_PROXY_JQ_BIN="$JQ_BIN" \
  PROXY_ROUTE_CURL_BIN="$FAKE_CURL" \
  PROXY_ROUTE_SCUTIL_BIN="$FAKE_SCUTIL" \
  PROXY_ROUTE_LSOF_BIN="$FAKE_LSOF" \
  FAKE_CURL_DIRECT_CODE=000 \
  FAKE_CURL_VALID_PROXIES=http://127.0.0.1:1082 \
  FAKE_SCUTIL_OUTPUT="" \
  FAKE_LSOF_OUTPUT="" \
  FAKE_CODEX_CAPTURE="$DIAGNOSTIC_EXPLICIT_DIR/codex.env" \
  FAKE_DOCTOR_EXIT=0 \
  "$DIAGNOSTIC" 2>&1)"
DIAGNOSTIC_EXPLICIT_STATUS=$?
set -e
assert_eq "0" "$DIAGNOSTIC_EXPLICIT_STATUS" "explicit diagnostic route should pass"
assert_contains "$DIAGNOSTIC_EXPLICIT_OUTPUT" "http://127.0.0.1:1082" \
  "diagnostic should report the validated explicit endpoint"
DIAGNOSTIC_EXPLICIT_ENV="$(<"$DIAGNOSTIC_EXPLICIT_DIR/codex.env")"
assert_contains "$DIAGNOSTIC_EXPLICIT_ENV" "HTTP_PROXY=http://127.0.0.1:1082" \
  "diagnostic should inject the selected explicit proxy"
assert_contains "$DIAGNOSTIC_EXPLICIT_ENV" "GIT_HTTP_PROXY=http://127.0.0.1:1082" \
  "diagnostic should align Git with the selected explicit proxy"
assert_contains "$DIAGNOSTIC_EXPLICIT_ENV" "ALL_PROXY=unset" \
  "explicit diagnostic should still clear ALL_PROXY"
assert_contains "$DIAGNOSTIC_EXPLICIT_ENV" "HTTP_PROXY_URL=unset" \
  "diagnostic should not leak the override input to Codex"
assert_contains "$DIAGNOSTIC_EXPLICIT_ENV" "NO_PROXY_HOSTS=unset" \
  "diagnostic should not leak its custom bypass input to Codex"

echo "proxy behavior: ok ($ASSERTIONS assertions)"
