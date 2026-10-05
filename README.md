# skills
Seven agent skills distilled from Cole Medin's agentic-coding videos (21-video sweep, 2026-10-05) — plus one-click installers to arm any CLI with them.

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

## Install (any SKILL.md-format CLI: OpenClaw, Claude Code, Codex...)
```bash
git clone https://github.com/coden607/skills.git
./skills/scripts/install-skills-everywhere.sh -s skills -t ~/.claude/skills   # or ~/.codex/skills, etc.
```

## Also included
- `scripts/install-ai-clis.sh` — one-click install of claude/codex/gem/kimi/grok CLIs with `yolo` launchers
- `scripts/one-shot-setup.sh` — the FULL bootstrap: paste one curl line → CLIs + launchers + skills + API-key prompts
- `chatgpt-bundle/` — self-contained .md bundle + install guide for ChatGPT (Custom GPTs / Projects)

Skill format: SKILL.md frontmatter (name + description) + optional references/. Compatible with any agent that scans SKILL.md skills dirs.
