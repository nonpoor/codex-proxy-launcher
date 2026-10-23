#!/bin/zsh

# Shared proxy-route discovery and environment setup for the launcher and
# diagnostic. A resolved route is emitted as tab-separated mode, source, URL.
# System/TUN routes use "-" for the URL because no explicit proxy is injected.

proxy_route_probe_code_ok() {
  emulate -L zsh
  local code="${1:-}"
  [[ "$code" == [0-9][0-9][0-9] ]] || return 1
  (( 10#$code >= 200 && 10#$code < 500 && 10#$code != 407 ))
}

proxy_route_url_valid() {
  emulate -L zsh
  local url="${1:-}"
  [[ "$url" == http://?* || "$url" == https://?* ]] || return 1
  [[ "$url" != *$'\n'* && "$url" != *$'\r'* && "$url" != *$'\t'* && "$url" != *' '* ]]
}

proxy_route_redact_url() {
  emulate -L zsh
  local url="${1:-}"
  local scheme rest endpoint

  if [[ "$url" == *://*@* ]]; then
    scheme="${url%%://*}"
    rest="${url#*://}"
    endpoint="${rest##*@}"
    print -r -- "${scheme}://<redacted>@${endpoint}"
  else
    print -r -- "$url"
  fi
}

proxy_route_describe() {
  emulate -L zsh
  local mode="${1:-}"
  local source="${2:-}"
  local url="${3:-}"
  local display_url

  [[ -n "$source" ]] || return 1
  case "$mode" in
    system)
      print -r -- "${source}（未注入本地代理端口）"
      ;;
    explicit)
      display_url="$(proxy_route_redact_url "$url")"
      print -r -- "${source} — ${display_url}"
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_route_probe_system() {
  emulate -L zsh
  local curl_bin="${PROXY_ROUTE_CURL_BIN:-/usr/bin/curl}"
  local target="${PROXY_ROUTE_TARGET_URL:-https://api.openai.com/v1/models}"
  local connect_timeout="${PROXY_ROUTE_CONNECT_TIMEOUT:-3}"
  local max_time="${PROXY_ROUTE_MAX_TIME:-8}"
  local code

  [[ -x "$curl_bin" ]] || return 1
  code="$(/usr/bin/env \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u WS_PROXY -u WSS_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u ws_proxy -u wss_proxy -u no_proxy \
    "$curl_bin" \
      --disable --silent --show-error --output /dev/null --write-out '%{http_code}' \
      --connect-timeout "$connect_timeout" --max-time "$max_time" \
      --noproxy '*' "$target" 2>/dev/null)" || return 1

  proxy_route_probe_code_ok "$code"
}

proxy_route_probe_explicit() {
  emulate -L zsh
  local proxy_url="${1:-}"
  local curl_bin="${PROXY_ROUTE_CURL_BIN:-/usr/bin/curl}"
  local target="${PROXY_ROUTE_TARGET_URL:-https://api.openai.com/v1/models}"
  local connect_timeout="${PROXY_ROUTE_CONNECT_TIMEOUT:-3}"
  local max_time="${PROXY_ROUTE_MAX_TIME:-8}"
  local code

  proxy_route_url_valid "$proxy_url" || return 1
  [[ -x "$curl_bin" ]] || return 1
  code="$(/usr/bin/env \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u WS_PROXY -u WSS_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u ws_proxy -u wss_proxy -u no_proxy \
    "$curl_bin" \
      --disable --silent --show-error --output /dev/null --write-out '%{http_code}' \
      --connect-timeout "$connect_timeout" --max-time "$max_time" \
      --noproxy '' --proxy "$proxy_url" "$target" 2>/dev/null)" || return 1

  proxy_route_probe_code_ok "$code"
}

proxy_route_url_from_host_port() {
  emulate -L zsh
  local host="${1:-}"
  local port="${2:-}"
  local display_host="$host"
  local -i port_number

  [[ -n "$host" && "$port" == <-> && ${#port} -le 5 ]] || return 1
  (( port_number = 10#$port ))
  (( port_number >= 1 && port_number <= 65535 )) || return 1
  [[ "$host" != *$'\n'* && "$host" != *$'\r'* && "$host" != *$'\t'* \
    && "$host" != *' '* && "$host" != */* ]] || return 1

  if [[ "$host" == *:* && "$host" != \[*\] ]]; then
    display_host="[$host]"
  fi
  print -r -- "http://${display_host}:${port_number}"
}

proxy_route_scutil_candidates() {
  emulate -L zsh
  local scutil_bin="${PROXY_ROUTE_SCUTIL_BIN:-/usr/sbin/scutil}"
  local proxy_state parsed source host port url

  [[ -x "$scutil_bin" ]] || return 0
  proxy_state="$("$scutil_bin" --proxy 2>/dev/null)" || return 0
  parsed="$(print -r -- "$proxy_state" | /usr/bin/awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      separator = index($0, ":")
      if (!separator) next
      key = trim(substr($0, 1, separator - 1))
      value = trim(substr($0, separator + 1))
      values[key] = value
    }
    END {
      if (values["HTTPSEnable"] == "1" && values["HTTPSProxy"] != "" && values["HTTPSPort"] != "")
        print "macOS HTTPS proxy\t" values["HTTPSProxy"] "\t" values["HTTPSPort"]
      if (values["HTTPEnable"] == "1" && values["HTTPProxy"] != "" && values["HTTPPort"] != "")
        print "macOS HTTP proxy\t" values["HTTPProxy"] "\t" values["HTTPPort"]
    }
  ')"

  [[ -n "$parsed" ]] || return 0
  while IFS=$'\t' read -r source host port; do
    [[ -n "$source" ]] || continue
    url="$(proxy_route_url_from_host_port "$host" "$port")" || continue
    print -r -- "${source}"$'\t'"${url}"
  done <<< "$parsed"
}

proxy_route_lsof_candidates() {
  emulate -L zsh
  local lsof_bin="${PROXY_ROUTE_LSOF_BIN:-/usr/sbin/lsof}"
  local listeners

  [[ -x "$lsof_bin" ]] || return 0
  listeners="$("$lsof_bin" -nP -iTCP -sTCP:LISTEN 2>/dev/null)" || return 0
  [[ -n "$listeners" ]] || return 0

  print -r -- "$listeners" | /usr/bin/awk '
    NR == 1 && $1 == "COMMAND" { next }
    {
      command = tolower($1)
      source = ""
      if (command ~ /macpacket|shadowrocket/) source = "Shadowrocket"
      else if (command ~ /flclash/) source = "FlClash"
      else if (command ~ /mihomo|clash/) source = "Clash/Mihomo"
      if (source == "") next

      endpoint = ""
      for (field = 1; field < NF; field++) {
        if ($field == "TCP") {
          endpoint = $(field + 1)
          break
        }
      }

      port = endpoint
      sub(/^.*:/, "", port)
      if (port !~ /^[0-9]+$/) next
      key = source SUBSEP port
      if (!(key in order_index)) {
        order_count++
        order[order_count] = key
        order_index[key] = order_count
        sources[key] = source
      }

      if (endpoint ~ /^127\.0\.0\.1:[0-9]+$/ || endpoint ~ /^localhost:[0-9]+$/ ||
          endpoint ~ /^\*:[0-9]+$/ || endpoint ~ /^0\.0\.0\.0:[0-9]+$/ || endpoint ~ /^\[::\]:[0-9]+$/) {
        ipv4_urls[key] = "http://127.0.0.1:" port
      } else if (endpoint ~ /^\[::1\]:[0-9]+$/) {
        ipv6_urls[key] = "http://[::1]:" port
      }
    }
    END {
      for (order_position = 1; order_position <= order_count; order_position++) {
        key = order[order_position]
        if (ipv4_urls[key] != "") print sources[key] "\t" ipv4_urls[key]
        else if (ipv6_urls[key] != "") print sources[key] "\t" ipv6_urls[key]
      }
    }
  '
}

proxy_route_resolve() {
  emulate -L zsh
  local override_url="${HTTP_PROXY_URL:-}"
  local discovered source url
  local -A seen
  local -i emitted=0

  if [[ -n "$override_url" ]]; then
    proxy_route_url_valid "$override_url" || return 2
    proxy_route_probe_explicit "$override_url" || return 2
    print -r -- "explicit"$'\t'"HTTP_PROXY_URL"$'\t'"$override_url"
    return 0
  fi

  if proxy_route_probe_system; then
    print -r -- "system"$'\t'"system/TUN"$'\t'"-"
    return 0
  fi

  discovered="$({
    proxy_route_scutil_candidates
    proxy_route_lsof_candidates
  })"

  [[ -n "$discovered" ]] || return 1
  while IFS=$'\t' read -r source url; do
    [[ -n "$source" && -n "$url" ]] || continue
    [[ -z "${seen[$url]-}" ]] || continue
    seen[$url]=1
    if proxy_route_probe_explicit "$url"; then
      print -r -- "explicit"$'\t'"$source"$'\t'"$url"
      (( emitted += 1 ))
    fi
  done <<< "$discovered"

  (( emitted > 0 )) || return 1
  return 0
}

proxy_route_clear_environment() {
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY WS_PROXY WSS_PROXY NO_PROXY
  unset http_proxy https_proxy all_proxy ws_proxy wss_proxy no_proxy
  unset HTTP_PROXY_URL NO_PROXY_HOSTS
}

proxy_route_apply_git_proxy() {
  emulate -L zsh
  local proxy_url="${1-}"
  local config_count="${GIT_CONFIG_COUNT:-0}"
  local -i config_index

  [[ "$config_count" == <-> ]] || return 1
  (( config_index = 10#$config_count ))

  # Git's command-scope config is inherited by every Git child process and
  # takes precedence over user-level config without hiding unrelated settings.
  typeset -gx "GIT_CONFIG_KEY_${config_index}=http.proxy"
  typeset -gx "GIT_CONFIG_VALUE_${config_index}=$proxy_url"
  export GIT_CONFIG_COUNT=$(( config_index + 1 ))
}

proxy_route_apply_shell_environment() {
  emulate -L zsh
  local mode="${1:-}"
  local proxy_url="${2:-}"
  local no_proxy_hosts="${3:-localhost,127.0.0.1,::1}"

  case "$mode" in
    system)
      proxy_route_clear_environment
      return 0
      ;;
    explicit)
      proxy_route_url_valid "$proxy_url" || return 1
      proxy_route_clear_environment
      export HTTP_PROXY="$proxy_url"
      export HTTPS_PROXY="$proxy_url"
      export http_proxy="$proxy_url"
      export https_proxy="$proxy_url"
      export NO_PROXY="$no_proxy_hosts"
      export no_proxy="$no_proxy_hosts"
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_route_apply_environment() {
  emulate -L zsh
  local mode="${1:-}"
  local proxy_url="${2:-}"
  local no_proxy_hosts="${3:-localhost,127.0.0.1,::1}"

  proxy_route_apply_shell_environment "$mode" "$proxy_url" "$no_proxy_hosts" || return 1
  case "$mode" in
    system)
      # An empty command-scope value neutralizes stale global Git proxies while
      # leaving Git to use the already-validated system/TUN route.
      proxy_route_apply_git_proxy ""
      ;;
    explicit)
      proxy_route_apply_git_proxy "$proxy_url"
      ;;
  esac
}

proxy_route_main() {
  emulate -L zsh
  local command="${1:-resolve}"
  local result_code

  case "$command" in
    resolve)
      proxy_route_resolve
      result_code=$?
      if (( result_code == 2 )); then
        print -u2 -r -- "HTTP_PROXY_URL 格式无效或当前不可用。"
      fi
      return "$result_code"
      ;;
    redact)
      proxy_route_redact_url "${2:-}"
      ;;
    *)
      print -u2 -r -- "用法：${0:t} [resolve | redact URL]"
      return 64
      ;;
  esac
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
  proxy_route_main "$@"
fi
