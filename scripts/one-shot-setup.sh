#!/usr/bin/env bash
# one-shot-setup.sh — paste this into any fresh Ubuntu VPS and get:
#   claude · codex · gem · kimi · grok  (+ `name yolo` launchers, + permanent all-runtime skills, + API keys)
#
# PASTE-IT-ALL MODE (recommended):
#   curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/one-shot-setup.sh | bash
#
# Keys: already-set env vars win; otherwise it PROMPTS (interactive paste);
#       stored in ~/.ai_keys (600) and auto-sourced by .bashrc.
# Non-interactive runs (no tty) skip prompts gracefully. Idempotent: re-run anytime.
set -uo pipefail

MAIN_REPO="${MAIN_REPO:-$HOME/main-repo}"
WRAPPER_DIR="$HOME/.ai-clis/bin"
KEYS_FILE="$HOME/.ai_keys"
SKILLS_REPO="https://github.com/coden607/skills.git"
MARK="✔"; CROSS="✖"
ok()  { printf '%s %s\n' "$MARK" "$1"; }
bad() { printf '%s %s\n' "$CROSS" "$1"; }
head(){ echo; echo "== $1 =="; }
SUDO=""; [[ "$(id -u)" -ne 0 ]] && SUDO="sudo"
have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- 0. main repo ----------
head "Main repo"; mkdir -p "$MAIN_REPO" && ok "$MAIN_REPO"

# ---------- 1. deps ----------
head "Dependencies"
if ! have node || [[ "$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)" -lt 18 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash - && $SUDO apt-get install -y nodejs
fi
have node && ok "node $(node -v)" || { bad "node install failed"; exit 1; }
if ! have pipx; then $SUDO apt-get install -y pipx >/dev/null 2>&1 || python3 -m pip install --user pipx; python3 -m pipx ensurepath >/dev/null 2>&1; fi
ok "deps ready"

# ---------- 2. CLIs ----------
head "AI CLIs (install missing only)"
npm_i(){ have "$1" && { ok "$1 present"; return; }; $SUDO npm install -g "$2" >/dev/null 2>&1 && ok "$1 installed" || bad "$1 FAILED"; }
npm_i claude @anthropic-ai/claude-code
npm_i codex  @openai/codex
npm_i gemini @google/gemini-cli
if have kimi; then ok "kimi present"; else pipx install kimi-cli >/dev/null 2>&1 && ok "kimi installed" || bad "kimi FAILED (needs Python 3.10+)"; fi
if have grok; then ok "grok present"; else $SUDO npm install -g @xai-official/grok >/dev/null 2>&1 && ok "grok installed (official xAI build)" || bad "grok install FAILED"; fi

# ---------- 3. launchers (yolo flags verified against real --help) ----------
head "Launchers (run from anywhere; yolo = full-auto)"
mkdir -p "$WRAPPER_DIR"
R_claude="$(command -v claude 2>/dev/null||true)"; R_codex="$(command -v codex 2>/dev/null||true)"
R_gemini="$(command -v gemini 2>/dev/null||true)"; R_kimi="$(command -v kimi 2>/dev/null||true)"; R_grok="$(command -v grok 2>/dev/null||true)"
mk(){ [[ -z "$2" ]] && { bad "skip $1 (binary missing)"; return; }
  printf '#!/usr/bin/env bash\ncd "%s" || exit 1\nif [[ "${1:-}" == "yolo" ]]; then\n  shift\n%s\nelse\n  exec "%s" "$@"\nfi\n' "$MAIN_REPO" "$3" "$2" > "$WRAPPER_DIR/$1"
  chmod +x "$WRAPPER_DIR/$1" && ok "$1 ready"; }
mk claude "$R_claude" 'exec "'"$R_claude"'" --dangerously-skip-permissions "$@"'
mk codex  "$R_codex"  'exec "'"$R_codex"'" --dangerously-bypass-approvals-and-sandbox "$@"'
mk gem    "$R_gemini" 'exec "'"$R_gemini"'" --yolo "$@"'
mk gemini "$R_gemini" 'exec "'"$R_gemini"'" --yolo "$@"'
mk kimi   "$R_kimi"   'exec "'"$R_kimi"'" --yolo "$@"'
if [[ -n "$R_grok" ]]; then
  printf '#!/usr/bin/env bash\ncd "%s" || exit 1\nif [[ "${1:-}" == "yolo" ]]; then shift; exec "%s" --yolo "$@"; else exec "%s" "$@"; fi\n' "$MAIN_REPO" "$R_grok" "$R_grok" > "$WRAPPER_DIR/grok"; chmod +x "$WRAPPER_DIR/grok"; ok "grok ready"
fi
for rc in "$HOME/.bashrc" "$HOME/.profile"; do touch "$rc"; grep -q "$WRAPPER_DIR" "$rc" || echo "export PATH=\"$WRAPPER_DIR:\$PATH\"" >> "$rc"; done
ok "PATH hooked"

# ---------- 4. permanent all-runtime skills ----------
head "Permanent Coden607 skills wiring"
if curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/install-all-ai-skills.sh | bash; then
  ok "skills wired across Claude, Codex, Grok, Gemini, Kimi; ChatGPT bundle generated"
else
  bad "permanent skills wiring FAILED"
fi

# ---------- 5. API keys ----------
head "API keys"
touch "$KEYS_FILE"; chmod 600 "$KEYS_FILE"
add_key(){
  local k="$1" hint="$2" v="${!1:-}"
  if [[ -n "$v" ]]; then
    grep -q "export $k=" "$KEYS_FILE" || echo "export $k='$v'" >> "$KEYS_FILE"
    ok "$k (from env)"; return
  fi
  v="$(grep -s "^export $k=" "$KEYS_FILE" | awk -F"'" '{print $2}')"
  if [[ -n "$v" ]]; then ok "$k (already saved)"; return; fi
  if [[ -t 0 ]]; then
    printf 'Paste %s (%s) or Enter to skip: ' "$k" "$hint"
    read -rs v; echo
    if [[ -n "$v" ]]; then echo "export $k='$v'" >> "$KEYS_FILE"; ok "$k saved"; fi
  else
    bad "$k skipped (no tty)"
  fi
}
add_key ANTHROPIC_API_KEY "claude — console.anthropic.com"
add_key OPENAI_API_KEY    "codex — platform.openai.com"
add_key GEMINI_API_KEY    "gemini — aistudio.google.com"
add_key MOONSHOT_API_KEY  "kimi — platform.moonshot.ai"
add_key XAI_API_KEY       "grok — console.x.ai"
grep -q "ai_keys" "$HOME/.bashrc" || echo "[ -f \"$KEYS_FILE\" ] && . \"$KEYS_FILE\"" >> "$HOME/.bashrc"

# ---------- 6. smoke test ----------
head "Smoke test"
for c in claude codex gemini kimi grok; do have "$c" && ok "$c present" || bad "$c missing"; done

echo; echo "DONE ✔  Restart shell (source ~/.bashrc), then:  claude | codex | gem | kimi | grok  (+ 'yolo')"
