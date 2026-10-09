#!/usr/bin/env bash
# cloudclaw-all.sh — ONE paste for everything: diagnose + fix → install/repair OpenClaw + gateway → load Cloudclaw → final check.
#   curl -fsSL "https://raw.githubusercontent.com/coden607/skills/main/scripts/cloudclaw-all.sh?$(date +%s)" -o all.sh && bash all.sh
# Auto-approves only safe fixes: clear caches/temp/old OCS backups, add 2G swap, install/repair OpenClaw gateway,
# symlink skills, load Cloudclaw files. ASK=1 = confirm each fix instead. Never touches other services or your data.
# Knobs: AGENT_NAME=Cloudclaw  ROLE=all|acquisition|repos  ASK=1
set -uo pipefail
RAW="https://raw.githubusercontent.com/coden607/skills/main/scripts"
D="$HOME/.cloudclaw-ocs"; mkdir -p "$D"
get(){ curl -fsSL "$RAW/$1?$(date +%s)" -o "$D/$1" || { echo "❌ download failed: $1"; exit 1; }; }
get cloudclaw-doctor.sh; get cloudclaw-up.sh
AUTO=1; [ "${ASK:-0}" = 1 ] && AUTO=0

echo "######## 1/3 diagnose + fix ########"
YES=$AUTO DOCTOR_SKIP_WS=1 bash "$D/cloudclaw-doctor.sh"

echo; echo "######## 2/3 OpenClaw gateway + Cloudclaw ########"
AGENT_NAME="${AGENT_NAME:-Cloudclaw}" ROLE="${ROLE:-all}" bash "$D/cloudclaw-up.sh"

echo; echo "######## 3/3 final check (read-only) ########"
NOFIX=1 bash "$D/cloudclaw-doctor.sh" | tail -40

echo
echo "Done. If everything above is ✅, DM your bot:  Read AGENTS.md and run BOOTSTRAP.md."
echo "If any ❌ remains, screenshot the Summary line + the ❌ lines and send to Claude."
