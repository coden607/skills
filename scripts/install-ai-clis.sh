#!/usr/bin/env bash
# install-ai-clis.sh — one-click install of AI coding CLIs on Ubuntu VPS
# (driven from iSH on iPhone). Idempotent: re-run anytime, it only adds what's missing.
#
# WHAT YOU GET:
#   Typing...      launches (inside your MAIN_REPO folder):
#     claude       Claude Code
#     codex        OpenAI Codex CLI
#     gem          Google Gemini CLI
#     kimi         Moonshot Kimi CLI
#     grok         xAI Grok CLI (if available via npm)
#   Yolo mode: put "yolo" FIRST ->  claude yolo | codex yolo | gem yolo | kimi yolo | grok yolo
#
# Usage: ./install-ai-clis.sh [--with-skills]
#   --with-skills  also installs the Cole Medin skill set into each CLI's skills dir
set -uo pipefail

MAIN_REPO="${MAIN_REPO:-$HOME/main-repo}"     # <-- EDIT THIS if your repo lives elsewhere
WRAPPER_DIR="$HOME/.ai-clis/bin"
SKILLS_SRC="$HOME/.openclaw/skills"
MARK="\xe2\x9c\x94"; CROSS="\xe2\x9c\x96"

ok()   { printf '%b %s\n' "$MARK" "$1"; }
bad()  { printf '%b %s\n' "$CROSS" "$1"; }
head() { echo; echo "== $1 =="; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- 0. Main repo ----------
head "Main repo folder"
mkdir -p "$MAIN_REPO" && ok "exists: $MAIN_REPO (launchers cd here)"

# ---------- 1. Runtime deps ----------
head "Runtime dependencies"
if ! need_cmd node || [[ "$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)" -lt 18 ]]; then
  echo "Installing Node.js 22 (NodeSource)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs
fi
need_cmd node && ok "node $(node -v)" || { bad "node failed"; exit 1; }
need_cmd npm  && ok "npm $(npm -v)"   || { bad "npm failed"; exit 1; }

if ! need_cmd pipx; then
  sudo apt-get install -y pipx >/dev/null 2>&1 || python3 -m pip install --user pipx
  python3 -m pipx ensurepath >/dev/null 2>&1
fi
ok "pipx present"

# ---------- 2. Install CLIs (skip if present) ----------
head "Installing CLIs (only missing ones)"
declare -A PKG=(
  [claude]="@anthropic-ai/claude-code"
  [codex]="@openai/codex"
  [gemini]="@google/gemini-cli"
)
for name in claude codex gemini; do
  bin="$(command -v "$name" || true)"
  if [[ -n "$bin" ]]; then ok "$name already installed ($bin)"; continue; fi
  echo "npm i -g ${PKG[$name]} ..."
  sudo npm install -g "${PKG[$name]}" >/dev/null 2>&1 && ok "$name installed" || bad "$name install FAILED"
done

if need_cmd kimi; then ok "kimi already installed ($(command -v kimi))"
else
  echo "pipx install kimi-cli ..."
  pipx install kimi-cli >/dev/null 2>&1 && ok "kimi installed" || bad "kimi install FAILED (needs Python 3.10+)"
fi

if need_cmd grok; then ok "grok already installed ($(command -v grok))"
else
  echo "Trying npm grok-cli (community; xAI has no official CLI yet)..."
  sudo npm install -g grok-cli >/dev/null 2>&1 && ok "grok installed" || bad "grok not available via npm — set XAI_API_KEY and use any OpenAI-compatible client"
fi

# ---------- 3. Launchers (name + name-yolo) ----------
head "Launchers in $WRAPPER_DIR"
mkdir -p "$WRAPPER_DIR"

# resolve REAL binary paths NOW (before wrappers shadow them on PATH)
resolve() { command -v "$1" 2>/dev/null || echo ""; }
REAL_claude="$(resolve claude)"; REAL_codex="$(resolve codex)"
REAL_gemini="$(resolve gemini)"; REAL_kimi="$(resolve kimi)"; REAL_grok="$(resolve grok)"

make_wrapper() { # $1=launcher name  $2=real path  $3=yolo flags
  [[ -z "$2" ]] && { bad "skip $1 (real binary not found)"; return; }
  cat > "$WRAPPER_DIR/$1" <<EOF
#!/usr/bin/env bash
# auto-generated launcher -> cd $MAIN_REPO then run $1
cd "$MAIN_REPO" || exit 1
if [[ "\${1:-}" == "yolo" ]]; then
  shift
  exec "$2" $3 "\$@"
else
  exec "$2" "\$@"
fi
EOF
  chmod +x "$WRAPPER_DIR/$1" && ok "$1 -> $2 (yolo flags: ${3:-none})"
}

make_wrapper claude "$REAL_claude" "--dangerously-skip-permissions"
make_wrapper codex  "$REAL_codex"  "--dangerously-bypass-approvals-and-sandbox"
make_wrapper gem    "$REAL_gemini" "--yolo"
make_wrapper gemini "$REAL_gemini" "--yolo"
make_wrapper kimi   "$REAL_kimi"   "--yolo"
# grok: community chat CLI, no agent mode — wrapper runs normally (see generated file)

# PATH hook
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [[ -f "$rc" ]] || touch "$rc"
  grep -q "$WRAPPER_DIR" "$rc" || echo "export PATH=\"$WRAPPER_DIR:\$PATH\"" >> "$rc"
done
ok "PATH hook added to .bashrc/.profile"

# ---------- 4. Optional: skills into every CLI ----------
if [[ "${1:-}" == "--with-skills" && -f "$HOME/Downloads/cole-medin-skills/install-skills-everywhere.sh" ]]; then
  head "Installing Cole Medin skills into all CLI skill dirs"
  bash "$HOME/Downloads/cole-medin-skills/install-skills-everywhere.sh" -a
fi

# ---------- 5. API key report ----------
head "API keys — set any you're missing (add to ~/.bashrc or ~/.ai_keys)"
check_key() { if [[ -n "${!1:-}" ]]; then ok "$1 set"; else bad "$1 missing -> $2"; fi; }
check_key ANTHROPIC_API_KEY   "claude auth (or run: claude login)"
check_key OPENAI_API_KEY      "codex auth (or run: codex login)"
check_key GEMINI_API_KEY      "gemini auth (or run: gemini --auth)"
check_key MOONSHOT_API_KEY    "kimi auth"
check_key XAI_API_KEY         "grok auth"

echo
echo "DONE. Restart your shell (or: source ~/.bashrc), then from anywhere type:"
echo "  claude | codex | gem | kimi | grok      (launches in $MAIN_REPO)"
echo "  claude yolo | codex yolo | gem yolo ... (full-auto mode)"
