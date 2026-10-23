#!/bin/zsh
# Source this file; no profile or system settings are changed automatically.
typeset -g CODEX_PROXY_ROUTE_LIB="${${(%):-%N}:A:h:h}/lib/proxy-route.zsh"

proxy_auto() {
  local route_output route_line route_mode route_source route_url
  [[ -r "$CODEX_PROXY_ROUTE_LIB" ]] || {
    print -u2 -- "Missing route module: $CODEX_PROXY_ROUTE_LIB"
    return 1
  }
  source "$CODEX_PROXY_ROUTE_LIB"
  route_output="$(proxy_route_resolve)" || {
    print -u2 -- "No usable system/TUN or HTTP proxy route."
    return 1
  }
  route_line="${route_output%%$'\n'*}"
  IFS=$'\t' read -r route_mode route_source route_url <<< "$route_line"
  proxy_route_apply_shell_environment "$route_mode" "$route_url" \
    "${NO_PROXY_HOSTS:-localhost,127.0.0.1,::1}" || return 1
  proxy_route_describe "$route_mode" "$route_source" "$route_url"
}

proxy_off() {
  source "$CODEX_PROXY_ROUTE_LIB" || return 1
  proxy_route_clear_environment
  print -r -- "Proxy OFF (current shell only)"
}

codex_auto() (
  proxy_auto || return 1
  command codex "$@"
)
