#!/bin/sh
# Reuse existing SSH config/auth. Never change SSH or server configuration.
set -eu
action=${1:-connect}
target=${2:-vps}
case "$target" in ''|-*|*[!a-zA-Z0-9._@:-]*) echo '[x] Use an SSH alias or user@hostname.' >&2; exit 2 ;; esac
command -v ssh >/dev/null 2>&1 || {
  echo '[x] SSH missing. In iSH install it with: apk add openssh-client' >&2
  exit 1
}
case "$action" in
  connect)
    exec ssh -tt -o StrictHostKeyChecking=ask -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -- "$target" \
      'if [ -x "$HOME/.local/bin/ocs" ]; then exec "$HOME/.local/bin/ocs" shell; else exec "${SHELL:-/bin/sh}" -l; fi'
    ;;
  check)
    exec ssh -T -o BatchMode=yes -o StrictHostKeyChecking=ask -o ConnectTimeout=10 -- "$target" \
      'printf "Connected: "; id -un; hostname'
    ;;
  last)
    exec ssh -T -o StrictHostKeyChecking=ask -o ConnectTimeout=10 -- "$target" 'exec "$HOME/.local/bin/ocs" last'
    ;;
  copy)
    [ -c /dev/clipboard ] || { echo '[x] iSH clipboard device unavailable; use the iPhone SSH shortcut.' >&2; exit 1; }
    umask 077
    output=$(mktemp)
    trap 'rm -f -- "$output"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ssh -T -o StrictHostKeyChecking=ask -o ConnectTimeout=10 -- "$target" 'exec "$HOME/.local/bin/ocs" last' > "$output"
    [ -s "$output" ] || { echo '[x] Empty capture; clipboard left untouched.' >&2; exit 1; }
    cat "$output" > /dev/clipboard
    printf '[+] VPS output copied. Open your LLM and tap Paste.\n'
    ;;
  *) echo '[x] Usage: link.sh connect|check|last|copy [SSH-alias-or-user@host]' >&2; exit 2 ;;
esac
