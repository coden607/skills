#!/usr/bin/env bash
# sync-github-skills.sh — make GitHub the permanent source of truth for skills.
# Pulls coden607/skills and copies every skill dir into ~/.openclaw/skills/
# (overwrite repo-canonical ones; NEVER deletes local-only skills).
# Safe to run anytime. Steve's standing rule: run when drift is suspected.
set -euo pipefail
SKILLS_HOME="${HOME}/.openclaw/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ cloning coden607/skills (canonical)"
gh repo clone coden607/skills "$TMP/skills" -- -q
cd "$TMP/skills"

synced=0
for d in */; do
  d="${d%/}"
  [ -f "$d/SKILL.md" ] || continue          # only real skill dirs
  mkdir -p "$SKILLS_HOME/$d"
  rsync -a --delete "$d/" "$SKILLS_HOME/$d/"
  synced=$((synced+1))
done

# clean stray packaging temp files
find "$SKILLS_HOME" -name '*.tmp' -delete 2>/dev/null || true
echo "✓ $synced skills synced from GitHub → $SKILLS_HOME (local-only skills preserved)"
