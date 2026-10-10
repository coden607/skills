#!/usr/bin/env bash
# install-all-ai-skills.sh — permanent Coden607 skills wiring for major CLI runtimes.
# Safe/idempotent: preserves unrelated instruction content and refreshes only managed blocks.
set -euo pipefail

REPO_URL="${CODEN_SKILLS_REPO:-https://github.com/coden607/skills.git}"
ROOT="${CODEN_SKILLS_ROOT:-$HOME/.coden607/skills}"
BIN="$HOME/bin"
STAMP="$HOME/.coden607/.last-sync"
START="<!-- CODEN607 SKILLS GLOBAL RULES -->"
END="<!-- END CODEN607 SKILLS GLOBAL RULES -->"

have(){ command -v "$1" >/dev/null 2>&1; }
ok(){ printf '✔ %s\n' "$*"; }

have git || { echo "git is required" >&2; exit 1; }
have python3 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$(dirname "$ROOT")" "$BIN"

if [[ -d "$ROOT/.git" ]]; then
  git -C "$ROOT" fetch -q origin main
  git -C "$ROOT" merge --ff-only -q origin/main
else
  git clone -q --depth 1 "$REPO_URL" "$ROOT"
fi
ok "canonical repo synced -> $ROOT"

managed_block(){
  local file="$1" body="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  python3 - "$file" "$START" "$END" "$body" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
body = sys.argv[4]
text = path.read_text(encoding="utf-8")
block = f"{start}\n{body.rstrip()}\n{end}"

if start in text and end in text:
    before = text.split(start, 1)[0].rstrip()
    after = text.split(end, 1)[1].lstrip()
    text = (before + "\n\n" if before else "") + block + ("\n\n" + after if after else "\n")
else:
    text = text.rstrip() + ("\n\n" if text.strip() else "") + block + "\n"

path.write_text(text, encoding="utf-8")
PY
}

# Claude: compressed descriptions, complete bodies/support files.
mkdir -p "$HOME/.claude/skills"
python3 -I "$ROOT/scripts/compress-skills.py" "$ROOT" "$HOME/.claude/skills"
managed_block "$HOME/.claude/CLAUDE.md" "Canonical skills: $ROOT
Before substantial work, read $ROOT/bundle.md, select the smallest matching skill set, and load only those SKILL.md files."

# Codex: native canonical skills.
bash "$ROOT/scripts/install-skills-everywhere.sh" -A -s "$ROOT" -t "$HOME/.codex/skills"
managed_block "$HOME/.codex/AGENTS.md" "Canonical skills: $ROOT
Before substantial work, read $ROOT/bundle.md and load only the smallest matching SKILL.md set."

# Grok Build: native user skills + global AGENTS.md.
bash "$ROOT/scripts/install-skills-everywhere.sh" -A -s "$ROOT" -t "$HOME/.grok/skills"
managed_block "$HOME/.grok/AGENTS.md" "Canonical skills: $ROOT
Native skills are installed in ~/.grok/skills.
Read $ROOT/bundle.md first, then load only the smallest matching skill set."

# Gemini CLI: persistent global context pointing at the canonical checkout.
managed_block "$HOME/.gemini/GEMINI.md" "Canonical skills: $ROOT
Before substantial work, read $ROOT/bundle.md. If a skill matches, read and follow its SKILL.md. Do not preload the whole library."

# Kimi Code / generic AGENTS discovery.
managed_block "$HOME/.kimi-code/AGENTS.md" "Canonical skills: $ROOT
Before substantial work, read $ROOT/bundle.md and follow only the smallest matching skill set."
managed_block "$HOME/.agents/AGENTS.md" "Canonical skills: $ROOT
Before substantial work, read $ROOT/bundle.md and follow only the smallest matching skill set."

# Build the offline ChatGPT Project/GPT Knowledge bundle.
CHATGPT_OUT="$HOME/.coden607/chatgpt-bundle"
python3 -I "$ROOT/scripts/build-runtime-bundles.py" --root "$ROOT" --output-dir "$CHATGPT_OUT"
ok "ChatGPT bundle -> $CHATGPT_OUT/coden607-skills-bundle.md"

# Permanent one-command refresh.
cat > "$BIN/skills-sync" <<EOF
#!/usr/bin/env bash
exec bash "$ROOT/scripts/install-all-ai-skills.sh" "\$@"
EOF
chmod +x "$BIN/skills-sync"

# Auto-refresh at most once per 24 hours on shell login.
HOOK='# --- CODEN607 SKILLS AUTO-SYNC ---
export PATH="$HOME/bin:$PATH"
_coden_stamp="$HOME/.coden607/.last-sync"
if [ ! -f "$_coden_stamp" ] || [ $(( $(date +%s) - $(stat -c %Y "$_coden_stamp" 2>/dev/null || echo 0) )) -gt 86400 ]; then
  (skills-sync >/tmp/coden-skills-sync.log 2>&1 && touch "$_coden_stamp") &
fi
# --- END CODEN607 SKILLS AUTO-SYNC ---'

for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$rc"
  grep -q "CODEN607 SKILLS AUTO-SYNC" "$rc" || printf '\n%s\n' "$HOOK" >> "$rc"
done

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"

COUNT="$(find "$ROOT" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
ok "$COUNT canonical skills wired across Claude, Codex, Grok, Gemini and Kimi"
echo "ChatGPT: add $CHATGPT_OUT/coden607-skills-bundle.md plus bundle.md to the Project/GPT once; a VPS cannot silently mutate ChatGPT Project sources."
echo "Refresh anytime: skills-sync"
