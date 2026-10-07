#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/legal-war-room/SKILL.md"
README="$ROOT/README.md"
INSTALLER="$ROOT/scripts/install-skills-everywhere.sh"

fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS: %s\n' "$*"; }

[[ -f "$SKILL" ]] || fail "legal-war-room/SKILL.md is missing"

name="$(awk 'BEGIN{n=0} /^---$/{n++;next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$SKILL")"
[[ "$name" == "legal-war-room" ]] || fail "frontmatter name must equal directory name"

desc="$(awk 'BEGIN{n=0} /^---$/{n++;next} n==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$SKILL")"
[[ -n "$desc" ]] || fail "description missing"
((${#desc} <= 1024)) || fail "description exceeds 1024 chars"
grep -Eqi 'motion|order to show cause|article 78|mandamus|surplus|foreclosure|court filing|legal research' <<<"$desc" || fail "description lacks legal trigger phrases"
grep -Fq '/legal-war-room' <<<"$desc" || fail "description lacks explicit /legal-war-room trigger"

for required in \
  'Primary-authority' \
  'Procedural posture' \
  'Remedy ladder' \
  'Adversarial' \
  'Judge' \
  'Opposing counsel' \
  'Appellate' \
  'Fact provenance' \
  'Uncertainty' \
  'Service matrix' \
  'Citation' \
  'Prove-me-wrong' \
  'Fatal-defect' \
  'Proposed order'; do
  grep -Fqi "$required" "$SKILL" || fail "missing required concept: $required"
done

grep -Fq '`legal-war-room`' "$README" || fail "README skills report does not list legal-war-room"\n! grep -Fq '\\\\n' "$README" || fail "README contains literal \\\\n escape text"
grep -Eq 'DEFAULT_SET=.*legal-war-room|DEFAULT_SET=\([^)]*legal-war-room' "$INSTALLER" || fail "default installer does not include legal-war-room"

pass "legal-war-room structure, discovery triggers, quality gates, report entry, and default installation"
