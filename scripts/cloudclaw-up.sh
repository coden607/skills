#!/usr/bin/env bash
# cloudclaw-up.sh — one paste: bring Cloudclaw up on the OpenClaw already installed for THIS user.
#   curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/cloudclaw-up.sh | bash
# Knobs: AGENT_NAME=Cloudclaw  ROLE=all|acquisition|repos
# Touches only OpenClaw: no apt upgrade, no firewall, no other services.
set -uo pipefail
AGENT_NAME="${AGENT_NAME:-Cloudclaw}"; ROLE="${ROLE:-all}"
RAW="https://raw.githubusercontent.com/coden607/skills/main/scripts"
ok(){ echo "✅ $*"; }; bad(){ echo "❌ $*"; }

echo "== Cloudclaw up ($AGENT_NAME, ROLE=$ROLE) =="
FREE=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)
[ "${FREE:-0}" -ge 2 ] && ok "disk free: ${FREE}G" || { bad "only ${FREE}G free — free space first"; exit 1; }

for d in "$HOME/.openclaw/bin" "$HOME/.local/bin" "$HOME/.npm-global/bin"; do [ -d "$d" ] && PATH="$d:$PATH"; done
command -v openclaw >/dev/null || { bad "openclaw not installed for $(whoami) — run: curl -fsSL https://openclaw.ai/install.sh | bash"; exit 1; }
ok "openclaw $(openclaw --version 2>/dev/null | head -1)"

echo "-- gateway probe"; openclaw gateway probe || bad "probe reported a problem (continuing)"

echo "-- loading Cloudclaw workspace + skills"
curl -fsSL "$RAW/ocs-kimi-claw.sh" -o "$HOME/ocs.sh" \
  && LINK=1 AGENT_NAME="$AGENT_NAME" ROLE="$ROLE" bash "$HOME/ocs.sh" \
  && ok "workspace loaded" || { bad "ocs failed"; exit 1; }

echo "-- restarting gateway"
[ "$(id -u)" = 0 ] && loginctl enable-linger root 2>/dev/null
openclaw gateway restart 2>/dev/null || systemctl --user restart openclaw-gateway.service 2>/dev/null \
  && ok "gateway restarted" || bad "restart failed — try: openclaw gateway start"
sleep 3
echo "-- status"; openclaw gateway probe && ok "gateway reachable" || bad "gateway not reachable — run: openclaw logs --follow"

echo
echo "== Next: DM your Telegram bot → \"Read AGENTS.md and run BOOTSTRAP.md.\" =="
echo "   If it replies with a pairing code: openclaw pairing approve telegram <CODE>"
