#!/bin/sh
# ocs-for-ish.sh — One-Click Skills installer for iSH (Alpine Linux on iPhone).
#
# Paste this single line into iSH:
#   curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/ocs-for-ish.sh | sh
#
# What it does:
#   1. apk-installs git + bash if missing (Alpine/iSH only)
#   2. clones (or fast-forward updates) coden607/skills into ~/skills
#   3. installs skills into every known CLI skills dir (~/.claude/skills,
#      ~/.codex/skills, ~/.config/claude/skills)
#
# Env knobs (prefix the paste with them, or export before running):
#   ALL=1     install EVERY skill in the repo (default: the core 8)
#   BRANCH=x  repo branch (default: main)
#   LINK=1    symlink skills instead of copy (live-updates with the repo)
set -e

REPO="https://github.com/coden607/skills.git"
DIR="$HOME/skills"
BRANCH="${BRANCH:-main}"

echo "== OCS for iSH: one-click skills installer =="

# 1. deps — iSH/Alpine uses apk; elsewhere assume git+bash already exist
if command -v apk >/dev/null 2>&1; then
  missing=""
  command -v git  >/dev/null 2>&1 || missing="$missing git"
  command -v bash >/dev/null 2>&1 || missing="$missing bash"
  if [ -n "$missing" ]; then
    echo ">> apk installing:$missing"
    apk add --no-cache $missing
  fi
elif ! command -v git >/dev/null 2>&1; then
  echo "!! git not found and no apk here — install git first, then re-run" >&2
  exit 1
fi

# 2. clone or update (idempotent — safe to paste again later)
if [ -d "$DIR/.git" ]; then
  echo ">> updating $DIR"
  git -C "$DIR" pull --ff-only
else
  echo ">> cloning $REPO -> $DIR"
  rm -rf "$DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$DIR"
fi

# 3. install into all detected CLI skill dirs
cd "$DIR"
ARGS="-a -s ."
[ "${ALL:-0}"  = "1" ] && ARGS="$ARGS -A"
[ "${LINK:-0}" = "1" ] && ARGS="$ARGS -l"
# shellcheck disable=SC2086
bash scripts/install-skills-everywhere.sh $ARGS

echo
echo "== Done! =="
echo "Core 8 installed (ALL=1 for the full library). Skills are live next session."
