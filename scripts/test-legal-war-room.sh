#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/legal-war-room/SKILL.md"
README="$ROOT/README.md"
INSTALLER="$ROOT/scripts/install-skills-everywhere.sh"
ADAPTIVE="$ROOT/adaptive-persona/SKILL.md"

fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS: %s\n' "$*"; }

[[ -f "$SKILL" ]] || fail "legal-war-room/SKILL.md is missing"
[[ -f "$ROOT/legal-war-room/references/authority-procedure.md" ]] || fail "authority-procedure reference missing"
[[ -f "$ROOT/legal-war-room/references/adversarial-review.md" ]] || fail "adversarial-review reference missing"
[[ -f "$ROOT/legal-war-room/templates/legal-work-matrix.md" ]] || fail "legal-work-matrix template missing"

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

for pointer in \
  'references/authority-procedure.md' \
  'references/adversarial-review.md' \
  'templates/legal-work-matrix.md'; do
  grep -Fq "$pointer" "$SKILL" || fail "SKILL.md does not wire resource: $pointer"
done

grep -Fq '`legal-war-room`' "$README" || fail "README skills report does not list legal-war-room"
if grep -Fq '\n' "$README"; then fail "README contains literal \\n escape text"; fi
grep -Eq 'DEFAULT_SET=.*legal-war-room|DEFAULT_SET=\([^)]*legal-war-room' "$INSTALLER" || fail "default installer does not include legal-war-room"
grep -Fq 'load `legal-war-room` when available' "$ADAPTIVE" || fail "adaptive-persona does not auto-pair legal-war-room"

pass "legal-war-room structure, discovery, resources, quality gates, report, installer, and auto-pair contract"
