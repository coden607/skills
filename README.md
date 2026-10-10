# skills
Eight core agent skills, including the legal-war-room workflow, built alongside skills distilled from Cole Medin's agentic-coding videos (21-video sweep, 2026-10-05) — plus one-click installers to arm any CLI with them.

## The skills
| Skill | What it does |
|---|---|
| `route-with-jev` | Route classification/routing/guardrail decisions through Jev (system-one decision model) at ~1/1000th LLM cost |
| `maintain-second-brain` | State-vs-event memory classification + anti-rot audits across MEMORY.md / daily logs / KB |
| `isolate-agent-runs` | Sandbox yolo-mode agents; dumb-zone awareness; destructive-op gates |
| `run-software-factory` | Autonomy levels + PRD→PR pipeline + 30-min triage cron loops |
| `enforce-with-hooks` | Hook-event design; regex→Jev→LLM judge ladder; 4 recipes |
| `route-interrupts` | Mid-task interruptions add to or queue behind the active work — never silently kill it |
| `compress-token-spend` | Cut token/$ spend: tier routing, cache-aware prompts, output discipline, 10% judge sampling |
| `legal-war-room` | On-demand litigation-grade legal research, procedural/remedy selection, adversarial judge/opponent/appellate review, service/citation verification, and filing quality gates |

## Install (any SKILL.md-format CLI: OpenClaw, Claude Code, Codex...)
```bash
git clone https://github.com/coden607/skills.git
./skills/scripts/install-skills-everywhere.sh -s skills -t ~/.claude/skills   # or ~/.codex/skills, etc.
```

## Claude Code cloud — compressed catalog

Keep all 51 skills installed while shortening only the descriptions Claude scans before selecting a skill:

```bash
git clone --depth 1 https://github.com/coden607/skills /tmp/coden-skills && mkdir -p ~/.claude/skills && python3 -I /tmp/coden-skills/scripts/compress-skills.py /tmp/coden-skills ~/.claude/skills
```

`compress-skills.py` copies every top-level skill and all support files, keeps the full `SKILL.md` body unchanged, and rewrites only the top-level frontmatter `description`. The source checkout is never modified.

## iSH (iPhone) — one paste
```sh
curl -fsSL https://raw.githubusercontent.com/coden607/skills/main/scripts/ocs-for-ish.sh | sh
```
Installs git+bash via apk if needed, clones/updates this repo into `~/skills`, and installs the core 8 skills into `~/.claude/skills` + `~/.codex/skills` + `~/.config/claude/skills`. Re-paste anytime to update. `ALL=1` prefix installs all 51 skills, `LINK=1` symlinks instead of copying.

## Also included
- `scripts/install-ai-clis.sh` — one-click install of claude/codex/gem/kimi/grok CLIs with `yolo` launchers
- `scripts/one-shot-setup.sh` — the FULL bootstrap: paste one curl line → CLIs + launchers + permanent cross-runtime skills + API-key prompts
- `scripts/install-all-ai-skills.sh` — canonical permanent wiring for Claude, Codex, Grok, Gemini and Kimi, plus a generated ChatGPT bundle
- `scripts/build-runtime-bundles.py` — builds a complete offline ChatGPT Project/GPT Knowledge bundle from the live skill tree
- `bundle.md` — tiny runtime router that forces lazy selection from the canonical library
- `chatgpt-bundle/` — ChatGPT Project/GPT instructions and install guide

Skill format: SKILL.md frontmatter (name + description) + optional references/. Compatible with any agent that scans SKILL.md skills dirs.

## Full installed set (2026-10-10)

The repo root now also contains the Cole Medin skill set from [coleam00/skills](https://github.com/coleam00/skills) (MIT) plus `adaptive-persona` and `jev-gate`. Each `SKILL.md` has a Grok runtime block so the procedure runs without Claude Code slash commands.

Install every skill folder that has a `SKILL.md`:

```bash
./scripts/install-skills-everywhere.sh -A -s . -t ~/.openclaw/skills
```


## Permanent cross-runtime install

Run this from a checkout of the repository:

```bash
bash scripts/install-all-ai-skills.sh
```

It maintains a canonical checkout at `~/.coden607/skills`, installs Claude's
compressed catalog, installs canonical native skills into Codex and Grok Build,
and writes managed instruction blocks for Gemini and Kimi without replacing
unrelated instructions. It also creates `~/bin/skills-sync` and a once-per-day
login refresh.

Grok Build is a first-class target: native skills go to `~/.grok/skills` and
global routing guidance goes to `~/.grok/AGENTS.md`.

## ChatGPT adapter

ChatGPT does not read a VPS skill directory directly. Use `bundle.md` as the
live router when GitHub access is available. For an offline Project/GPT
Knowledge file, generate one from the canonical tree:

```bash
python3 scripts/build-runtime-bundles.py --output-dir /tmp/coden607-chatgpt
```

Then add `coden607-skills-bundle.md` and `bundle.md` to the ChatGPT Project
or GPT Knowledge, and use `chatgpt-bundle/PROJECT-INSTRUCTIONS.md` as the
project/GPT instructions.
