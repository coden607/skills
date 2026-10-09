#!/usr/bin/env bash
# cloudclaw-vps.sh — install OpenClaw + Cloudclaw on an EXISTING VPS without touching other services.
#
# On the VPS, as root:
#   curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/cloudclaw-vps.sh -o cloudclaw-vps.sh && bash cloudclaw-vps.sh
#
# Safe by design:
#   - no apt upgrade, no firewall changes, no system-wide Node (OpenClaw installs under ~claw/.openclaw)
#   - everything runs as a separate user "claw"; gateway stays on 127.0.0.1:18789
#   - aborts if disk is low or port 18789 is already used by something else
# Knobs: CLAW_USER=claw  AGENT_NAME=Cloudclaw  ROLE=all|acquisition|repos  MIN_FREE_GB=5
set -euo pipefail

CLAW_USER="${CLAW_USER:-claw}"
AGENT_NAME="${AGENT_NAME:-Cloudclaw}"
ROLE="${ROLE:-all}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
RAW="https://raw.githubusercontent.com/coden607/skills/main/scripts"

[ "$(id -u)" = 0 ] || { echo "!! run as root (ssh root@VPS_IP)"; exit 1; }
echo "== Cloudclaw VPS setup (user: $CLAW_USER) =="

# 1. preflight — read-only checks
FREE_GB=$(df -BG --output=avail /home | tail -1 | tr -dc 0-9)
echo ">> free disk on /home: ${FREE_GB}G"
if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
  echo "!! less than ${MIN_FREE_GB}G free — stopping. See biggest dirs:"; du -xh --max-depth=1 / 2>/dev/null | sort -h | tail -8; exit 1
fi
if ss -ltn 2>/dev/null | grep -q ':18789 '; then
  if ! pgrep -u "$CLAW_USER" -f openclaw >/dev/null 2>&1; then echo "!! port 18789 is used by another service — stopping"; exit 1; fi
fi

# 2. only install missing basics (no upgrades)
need=""; for p in curl git ca-certificates; do dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"; done
if [ -n "$need" ]; then echo ">> installing:$need"; apt-get update -qq && apt-get install -y -qq $need; fi

# 3. dedicated user
id "$CLAW_USER" >/dev/null 2>&1 || { useradd -m -s /bin/bash "$CLAW_USER"; echo ">> created user $CLAW_USER"; }
loginctl enable-linger "$CLAW_USER"
H=$(getent passwd "$CLAW_USER" | cut -d: -f6)
mkdir -p /var/tmp/openclaw-compile-cache && chown "$CLAW_USER" /var/tmp/openclaw-compile-cache
grep -q OPENCLAW_NO_RESPAWN "$H/.bashrc" 2>/dev/null || cat >> "$H/.bashrc" <<'EOF'
export NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
export OPENCLAW_NO_RESPAWN=1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
for d in "$HOME/.openclaw/bin" "$HOME/.local/bin" "$HOME/.npm-global/bin"; do [ -d "$d" ] && PATH="$d:$PATH"; done
export PATH
EOF
chown "$CLAW_USER:$CLAW_USER" "$H/.bashrc"

# 4. OpenClaw under the user's own prefix (no system Node)
run() { su - "$CLAW_USER" -c "source ~/.bashrc; $*"; }
if ! run 'command -v openclaw' >/dev/null 2>&1; then
  echo ">> installing OpenClaw for $CLAW_USER"
  run 'curl -fsSL https://openclaw.ai/install-cli.sh | bash'
fi
run 'command -v openclaw' >/dev/null || { echo "!! openclaw not on PATH for $CLAW_USER — run: su - $CLAW_USER; then: openclaw --version"; exit 1; }

# 5. onboarding (interactive): choose bind=loopback, port 18789
echo ">> onboarding — pick LOOPBACK bind, port 18789"
run 'openclaw onboard --install-daemon' </dev/tty

# 6. Cloudclaw workspace + skills (symlinked to save disk)
run "curl -fsSL $RAW/ocs-kimi-claw.sh -o ~/ocs.sh && LINK=1 AGENT_NAME='$AGENT_NAME' ROLE='$ROLE' bash ~/ocs.sh"
run 'systemctl --user restart openclaw-gateway.service' || echo ">> restart the gateway manually: su - $CLAW_USER; systemctl --user restart openclaw-gateway.service"
run 'openclaw status' || true

IP=$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
cat <<EOF

== Done: $AGENT_NAME on this VPS ==
Dashboard (from your phone/PC, keep this running):
  ssh -N -L 18789:127.0.0.1:18789 root@$IP
  then open http://localhost:18789  (token link: su - $CLAW_USER -c 'openclaw dashboard')
Then tell $AGENT_NAME: "Read AGENTS.md and run BOOTSTRAP.md."
EOF
