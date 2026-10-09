#!/bin/sh
# Read-only diagnostics; intentionally omit credentials and environment dumps.
set -eu
printf 'user: %s\n' "$(id -un)"
printf 'system: %s\n' "$(uname -s)"
printf 'terminal: '
tty 2>/dev/null || true
printf 'TERM: %s\n' "${TERM:-unset}"
for tool in ssh tmux; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%s: available\n' "$tool"
  else
    printf '%s: missing\n' "$tool"
  fi
done
if [ -c /dev/clipboard ]; then printf 'iSH clipboard: available\n'; fi
if [ -x "$HOME/.local/bin/ocs" ]; then
  printf 'OCS helper: installed\n'
fi
if command -v ssh >/dev/null 2>&1; then
  printf 'SSH alias vps (configuration only, not a connection test):\n'
  ssh -G vps 2>/dev/null | awk '$1 == "hostname" || $1 == "user" || $1 == "port"'
fi
