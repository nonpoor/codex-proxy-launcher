#!/bin/zsh

# Bundle layouts change independently of this launcher. Prefer the selected
# app's bundled CLI, then the older layout, then an explicitly installed CLI.
codex_runtime_find() {
  emulate -L zsh
  local bundle candidate
  if [[ -n "${CODEX_PROXY_CODEX_BIN:-}" ]]; then
    [[ -x "$CODEX_PROXY_CODEX_BIN" ]] || return 1
    print -r -- "$CODEX_PROXY_CODEX_BIN"
    return 0
  fi
  for bundle in "${CODEX_PROXY_APP_BUNDLE:-/Applications/ChatGPT.app}" /Applications/Codex.app; do
    for candidate in "$bundle/Contents/Resources/codex-cli/bin/codex" \
      "$bundle/Contents/Resources/codex"; do
      if [[ -x "$candidate" ]]; then
        print -r -- "$candidate"
        return 0
      fi
    done
  done
  candidate="$(whence -p codex 2>/dev/null)" || return 1
  [[ -x "$candidate" ]] || return 1
  print -r -- "$candidate"
}
