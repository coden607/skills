#!/usr/bin/env bash
# cloudclaw-doctor.sh — diagnose + fix OpenClaw / Cloudclaw / Kimi Claw installs (VPS or Kimi sandbox).
#   curl -fsSL "https://raw.githubusercontent.com/coden607/skills/main/scripts/cloudclaw-doctor.sh?$(date +%s)" -o doctor.sh && bash doctor.sh
# Read-only checks always run. Each fix asks first (y/N). YES=1 = approve all fixes. NOFIX=1 = report only.
# Never touches other services: no apt upgrade, no firewall, no deleting anything outside caches/temp/old backups.
set -uo pipefail
TS=$(date +%Y%m%d-%H%M%S); LOG="$HOME/cloudclaw-doctor-$TS.log"
exec > >(tee -a "$LOG") 2>&1
RAW="https://raw.githubusercontent.com/coden607/skills/main/scripts"
ok(){ echo "✅ $*"; }; warn(){ echo "⚠️  $*"; }; bad(){ echo "❌ $*"; ISSUES=$((ISSUES+1)); }
ISSUES=0; FIXED=0
ask(){ # ask "question" → 0 if approved
  [ "${NOFIX:-0}" = 1 ] && { echo "   (NOFIX) skipped: $1"; return 1; }
  [ "${YES:-0}" = 1 ] && { echo "   → auto-yes: $1"; return 0; }
  if [ -r /dev/tty ]; then printf "   ❓ %s [y/N] " "$1" > /dev/tty; read -r a < /dev/tty; [[ "$a" =~ ^[Yy] ]]; else echo "   (no terminal) skipped: $1 — re-run with YES=1"; return 1; fi
}
have(){ command -v "$1" >/dev/null 2>&1; }
ROOT=0; [ "$(id -u)" = 0 ] && ROOT=1
for d in "$HOME/.openclaw/bin" "$HOME/.local/bin" "$HOME/.npm-global/bin"; do [ -d "$d" ] && PATH="$d:$PATH"; done
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
oc(){ openclaw "$@" </dev/null; }
free_gb(){ df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9; }

echo "== Cloudclaw doctor $TS — $(whoami)@$(hostname) =="

# ---------- 1. disk ----------
echo; echo "-- 1. Disk"
F=$(free_gb); df -h "$HOME" | tail -1
if [ "${F:-0}" -lt 3 ]; then
  bad "low disk: ${F}G free"
  du -xsh "$HOME"/.npm "$HOME"/.cache "$HOME"/skills "$HOME"/.openclaw/workspace/skills "$HOME"/.openclaw/workspace/.ocs-backup-* /tmp 2>/dev/null | sort -h | tail -8
  if ask "Clear caches + temp + old OCS backups (npm/pip cache, ~/.cache, /tmp files >1 day, .ocs-backup-*)?"; then
    have npm && npm cache clean --force >/dev/null 2>&1
    have pip && pip cache purge >/dev/null 2>&1
    rm -rf "$HOME"/.cache/* "$HOME"/.openclaw/workspace/.ocs-backup-* 2>/dev/null
    find /tmp -mindepth 1 -maxdepth 1 -user "$(whoami)" -mtime +1 -exec rm -rf {} + 2>/dev/null
    if [ $ROOT = 1 ]; then have apt-get && apt-get clean; have journalctl && journalctl --vacuum-size=100M >/dev/null 2>&1; fi
    FIXED=$((FIXED+1)); ok "now $(free_gb)G free"
  fi
  if [ -d "$HOME/.openclaw/workspace/skills" ] && [ ! -L "$(find "$HOME/.openclaw/workspace/skills" -mindepth 1 -maxdepth 1 | head -1)" ] && [ -d "$HOME/skills/.git" ]; then
    if ask "Replace copied skills with symlinks to ~/skills (saves space, same skills)?"; then
      for s in "$HOME/.openclaw/workspace/skills"/*/; do n=$(basename "$s"); [ -f "$HOME/skills/$n/SKILL.md" ] && rm -rf "$s" && ln -s "$HOME/skills/$n" "$HOME/.openclaw/workspace/skills/$n"; done
      FIXED=$((FIXED+1)); ok "skills symlinked; now $(free_gb)G free"
    fi
  fi
else ok "disk: ${F}G free"; fi

# ---------- 2. memory ----------
echo; echo "-- 2. Memory"
if have free; then
  free -h | sed -n 1,3p
  MEM=$(free -m | awk '/Mem:/{print $2}'); SW=$(free -m | awk '/Swap:/{print $2}')
  if [ "${MEM:-0}" -lt 3800 ] && [ "${SW:-0}" -lt 1000 ]; then
    bad "RAM ${MEM}M with no swap — npm installs/builds can get killed"
    if [ $ROOT = 1 ] && [ "$(free_gb)" -ge 4 ] && [ ! -e /swapfile ] && ask "Create a 2G swapfile (/swapfile, persistent)?"; then
      (fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048) && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile \
        && { grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab; } && FIXED=$((FIXED+1)) && ok "swap on: $(free -h | awk '/Swap:/{print $2}')"
    fi
  else ok "memory OK"; fi
