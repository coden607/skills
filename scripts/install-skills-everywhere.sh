#!/usr/bin/env bash
# install-skills-everywhere.sh — one-click install of SKILL.md-format skills
# into any CLI agent that reads them (Claude Code, Codex CLI, OpenClaw, etc.).
#
# Usage:
#   ./install-skills-everywhere.sh                 # auto-detect known CLIs, copy mode
#   ./install-skills-everywhere.sh -a              # same as above (explicit)
#   ./install-skills-everywhere.sh -l              # symlink instead of copy (live-updates with source)
#   ./install-skills-everywhere.sh -t ~/.claude/skills   # install to one explicit dir
#   ./install-skills-everywhere.sh -s ./my-skills -t /some/agent/skills
#   ./install-skills-everywhere.sh -h              # help
#
# Exit codes: 0 = all installs OK (or nothing to do), 1 = a target failed.
set -euo pipefail

SRC="$HOME/.openclaw/skills"
MODE="copy"
AUTO=0
TARGETS=()

# The Cole Medin skill set (by folder name). Install only these unless -A given.
DEFAULT_SET=(route-with-jev maintain-second-brain isolate-agent-runs run-software-factory enforce-with-hooks route-interrupts)
INSTALL_ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all-targets) AUTO=1; shift;;
    -A|--all-skills)  INSTALL_ALL=1; shift;;
    -l|--link)        MODE="link"; shift;;
    -s|--source)      SRC="${2:?-s needs a path}"; shift 2;;
    -t|--target)      TARGETS+=("${2:?-t needs a path}"); shift 2;;
    -h|--help)        sed -n '2,14p' "$0"; exit 0;;
    *) echo "Unknown flag: $1 (see -h)" >&2; exit 1;;
  esac
done

[[ -d "$SRC" ]] || { echo "Source not found: $SRC" >&2; exit 1; }

# Auto-detect known CLI skill directories
if [[ $AUTO -eq 1 || ${#TARGETS[@]} -eq 0 ]]; then
  for d in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/claude/skills"; do
    # include existing dirs AND the conventional ones (create them)
    TARGETS+=("$d")
  done
fi

# Build skill list
SKILLS=()
if [[ $INSTALL_ALL -eq 1 ]]; then
  for d in "$SRC"/*/; do
    [[ -f "$d/SKILL.md" ]] && SKILLS+=("$(basename "$d")")
  done
else
  for n in "${DEFAULT_SET[@]}"; do
    [[ -f "$SRC/$n/SKILL.md" ]] && SKILLS+=("$n")
  done
fi

[[ ${#SKILLS[@]} -gt 0 ]] || { echo "No matching skills found in $SRC" >&2; exit 1; }
echo "Installing ${#SKILLS[@]} skill(s) from $SRC [mode: $MODE]"
FAIL=0
for t in "${TARGETS[@]}"; do
  mkdir -p "$t"
  ok=0
  for s in "${SKILLS[@]}"; do
    if [[ "$MODE" == "link" ]]; then
      ln -sfn "$SRC/$s" "$t/$s" && ok=$((ok+1))
    else
      rm -rf "$t/$s.tmp"
      cp -R "$SRC/$s" "$t/$s.tmp" && mv "$t/$s.tmp" "$t/$s" && ok=$((ok+1))
    fi
  done
  echo "  ✔ $t  ($ok/${#SKILLS[@]})"
  [[ $ok -eq ${#SKILLS[@]} ]] || FAIL=1
done

echo
echo "Done. Skills are live in each CLI that scans its skills dir (may need a restart/session refresh)."
exit $FAIL