else warn "free not available"; fi

# ---------- 3. node + openclaw ----------
echo; echo "-- 3. Node + OpenClaw"
if have node; then
  NV=$(node -v); NM=$(echo "$NV" | tr -d v | cut -d. -f1); echo "node $NV"
  [ "${NM:-0}" -ge 22 ] && ok "node version OK" || bad "node $NV too old (OpenClaw needs 22.14+, docs recommend 24+)"
else warn "node not on PATH (OpenClaw installer can provide it)"; fi
if have openclaw; then ok "openclaw $(oc --version 2>/dev/null | head -1)"
else
  bad "openclaw not installed for $(whoami)"
  if ask "Install OpenClaw now (official installer, no onboarding)?"; then
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard && FIXED=$((FIXED+1))
    for d in "$HOME/.openclaw/bin" "$HOME/.local/bin" "$HOME/.npm-global/bin"; do [ -d "$d" ] && PATH="$d:$PATH"; done
  fi
fi

# ---------- 4. gateway ----------
echo; echo "-- 4. Gateway"
if have ss; then L=$(ss -ltnp 2>/dev/null | grep ':18789 ' || true); [ -n "$L" ] && echo "port 18789: $L" || warn "nothing listening on 18789"; fi
if have openclaw; then
  if oc gateway probe >/dev/null 2>&1; then ok "gateway reachable"
  else
    bad "gateway unreachable"
    if have systemctl && ask "Install/repair + start the OpenClaw gateway service?"; then
      [ $ROOT = 1 ] && loginctl enable-linger root 2>/dev/null
      oc gateway install || oc gateway install --force
      sleep 6
      oc gateway probe >/dev/null 2>&1 && { ok "gateway reachable now"; FIXED=$((FIXED+1)); } || {
        bad "still unreachable — last service logs:"
        journalctl --user -u openclaw-gateway.service -n 25 --no-pager 2>/dev/null || oc logs 2>/dev/null | tail -25; }
    elif ! have systemctl; then warn "no systemd here (managed sandbox?) — use the host's Restart button"; fi
  fi
  echo "-- openclaw doctor"; oc doctor 2>&1 | tail -25 || true
fi

# ---------- 5. Kimi Claw installer failures ----------
echo; echo "-- 5. Kimi Claw installer logs"
KL=$(ls -t "$HOME"/.kimi/kimi-claw/log/install_fail_*.log 2>/dev/null | head -1 || true)
if [ -n "$KL" ]; then
  bad "last Kimi install failed: $KL"
  tail -30 "$KL"
  T=$(cat "$KL")
  echo "$T" | grep -qiE 'ENOSPC|no space left' && echo "   → cause: DISK FULL (step 1 fixes)"
  echo "$T" | grep -qiE 'ENOMEM|heap out of memory|Killed|signal 9|SIGKILL' && echo "   → cause: OUT OF MEMORY (step 2 swap fixes)"
  echo "$T" | grep -qiE 'EADDRINUSE|address already in use|18789' && echo "   → cause: PORT IN USE — an OpenClaw gateway is already running here; Kimi's installer wants its own. Stop one: 'openclaw gateway stop' then re-run Kimi's installer."
  echo "$T" | grep -qiE 'EACCES|permission denied' && echo "   → cause: PERMISSIONS — run Kimi's installer as root"
  echo "$T" | grep -qiE 'ETIMEDOUT|ECONNRESET|ENOTFOUND|network|fetch failed|429' && echo "   → cause: NETWORK — just re-run Kimi's installer"
  echo "$T" | grep -qiE 'node.*(version|engine)|Unsupported engine' && echo "   → cause: NODE VERSION too old"
  echo "   After fixes: re-run the exact install command Kimi gave you."
else ok "no Kimi installer failure logs"; fi

# ---------- 6. Cloudclaw workspace ----------
echo; echo "-- 6. Cloudclaw workspace"
WS="$HOME/.openclaw/workspace"
if [ -f "$WS/AGENTS.md" ] && grep -q "Conductor" "$WS/AGENTS.md"; then
  ok "Cloudclaw files present; skills: $(find -L "$WS/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l)"
  [ -f "$WS/BOOTSTRAP.md" ] && warn "BOOTSTRAP.md not done yet — tell the agent: Read AGENTS.md and run BOOTSTRAP.md."
else
  bad "Cloudclaw workspace not loaded"
  if have openclaw && [ "$(free_gb)" -ge 1 ] && ask "Load Cloudclaw workspace + skills (symlinked)?"; then
    curl -fsSL "$RAW/ocs-kimi-claw.sh" -o "$HOME/ocs.sh" && LINK=1 bash "$HOME/ocs.sh" </dev/null && FIXED=$((FIXED+1))
  fi
fi

# ---------- summary ----------
echo; echo "== Summary: $ISSUES issue(s) found, $FIXED fix(es) applied =="
[ "$ISSUES" -gt "$FIXED" ] && echo "Re-run to confirm, or send Claude this file: $LOG"
echo "Full report: $LOG"
