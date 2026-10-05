# Cole Medin Skill Set — ChatGPT Knowledge Bundle

Six agent skills. Each section: the skill name, WHEN TO USE it (trigger description), and the full operating procedure. Apply whichever section matches the task.

---

## SKILL: route-with-jev


**Skill name:** route-with-jev
description: >-
  Route decisions through Jev (typesafe/jev-1.13, the "system-one" decision
  model) via OpenRouter's /v1/systemone endpoint, instead of spending LLM
  calls on classification, routing, and guardrails. USE when: (1) routing a
  task, ticket, PR, or user query to a model tier or pipeline before invoking
  an expensive LLM (see workspace/orchestration/models.yaml tiers); (2) adding
  a pre-tool-use guardrail hook (is this action exposing secrets? destroying
  data? exfiltrating? off-task?) with near-zero false positives; (3) a loop
  needs fast repeated next-action decisions (browser automation, gameplay
  testing, workflow classification); (4) replacing regex/keyword classifiers
  with calibrated probability decisions. Trigger phrases: "route with Jev",
  "Jev classify", "model tier", "Jev guardrail", "decision endpoint",
  "system one", "cheap routing layer". DO NOT USE for: text generation,
  reasoning, creative writing, multi-step analysis, or anything a simple
  function/regex does cheaper — Jev decides, it does not think or write.


# Route With Jev

Make cheap, fast, calibrated decisions with Jev (`typesafe/jev-1.13` on
OpenRouter) so expensive LLM calls only fire where they earn their tokens.

## The Iron Rule: Never Jev Alone

Jev is a system-one decision model. It generates decisions — not text, not
reasoning, not code. Every Jev call lives inside an LLM sandwich:

```
LLM builds the harness  →  Jev decides  →  LLM acts on the decision
```

1. **LLM builds the harness.** The LLM writes the state serializer, the typed
   questions, the thresholds, and the action mapping. This is one-time design
   work — reasoning work, which is LLM territory.
2. **Jev decides.** Given state + multiple-choice questions, Jev returns a
   calibrated probability per question in ~0.2s.
3. **LLM acts.** The LLM (or plain code) executes the chosen branch, then
   handles anything Jev flagged — review, block, escalate.

If you find yourself wanting Jev to "explain why," stop. That is a hint the
question belongs to the LLM layer, or the state doesn't contain the answer.

## When to Offload a Decision to Jev

Offload when ALL of these hold:

- **Multiple-choice.** The answer space is a small fixed set (yes/no, tier
  names, next actions). If the answer is open-ended prose, use an LLM.
- **Repeated or latency-sensitive.** The decision fires per tool call, per
  tick (60fps gameplay), per incoming item, or per loop iteration where an
  LLM call (seconds, whole cents) is untenable.
- **Judgment, not computation.** The decision needs semantic understanding
  (is this destructive? is this off-task?) — too fuzzy for regex, too cheap
  for an LLM.
- **Calibrated thresholds help.** You act on confidence (`block if p > 0.8`),
  which requires Jev's calibrated probabilities, not vibes.

Use plain code (not even Jev) when the rule is exact and enumerable — a
deterministic check (path prefix, command name) is free and cannot drift.

## Cost Discipline

Internalize these numbers before designing anything:

- **Jev pricing (1.13):** ~$0.042/M input tokens; **output is free**.
- **A Jev decision call costs roughly 1/1000th of an LLM call.** Dozens of
  routing decisions run about $0.004 total. The logged end-to-end pipeline
  test classified a task at 97% confidence for $0.0000168.
- **Input is the only meter.** Keep state compact — a Jev call fed a bloated
  state stops being "practically free."
- **Routing saves more than it spends.** Mis-tiering costs $2–$50/M tokens of
  LLM overkill. One $0.000017 Jev call per job pays for itself on the first
  prevented over-tier.

Grade non-trivial routed jobs in `workspace/orchestration/outcomes.jsonl`
(skip chitchat/simple). Two consecutive grades < 3 on the same task_type →
raise that task_type's tier permanently. Steve can pin any task_type to any
tier — human override beats the loop.

## State Design

State is the situation description Jev scores. Design it like a brief for a
fast reader, not a dump for a database.

- **Include:** the minimum facts that determine the answer. For hooks: tool
  name, input args, cwd, current objective. For routing: the raw query/ticket
  text plus task hints (source, labels, size).
- **Cut:** logs, full file contents, history, anything not load-bearing for
  the questions. Every token is billed input.
- **Keep it structured when cheap:** a short JSON or labeled lines parse
  better than a wall of prose. `jev_decide.py` accepts `@file.json` for
  structured state.
- **Write questions against the state you actually send.** If the question
  needs a fact missing from state, the calibration is fiction. Fix the state,
  not the threshold.

## Typed Questions

Jev answers three question types, each as a calibrated probability:

| Type | Meaning | Criteria shape | Example |
|---|---|---|---|
| `noul` | yes/no probability 0..1 | none (or guidance) | "Is this action exposing secrets?" |
| `choice` | pick one option | `{option: definition}` map | tier selection across 8 tiers |
| `score` | level on ordered scale | ordered list of level descriptions | urgency 1–5 |

Rules for good questions:

- **One decision per key.** "Which tier?" is a `choice`. "Is it urgent AND
  which tier?" is two questions. Jev answers each in parallel — split them.
- **Write definitions into the criteria.** A `choice` with bare option names
  forces Jev to guess your taxonomy. One line of definition per option fixes
  drift across domains — this is what makes Jev general where task-specific
  classifiers aren't.
- **Set thresholds before you see answers.** Decide "block if p > 0.8" up
  front. Tuning thresholds to observed outputs defeats calibration.

## Calling Jev

Use the existing bridge — do not re-implement the client:

```
/root/.openclaw/skills/youtube-learn/scripts/jev_decide.py
```

```bash
# Key resolution: $OPENROUTER_API_KEY → ~/.config/jev/api_key → workspace/.jev_key
jev_decide.py --state "Convert this bash script to PowerShell" \
  --questions '{"tier": {"type": "choice", "instructions": "Which model tier should handle this?", "criteria": {"simple": "extraction/rewrite", "code": "patches/scripts", "reasoning": "analysis/planning"}}}'

jev_decide.py --state @ticket.txt --questions @qs.json   # file-based
jev_decide.py --selftest                                   # verify the key
```

It POSTs `{model, state, questions}` to `https://openrouter.ai/api/v1/systemone`
(model `typesafe/jev-1.13`) and prints the full response JSON: `answers` +
`usage` (including cost) + confidence scores. Exit codes: 0 ok, 3 bad
input/missing key, 4 API error — wire 3/4 to fail-closed in guardrails.

## Worked Patterns

Full annotated examples (hook guardrail, tier router, PR triage, browser
loop, anti-pattern teardowns) live in `references/examples.md` — read it
before implementing a new pattern. Summary:

1. **Hook guardrail.** Pre-tool-use hook sends `{tool_name, args, cwd,
   objective}` as state; four `noul` questions (secrets? destruction?
   exfiltration? off-task?); block the tool call if any returns true above
   threshold. Replaces regex hooks with near-zero false positives at a
   fraction of a penny per call. Fail closed on API error.
2. **Tier router.** Task text as state; one `choice` question over the tier
   names defined in `workspace/orchestration/models.yaml` (simple/chitchat/
   reasoning/code/research/long-doc/creative/frontier), each option defined
   by its `when:` line. Log the decision to outcomes.jsonl, grade the job,
   let the feedback loop move tiers.
3. **Intake triage.** Issue/PR text as state; `choice` for work type
   (bug/feature/docs), `noul` for "needs human review" — routes to review
   depth before any LLM work happens.

## Alignment With Steve's Stack

- **Tier map:** `workspace/orchestration/models.yaml` is the single source of
  truth for tier names and their `when:` conditions. Quote those conditions
  verbatim as `choice` criteria so routing and the map can never drift apart.
- **Learning loop:** `workspace/orchestration/outcomes.jsonl` records graded
  routed jobs; the feedback rules (retry one tier up on grade < 3; bump the
  task_type after two bad grades) close the loop.
- **Review cadence:** models.yaml is refreshed monthly — the model market
  rots. Jev questions that name model tiers must be re-checked then.

## Anti-Patterns

- **Jev alone.** No harness, no acting layer. Jev is the middle of the
  sandwich, never the meal.
- **Free-text questions.** Jev scores fixed options; "summarize this" and
  "what should we do here?" are LLM calls.
- **Bloated state.** Pasting logs or whole files into state burns the one
  meter Jev charges on. Ship the deciding facts only.
- **Regex-grade determinism.** If a rule is exact (path == `/etc/passwd`),
  code it. Jev is for judgment, not string matching.
- **Threshold tuning after peeking.** Setting cutoffs from observed answers
  destroys calibration and re-imports the bias you offloaded Jev to remove.
- **Silent failure.** Jev returning low confidence everywhere usually means
  state/questions mismatch — the state doesn't contain what the questions
  ask. Log and inspect; don't just lower thresholds.
- **Frontier tokens on banter.** Not Jev-related, but same disease: never
  route casual conversation to expensive tiers. chitchat tier exists.

## Resources

- `references/examples.md` — worked examples with config snippets: hook
  guardrail, tier router, intake triage, browser automation loop, and
  anti-pattern teardowns.

### Reference: examples.md

# route-with-jev — Worked Examples

Each example is copy-adaptable. State is deliberately compact — input tokens
are the only thing Jev bills.

---

## 1. Pre-Tool-Use Hook Guardrail

The flagship use case: replace regex hooks with near-zero false positives.
Fires before every tool call; blocks dangerous actions.

**State per call** (build it in the hook, don't cache):

```json
{
  "tool_name": "exec",
  "args": "rm -rf /root/.openclaw/workspace",
  "cwd": "/root/.openclaw/workspace",
  "objective": "clean up temp files from the cole-medin ingest run"
}
```

**Questions** (four nouls, answered in parallel):

```json
{
  "exposes_secrets":  {"type": "noul", "instructions": "Is this action exposing secrets? (reading .env, credentials, key files)"},
  "destroys_data":    {"type": "noul", "instructions": "Is this action destroying data? (removing folders, dropping tables, force-pushing)"},
  "exfiltrates":      {"type": "noul", "instructions": "Is this action sending sensitive data to an external destination?"},
  "off_task":         {"type": "noul", "instructions": "Is this action off-task from the stated objective?"}
}
```

**Decision logic** (plain code, not an LLM):

```python
BLOCK_THRESHOLD = 0.8
if api_error:                       # exit code 4 from jev_decide.py
    block_and_log(...)              # fail closed — never fail open
elif any(a["noul"] > BLOCK_THRESHOLD for a in answers.values()):
    block_and_log(flagged_keys)     # hand the flagged action to the LLM layer
                                    # for a human-readable explanation
else:
    allow()
```

Why this beats regex: `rm -rf ./build` and `rm -rf /root/.openclaw/workspace`
are the same string pattern, very different decisions. Jev reads objective +
args together; regex can't.

---

## 2. Model-Tier Router

Routes a task to a tier in `workspace/orchestration/models.yaml` before any
LLM call. The `criteria` definitions are copied verbatim from the map's
`when:` lines — keep them in sync on the monthly review.

**State:** the task text, plus one line of source context:

```
Task: "patch the date formatter to ISO-8601 and add tests"
Source: user chat · prior tier for this task_type: code (grades: 4,5)
```

**Questions:**

```json
{
  "tier": {
    "type": "choice",
    "instructions": "Which model tier should handle this task? Judge by the task content alone.",
    "criteria": {
      "simple":   "extraction, classification, rewrites, short summaries, formatting",
      "chitchat": "casual conversation, quick Q&A, morale replies",
      "reasoning":"analysis, planning, math, multi-step logic, judgment calls",
      "code":     "patches, migrations, tests, scripts, debugging",
      "research": "web research, cited summaries, competitive intel",
      "long-doc": "transcripts, huge PDFs, repo scans, big corpora",
      "creative": "ad copy, storytelling, voice-heavy writing",
      "frontier": "final review of high-stakes output, hardest problems — needs explicit ask"
    }
  }
}
```

**Act layer:** dispatch to the tier's `primary` model; log the row to
`outcomes.jsonl` after grading. Expected Jev response: `code, confidence ~98%`.
Cost: $0.000017-ish. One wrong route to `frontier` would have cost ~1000×.

Add a second question when intake volume justifies it:
`"needs_human": {"type": "noul", "instructions": "Is this request ambiguous enough that a human should look first?"}` — route p > 0.8 to Steve instead of guessing.

---

## 3. Intake Triage (Issues / PRs / Tickets)

Classifies work before review depth is chosen. State is the raw issue text —
issues are short, so this stays cheap.

**Questions:**

```json
{
  "work_type": {
    "type": "choice",
    "instructions": "What kind of work is this?",
    "criteria": {
      "bug":     "something is broken or behaving incorrectly",
      "feature": "new capability or enhancement",
      "docs":    "documentation-only change",
      "chore":   "refactor, dependency bump, config, no behavior change"
    }
  },
  "security_sensitive": {"type": "noul", "instructions": "Does this touch auth, secrets, payments, or data access?"},
  "review_depth": {
    "type": "score",
    "instructions": "How deep should review go?",
    "criteria": [
      "level 1: skim — title + diff stat",
      "level 2: standard — read the diff",
      "level 3: careful — read the diff and its tests",
      "level 4: deep — read everything plus surrounding context"
    ]
  }
}
```

**Act layer:** security_sensitive p > 0.7 → level 4 + notify; bug → standard
path; chore → skim. PR triage at intake means the expensive review LLM only
reads what deserves it.

---

## 4. Browser / Loop Automation (Decision-Per-Tick)

For loops that iterate faster than any LLM can: browser automation, gameplay
testing (60fps), scrape-and-click walks.

**Sandwich setup (one-time, LLM does this):**
- Translate the page/game state into a compact structured state (element
  labels, visible text, goal line).
- Generate the `choice` question over possible next actions: click X, focus
  Y, scroll, type (free-form text input is pre-generated by the LLM between
  ticks — Jev never writes prose), stop.
- Set the stop threshold.

**Per tick:** serialize state → Jev (~0.2s) → execute → repeat.
**Post-loop:** LLM analyzes what the run surfaced (bugs, anomalies, stuck
points). Jev drove; the LLM reviews.

If Jev keeps picking the same action with confidence collapsing, that's the
low-confidence signal — stop the loop and hand the trace to the LLM.

---

## 5. Anti-Pattern Teardowns

**"Let me add Jev to summarize incoming emails."** — Summarization is
generation. Wrong model class entirely. Jev could decide `needs_reply:
noul`, and the LLM writes the reply. Decision and generation stay split.

**"I'll feed the last 200 tool calls as state for context."** — 200 calls of
args ≈ thousands of billed input tokens per decision, and most of it is
noise. The deciding facts are objective + this call's args + cwd. Ship those.

**"Jev said 0.51 for destroys_data, let me lower the block threshold to 0.5
so it catches more."** — You tuned the threshold to the answer after peeking.
Calibration is the product. At 0.51 with a sane state, the honest read is
"uncertain" → route to the LLM layer for one cheap judgment call, or block.
Thresholds set ex-ante or not at all.

**"Skip the LLM harness step — I'll hand-write the questions inline each
time."** — Works once. Then domains drift and questions quietly rot. The
harness step is what makes questions versioned, reviewable, and re-usable.
One LLM design pass per pattern, not per call.

---

## SKILL: maintain-second-brain


**Skill name:** maintain-second-brain
description: >-
  Classification and audit layer for the second-brain memory stack:
  MEMORY.md + memory/YYYY-MM-DD.md + learning/*-knowledge-base/. Classifies
  each new fact as STATE (replaceable current truth — overwrites stale
  values) or EVENT (timestamped history — append-only), triages it to the
  right tier, detects contradictions between upfront memory and KB pulls,
  runs anti-rot audits, and promotes/demotes knowledge between tiers. Use
  when the user says "remember this" or shares a new fact; when MEMORY.md
  and a KB page disagree; when knowledge feels stale or contradictory; for
  "audit my memory", "audit the knowledge base", "second-brain audit",
  "clean up / curate memory", "is this still true?"; before bulk KB
  ingestion; or when unsure which tier a fact belongs in. Complements
  agent-memory (which owns reflection timing) — this skill owns the HOW:
  classification, contradiction reconciliation, audit procedure.


# Maintain Second Brain

Append-only memory rots. Every incoming fact must be classified **state vs
event** and written so stale values get REPLACED, not accumulated. A
convention like "date everything" gets ~8% compliance; a mandatory
classification step gets 100%. Framework beats convention.

Relationship to `agent-memory`: that skill decides WHEN to reflect and
promote (heartbeat/stop-hook loop). This skill decides HOW: the
classification call, the tier routing, the contradiction reconciliation, and
the audit sweep. Run them together, never as duplicates.

## The stack (Steve's layout)

| Tier | Path | Class | Write rule |
|---|---|---|---|
| Daily log | `memory/YYYY-MM-DD.md` | Event log | APPEND timestamped lines. Never edit history. |
| Curated memory | `MEMORY.md` | Living state | REPLACED in place. Current truth only, one line per fact, every entry dated + sourced. |
| Knowledge base | `learning/*-knowledge-base/` | Mixed | `raw/` = immutable events; `concepts/` + `entities/` + `sources/` = replaceable state. |

KB internals (OKF): `index.md` + `SCHEMA.md` are the agent entry points —
read them before navigating; never load the whole bundle. `raw/<slug>.md` is
`immutable: true` — never hand-edit. Concept/entity pages are synthesized
across sources, each ending in a `## Sources` section tracing every claim to
a video/timestamp. Validate structural changes with the KB's `lint.py`.
Ingestion history lives in the KB's `log.md`; scope in `roadmap.md`.

The KB already implements the state/event split by design — the audit's job
is to keep it honest, not to restructure it.

## Protocol 1 — Classify: state vs event

Ask of every incoming fact: **"If this changed tomorrow, would I edit an
existing line or add a new one?"**

- **STATE** — describes the world AS IT IS NOW. Rates, prices, versions,
  roadmaps, active configs, current tools, standing preferences, contracts,
  "X is now Y". Replaceable: a new value makes the old one FALSE. State has
  exactly one current value per key.
- **EVENT** — something that HAPPENED at a point in time. Deliveries,
  decisions, sessions, signings, failures, "on <date> we did X". Append-only:
  a new event never falsifies an old one. The history itself is the value.

Hybrid rule: a fact that arrives wrapped in a dated happening ("rate
increased to $9.5k on 2026-06-01") is BOTH — record the event AND update
the state. Never let the event record become the state record: state must
read as current truth ("Current rate: $9,500"), not as a timeline you must
reconstruct.

Edge calls: durable user preferences = state; one-off requests = event;
versions of tools/models = state, but pin the old value in the daily log
before replacing ("replaced: X → Y") so the trail survives.

## Protocol 2 — Triage: route to the right tier

Follow the decision tree in
[references/audit-protocol.md](references/audit-protocol.md) — the full
version with edge cases. Summary:

1. **Session-scoped, no future value** → say it, file nothing.
2. **Raw event** → append one timestamped line to today's daily log.
3. **Current-state fact** → update `MEMORY.md` in place: merge into the
   existing line for that key; never add a second line about the same key.
   Date the line and cite the source (`Source: path`).
4. **Durable, structured, search-target** (concept, technique, tool,
   person, framework) → KB. Read `SCHEMA.md` + `index.md` + the pages the
   new material touches BEFORE writing (synthesis, not accretion — the unit
   of knowledge is the idea, not the video). Merge into existing pages when
   additive; create new pages only when the KB's page-creation threshold is
   met; if the new material conflicts with an existing page → Protocol 3.
5. **Too big for MEMORY.md, too general for one daily file** → daily log
   holds the narrative; MEMORY.md gets a one-line pointer
   (`See memory/YYYY-MM-DD.md — <topic>`); the KB gets the synthesis.
6. **"Remember this"** → write to today's log AND apply rule 3/4 immediately
   if durable.

## Protocol 3 — Contradiction detection

The #1 failure mode: always-loaded memory and KB pulls disagree, the agent
sees both, and behaves unpredictably. Prevention is structural; detection
runs at every write.

Before writing state anywhere:
1. Pull the current value from EVERY tier that could hold one: `MEMORY.md`,
  relevant lines in recent daily logs, and the KB (via `index.md` →
  concept/entity pages, or `rg` for the term).
2. Compare. Exact agreement → write. No existing value → write.
3. Conflict → reconcile before writing:
   - **Both dated, one unambiguously newer and authoritative** → newer wins.
     Replace the stale value. Log the correction in today's daily log:
     `Corrected <key>: <old> → <new> (<source>)`.
   - **Ambiguous** (undated, same date, or unclear authority) → do NOT pick.
     Present both values to Steve and ask. Stale memory is worse than no
     memory; a guessed reconciliation is worse than a visible one.
   - **Event chain vs state mismatch** (event log implies a different
     current value than the state line) → the latest event wins; update the
     state and flag the gap in the audit notes.
   - **KB vs MEMORY.md conflict** → KB page cites sources/timestamps and
     wins; MEMORY.md gets corrected with `Source:` pointing at the page.

After reconciling, cascade-check: a changed value often invalidates other
lines (old rate → old budget → old timeline). Follow the chain.

## Protocol 4 — Anti-rot audit

Three cadences, one rule: **propose, don't touch.** The agent flags every
finding; Steve approves; then write using Protocols 1–3. That loop is what
makes audits safe enough to run often.

1. **Pre-write check** — runs at every MEMORY.md write (automatic, part of
   Protocol 3). Cost: seconds.
2. **Weekly sweep** — during an agent-memory heartbeat reflection: scan the
   week's daily logs for state-change events that never updated MEMORY.md;
   check each MEMORY.md line against the week's events for silent overrides.
   Propose corrections as a list.
3. **Deep audit** — on user request ("audit my second brain") or when rot is
   suspected. Full procedure + checklist:
   [references/audit-protocol.md](references/audit-protocol.md). Covers
   MEMORY.md currency, traceability, KB Sources-section integrity, raw/
   immutability, duplicate-concept detection, and `log.md` / `roadmap.md`
   drift. Finish a KB-touching audit with `python lint.py`.

Rot signals that justify a deep audit: agent answers about Steve's own
setup wrong; two confident answers to the same question disagree; MEMORY.md
or KB pages undated; "as of" strings older than ~60 days; the user corrects
a fact the memory system already "knew".

## Protocol 5 — Promotion / demotion between tiers

**Promote** (up = distilled, load-bearing):
- Daily log → MEMORY.md: the fact is durable AND would change a future
  session's behavior AND keeps recurring in logs. One line, dated, sourced.
  This is a filter, not a copy — most log lines stay in the log.
- Log/MEMORY.md → KB: the fact is reference knowledge — a technique, tool,
  person, framework, or synthesized lesson — that future sessions will
  search for. It becomes a concept/entity/source page, or merges into one.

**Demote** (down = archived, searchable):
- MEMORY.md → daily log: a state value goes stale and a newer one replaces
  it — the old value lands in the log with `Replaced by:` (history kept,
  context freed). A MEMORY.md line grows past one line → distill; the full
  version goes to a dated log entry or KB page, MEMORY.md keeps the index
  card. A decision is superseded → demote with the replacement date.
- KB: superseded concept/entity pages are NOT deleted — mark them
  `Superseded by <page>` so links and citations survive. Only raw/ files are
  untouchable; everything else is maintained state.

Never demote silently — always leave a pointer (`Replaced by`, `See`,
`Superseded by`) so retrieval can follow the trail.

## Failure modes this skill exists to prevent

1. **Contradictory tiers** — MEMORY.md says X, KB says Y, agent sees both.
2. **Append-only rot** — outdated state accumulating because nothing gets
   replaced.
3. **Convention without enforcement** — "date everything" style rules that
   rely on the model remembering to comply. Classification is a mandatory
   step, not a style preference.
4. **Unbounded MEMORY.md** — every line costs tokens every turn; stale lines
   are pure cost. Ruthless currency.
5. **Unguarded raw layer** — editing `raw/` transcripts destroys the event
   trail; edits to synthesized pages without updating their Sources section
   break traceability.
6. **Guessing through ambiguity** — reconciling undated conflicts by vibes
   instead of asking.

## Working rules

- Every MEMORY.md line: dated, sourced, one line.
- Every event: timestamped, append-only, in the daily log.
- Every KB claim: traceable to a `## Sources` entry.
- When memory and KB disagree: reconcile BEFORE answering, never after.
- Reconciliation target: exactly one current truth per fact per tier, with
  the history preserved in the event layer.
- Batch the write phase (one proposed-changes list → one approval → apply),
  not ask-per-line.

### Reference: audit-protocol.md

# Audit Protocol — Checklist, Decision Tree, Deep-Audit Procedure

Reference for `maintain-second-brain`. Read this when running a deep audit,
when a classification is non-obvious, or when preparing the batch of
proposed changes for Steve's approval.

## Contents

1. Classification decision tree (incoming information)
2. Contradiction reconciliation matrix
3. Weekly sweep checklist (lightweight)
4. Deep-audit checklist (full)
5. Proposed-changes report format
6. Quick reference: tier routing

---

## 1. Classification decision tree

Start at the top; take the first branch that matches.

```
INCOMING FACT
│
├─ Session-scoped only? (joke, one-off command, transient context,
│   no value beyond this conversation)
│   → FILE NOTHING. Say it, move on.
│
├─ Did something HAPPEN? (delivery, decision, meeting, signing, failure,
│   completed task, session milestone)
│   → EVENT. Append one timestamped line to today's daily log:
│     `- HH:MM — <what happened> (<source/context>)`
│   └─ Does the event CHANGE a current value? (rate changed, tool swapped,
│      plan superseded, version bumped)
│      → ALSO update the state line for that key (see STATE branch) and
│        prepend the log entry with `Replaced <key>: <old> → <new>.`
│
├─ Does it describe how the world IS NOW? (current rate, active config,
│   standing preference, current version, present tool, roadmap focus)
│   → STATE. Update MEMORY.md (or the KB page) IN PLACE:
│     1. Pull the existing line for this key (Protocol 3 pulls).
│     2. No existing line → add one, dated, sourced.
│     3. Existing line, same value → refresh the date, done.
│     4. Existing line, different value → REPLACEMENT:
│        - Old value → today's daily log with `Replaced by:`.
│        - MEMORY.md line rewritten to the new value, re-dated,
│          source cited.
│        - Cascade-check related lines (budget↔rate, tool↔workflow).
│     5. KB page holds the state → edit the page, refresh its frontmatter
│        `updated:` date, and keep the claim's Sources entry honest.
│
├─ Is it reference knowledge? (a technique, framework, concept, tool,
│   person, organization, synthesized lesson — knowledge future sessions
│   will SEARCH for)
│   → KB. Ingestion procedure:
│     1. Read the KB's SCHEMA.md + index.md.
│     2. Read every concept/entity page the material touches.
│     3. Additive (fits existing pages) → merge into those pages; update
│        `updated:`; extend Sources.
│     4. New idea meeting the page-creation threshold (≥2 sources or
│        ≥2 inbound links — per the KB's own schema) → create the page,
│        link it from index/theme, add to the KB's log.md.
│     5. Conflicts with an existing page → CONTRADICTION. Go to §2.
│     6. Raw source material (transcript, document) → write to raw/,
│        immutable + timestamped; a sources/ summary page is its pointer.
│
└─ Big/complex (a full analysis, a long story, a project writeup)?
   → SPLIT ACROSS TIERS:
     - Daily log: the narrative, dated.
     - MEMORY.md: one pointer line — `See memory/YYYY-MM-DD.md — <topic>`.
     - KB: the synthesis, if the content is durable reference knowledge.
```

Rules that apply at every branch:

- Every write is dated. State writes additionally cite the source
  (`Source: <path or URL>`).
- An event line never rewrites another event line. A state line never
  survives unchanged when its value changes.
- Hybrid facts (dated happening + new value) always produce BOTH the event
  record and the state update. Missing one half is the classic rot source.
- When Steve says "remember this": today's log gets the event record AND
  the state/reference branch runs immediately if the content is durable.

## 2. Contradiction reconciliation matrix

Detected during Protocol 3 pre-write pulls, weekly sweeps, deep audits, or
when the user corrects a "known" fact.

| Case | Signals | Resolution |
|---|---|---|
| State vs state, both dated | Two different current values with different dates | Newer authoritative source wins. Replace stale; log correction in today's daily log; cascade-check dependents. |
| State vs state, ambiguous | Undated, same date, or unclear which source is authoritative | STOP. Present both values + sources to Steve; ask. Never guess. |
| Event chain vs state | Event log's latest entry implies a different current value than the state line | Latest event wins. Update state; add a `state lagged behind events` note to the audit findings. |
| MEMORY.md vs KB | Always-loaded line disagrees with a synthesized page | KB page wins IF its Sources section traces the claim — cite the page in the corrected MEMORY.md line. If the page is unsourced, treat as ambiguous and ask. |
| KB vs KB | Two pages describe the same fact differently | Check both pages' Sources timestamps; newer-sourced wins; fix the loser; if sources are the same age, ask Steve. |
| KB duplicate concepts | Same idea under two slugs (e.g. `piv-loop` vs `plan-implement-validate`) | Merge into the canonical slug per the KB's taxonomy; leave the loser as a redirect link; add to log.md. |
| Raw vs synthesized | A sources/concepts/entities page misquotes or contradicts its own raw/ transcript | raw/ is immutable truth. Fix the synthesized page; never edit raw/. |

After ANY reconciliation, run the cascade check: list every other line or
page that referenced the old value, and add each to the proposed-changes
batch.

## 3. Weekly sweep checklist (lightweight, heartbeat-cadence)

Runs alongside the agent-memory reflection pass. ~10 minutes, no approval
needed for findings — produce a proposed list.

- [ ] Read the last 7 days of daily logs (oldest first).
- [ ] Extract every event that implies a state change (rate/version/plan/
      tool/preference changes).
- [ ] For each: is the corresponding MEMORY.md line updated? If not →
      proposed change.
- [ ] Read MEMORY.md line by line: does any line contradict anything in the
      week's logs? Does any line reference something superseded this week?
- [ ] Check every MEMORY.md line still has a current `Source:` that exists.
- [ ] Check for new duplicate keys in MEMORY.md (two lines about the same
      fact) → merge proposal.
- [ ] If any KB work happened this week: confirm new pages were logged in
      log.md and linked from index.md.
- [ ] Output: proposed-changes list in §5 format. Apply only after Steve
      approves.

## 4. Deep-audit checklist (full, user-triggered or rot-suspected)

Scope: MEMORY.md + daily logs + every KB under `learning/`. Read the KB's
SCHEMA.md before touching anything inside it.

### Tier 1 — MEMORY.md

- [ ] Every line dated. Undated line → date it or flag for replacement.
- [ ] Every line sourced and the source path still exists.
- [ ] Exactly one line per fact key — no duplicate-key lines.
- [ ] Each line still TRUE today. Doubtful → verification question for
      Steve (batch them; don't interrogate one at a time).
- [ ] Any "as of" older than ~60 days → recheck against logs and KB.
- [ ] Superseded decisions marked superseded, with the replacement named.
- [ ] Size check: if MEMORY.md has grown since the last audit, confirm
      every added line passes the promotion filter (durable + would change
      a future session). Demote the rest.

### Tier 2 — Daily logs

- [ ] State-change events that never propagated to MEMORY.md → proposed
      updates.
- [ ] Event chains with gaps (decision referenced but no deciding event) →
      note in findings; do not fabricate the missing event.
- [ ] Recent logs carry `memory_search`-friendly keywords (names, projects,
      key nouns) so retrieval can find them later.

### Tier 3 — Knowledge base(s)

- [ ] Every concepts/entities/sources page ends with a `## Sources`
      section, and every claim traces to a source. Unsourced strong claims
      → flag.
- [ ] Frontmatter `updated:` dates exist and are plausible (not older than
      the newest source cited on the page).
- [ ] Duplicate/near-duplicate concept pages under different slugs → merge
      proposal (keep canonical per taxonomy; loser becomes a link).
- [ ] raw/ files untouched and `immutable: true` — no hand-edits anywhere.
- [ ] index.md navigation still matches reality: no links to deleted pages,
      new pages linked in.
- [ ] log.md ingestion entries vs roadmap.md scope — un-ingested queued
      work and stale scope statements → findings.
- [ ] KB-vs-MEMORY.md cross-tier consistency: every fact that exists in
      both tiers agrees in both tiers.
- [ ] After applying approved KB changes: run `python lint.py` from the KB
      root; fix anything it flags.

### Wrap-up

- [ ] Assemble ALL findings into the §5 report — one batch.
- [ ] Steve approves/rejects line by line (or whole-batch).
- [ ] Apply approved changes tier by tier using Protocols 1–3 (correct
      classification per change, not bulk sed).
- [ ] Record the audit itself as an EVENT in today's daily log: scope,
      findings count, changes applied count, lint result.

## 5. Proposed-changes report format

One batch, so approval is one decision:

```markdown
## Second-brain audit — <date> — <scope>

### Proposed changes (<n>)
1. [MEMORY.md] Update "<line>" → "<new line>" (why: <event/source>)
2. [MEMORY.md] Demote "<line>" → daily log 2026-10-05 (why: superseded by #1)
3. [KB entities/tools/foo.md] Update version 1.2 → 2.0, extend Sources (why: <source>)
4. [KB concepts/] Merge bar.md into foo.md (why: duplicate concept, canonical slug foo)
5. [ASK] "<fact>" — two conflicting values: MEMORY.md says X (<date>), KB says Y (<date>). Which is current?

### Findings needing no action (<n>)
- <observations worth knowing but not worth changing>

### Skipped (<n>)
- <considered and deliberately left alone, with reason>
```

Items marked [ASK] block on Steve's answer; everything else can be applied
in one pass after approval.

## 6. Quick reference: tier routing

| What it is | Class | Tier | Write op |
|---|---|---|---|
| "Happened today" — delivery, call, decision | Event | Daily log | Append |
| "Current rate is X" / "I now use Y" | State | MEMORY.md | Replace in place |
| Standing preference, durable constraint | State | MEMORY.md | Replace in place |
| Technique/framework/tool/person/org | Reference | KB concept/entity | Merge or create page |
| Full transcript / source document | Event (raw) | KB raw/ + sources/ | Write once, immutable |
| Synthesized lesson, cross-video pattern | Reference | KB concepts/ | Merge into canonical page |
| Session narrative, too big for a line | Event | Daily log + MEMORY.md pointer | Append + one pointer line |
| Superseded version/rate/plan | State (stale) | Demote to daily log | Append `Replaced by:` |
| Superseded KB page | Reference (stale) | KB — mark `Superseded by` | Edit page, keep link |

---

## SKILL: isolate-agent-runs


**Skill name:** isolate-agent-runs
description: >-
  Isolate autonomous / yolo-mode agent runs so a runaway agent cannot destroy
  the host — sandbox the run, control network egress, gate destructive
  operations, and protect secrets. Use when running a coding agent in
  skip-permissions / autonomous / yolo mode, when a session is approaching
  context limits ("dumb zone"), when wiring agent runs into CI or TaskFlow,
  or when an agent will touch production-shaped resources (databases, git
  remotes, SSH keys). Triggers: "yolo mode", "skip permissions", "run this
  autonomously", "let the agent loose on the repo", "sandbox the agent",
  "don't let it wipe anything", "dumb zone", "context limit errors",
  "agent deleted", "rm -rf", "agent keeps making mistakes late in a long
  session", "prompt guardrails keep failing".


# isolate-agent-runs

**YOLO / autonomous mode is an isolation problem, not a prompt problem.**
Never try to talk an agent out of being destructive. Put walls around it
so destruction is physically impossible, then let it run free inside.

## The core law

Prompt-based guardrails DO NOT WORK for long autonomous runs. An agent may
refuse a risky operation early in a chat, then comply after one follow-up.
Instructions — even system-prompt instructions — decay as context fills.

## The dumb zone

Past roughly **200–300K tokens of context**, agents forget instructions
(including system prompt) and start making catastrophic, confident
decisions. This is the dumb zone.

Signals you are entering it:
- The agent forgets earlier constraints it followed perfectly an hour ago.
- It "helpfully" runs destructive commands it refused to run earlier.
- It re-litigates settled decisions or re-litigates your guardrails.
- Late-session refactors that touch unrelated files; "cleanup" nobody asked for.
- It drops or rewrites git history, stashes, or config it was told to protect.

Rules:
1. **Split long sessions BEFORE the band.** Hand off to a fresh session with
   a state file (see `harness-engineering`) once you approach ~200K tokens.
2. **Never start an autonomous run inside the dumb zone.** A degraded agent
   plus full permissions is how machines get wiped.
3. **Judge isolation, not obedience.** Assume the agent WILL eventually try
   something you told it not to. Design for that moment.

## The isolation stack

Isolation has independent layers. Use as many as the risk warrants —
they stack, and each covers a different failure mode.

### 1. Hypervisor / process isolation
The agent gets full root power INSIDE a sandbox, but the sandbox cannot
touch the host filesystem, processes, or home directory. The host's
`~/.ssh`, browser profiles, dotfiles, and other projects are invisible.

### 2. Network egress control (allow-list)
Outbound requests to non-allowed URLs are blocked by the sandbox proxy
(403 before leaving the box). This is your main defense against
**prompt-injection exfiltration** — a malicious page or dependency README
tricking the agent into curling your API keys to an attacker.

Start with an empty allow-list and add only what the task needs:
package registries, the git remote, specific API hosts.

### 3. Nested engine isolation
The sandbox runs its own Docker daemon / runtime, so host containers,
volumes, and orchestration are untouched even if the agent runs
container commands.

### 4. Workspace isolation
Mount the working directory read-only where possible. For destructive
or git-heavy runs, give the agent a **copy** of the repo so host git
history, stashes, and uncommitted work are physically unreachable.

## Sandbox run pattern (verbatim commands)

Docker Sandboxes (`sbx`) is the reference implementation of this stack —
free, one-command install on Mac/Windows, purpose-built for coding agents.
Adapt the same pattern to any sandbox (VM, container, remote runner).

```bash
# Run the coding agent inside the sandbox (mounts CWD into the VM)
sbx run claude

# Full-isolation mode: sandbox works on a COPY of the repo.
# Host git history, stashes, and uncommitted files are never touched.
sbx run claude --clone

# Destroy the sandbox VM and everything inside it
sbx rm
```

In-sandbox verification (run these the first time, every time):

```bash
!ls            # mounted workspace visible
!ls ~/.ssh     # NOT FOUND — host files invisible
```

## Verify isolation BEFORE trusting the sandbox

Do not give an autonomous run real work until it passes this audit. Give
the agent this prompt inside the sandbox:

```text
"Can you see any of my host files, no matter how hard you try?
Can you reach a service on my host machine? Can you touch the host
Docker socket / mess with my containers?"
```

Expected: every probe fails. If ANY probe succeeds, the sandbox is leaking
— fix it before proceeding. See `references/isolation-playbook.md` for the
full pre-flight checklist.

## Secret & credential handling

Assume every credential reachable by the agent can eventually leak —
through the dumb zone, through prompt injection, through a dependency
README that says "run this to fix your build."

Rules:
1. **The host's secrets must be unreachable.** SSH keys, cloud credentials,
   browser cookies, and dotfiles stay OUTSIDE the sandbox. The `~/.ssh not
   found` check is your proof.
2. **Issue scoped, short-lived credentials.** Give the run a token that can
   only do what the task needs (e.g. one repo, read/write but not admin),
   and expire it when the run ends.
3. **Never put secrets in the prompt or the repo.** If a tool needs a key,
   inject it via environment variable inside the sandbox, not in files the
   agent can read and echo.
4. **Network allow-list limits blast radius.** Even if a key leaks, an
   egress proxy that only allows known hosts prevents it from being phoned
   home.

## Destructive-operation approval gates

These are the horror stories, straight from real agent runs — treat ANY of
them as an automatic STOP and route to a human, no matter what the agent
"says":

- `rm -rf` on anything outside an explicitly-scoped temp directory.
- Dropping, truncating, or migrating a production database.
- `git push --force`, history rewrite, or dropping a stash the user didn't
   explicitly ask to discard.
- Deleting or overwriting files the task never touched ("cleanup").
- Modifying CI/CD, deploy, or IAM configuration.
- Installing packages from unreviewed sources when a lockfile exists.

Implementation:
1. **Deterministic gates, not agent judgment.** Scripts and sandbox policy
   enforce the gate the same way every time. A second agent "reviewing" is
   probabilistic-on-probabilistic — same blind spots as the implementer.
   (See `references/isolation-playbook.md` for gate examples.)
2. **Prefer making destructive ops impossible over making them gated.**
   Read-only mounts, `--clone` mode, and disposable VMs beat approvals.
3. **Human checkpoints at plan approval and done-declaration** — the agent
   never closes its own loop on destructive work. (Overlaps `piv-loop`.)

## Deterministic verification after the run

An agent that finishes its task has NOT proven the task is done — late in
a session it may have "quietly noticed" an issue and only mentioned it in
passing while the fix never happened. After any isolated run:

1. Run the checks via a **script** (tests, lint, type-check, build) — not
   by asking the agent "did it work?"
2. Feed failures back to the agent to iterate; re-run the script; only a
   green script counts as done.
3. In workflow form: `implement → open PR → deterministic scan → agent
   fixes red → re-scan → assert green → ready`.

## Pre-flight checklist (summary)

Full checklist in `references/isolation-playbook.md`. Minimum before any
autonomous run:

- [ ] Run happens inside a sandbox (never yolo on the host).
- [ ] `~/.ssh` and host secrets confirmed unreachable in-sandbox.
- [ ] Network allow-list set; only task-required hosts reachable.
- [ ] Workspace mounted read-only, or repo cloned (`--clone`) for destructive work.
- [ ] Scoped, expirable credentials issued — no long-lived keys.
- [ ] Destructive-op gates scripted, not prompt-based.
- [ ] Session well under the dumb-zone band (~200–300K tokens).
- [ ] Verification script defined BEFORE the run starts.
- [ ] Cleanup path known (`sbx rm` / VM teardown).

## Anti-patterns

- "I told it not to delete things, so it's safe." — prompts decay; isolation doesn't.
- Running skip-permissions / yolo mode directly on the host. Ever.
- Letting one mega-session grind to 500K tokens "to save setup time."
- Approving destructive ops via agent conversation instead of a script gate.
- Trusting a sandbox without running the isolation-verification audit.
- Mounting the whole home directory "for convenience."

## Related skills

- `piv-loop` — human-owned checkpoints (plan approval, done-declaration)
  that pair with these isolation walls.
- `harness-engineering` — state files, handoffs, and multi-session loops
  that keep runs short and out of the dumb zone.
- `taskflow` — durable orchestration for isolated long-running jobs.

### Reference: isolation-playbook.md

# Isolation Playbook — Pre-Flight Checklist & Sandbox Setup

Detailed procedures referenced by `SKILL.md`. Grounded in Cole Medin's
sandboxing/security walkthroughs (see `learning/cole-medin/notes/` in the
workspace: `zb2LyMro77M`, `SGodxQHnVxc`, `SWEThyRHMgQ`).

---

## 1. Full pre-flight isolation checklist

Run through this BEFORE any autonomous / skip-permissions agent run.
Every box must be checked; a single unchecked box is a stop.

### Sandbox & process isolation
- [ ] Agent runs inside a sandbox (VM/container), not on the host.
- [ ] Sandbox has its own runtime/Docker daemon (nested engine) so host
      containers and volumes are unreachable.
- [ ] Host home directory is NOT mounted. Only the task workspace is.
- [ ] For destructive or git-heavy tasks: repo is COPIED into the sandbox
      (`--clone` mode) — host git history/stashes unreachable.

### Secret & credential isolation
- [ ] In-sandbox probe: `!ls ~/.ssh` → **not found**.
- [ ] No host dotfiles, browser profiles, cloud credentials, or env files
      reachable from inside.
- [ ] Credentials issued for this run only: scoped (least privilege),
      short-lived, revocable on completion.
- [ ] Secrets injected via environment, never written to files the agent
      can read/echo, never pasted into prompts.

### Network egress
- [ ] Allow-list configured; default-deny (empty list) start.
- [ ] Only task-required hosts allowed: package registries, git remote,
      specific API endpoints.
- [ ] Verified in-sandbox: request to a non-allowed URL returns 403 from
      the proxy before leaving the box.
- [ ] Test method: ask the agent "can we reach X?" → expect 403 → allow X
      in sandbox config → retest succeeds.

### Context health (dumb-zone check)
- [ ] Session starts well under ~200–300K tokens of context.
- [ ] A handoff/state-file plan exists if the run may grow long
      (see `harness-engineering`).
- [ ] No autonomous run starts inside the dumb zone.

### Destructive-op gates
- [ ] Gates are deterministic (scripts/policy), not agent promises.
- [ ] Any `rm -rf`, prod DB op, force-push, history rewrite, or
      out-of-scope file deletion requires explicit human approval.
- [ ] Verification script (tests/lint/scan) defined BEFORE the run starts
      and run AFTER it finishes — green script = done, not agent's word.

### Cleanup & teardown
- [ ] Teardown path ready: `sbx rm` (or VM delete) destroys the sandbox
      and everything inside it.
- [ ] Run-scoped credentials revoked after teardown.
- [ ] Results extracted (diff/patch/PR) BEFORE teardown.

---

## 2. Docker Sandboxes (`sbx`) setup & commands

Reference sandbox for coding agents. Free; single-command install on
Mac/Windows (see the sbx docs); otherwise hand the docs URL to your coding
agent and have it perform the install inside a throwaway environment.

```bash
# Install Docker Sandboxes (Mac/Windows single command — see docs)

# Run coding agent inside sandbox (mounts current dir into VM)
sbx run claude

# Full isolation: sandbox works on a COPY of the repo
# Host git history, stashes, uncommitted files never touched
sbx run claude --clone

# Remove sandbox VM + everything inside it
sbx rm
```

First-run in-sandbox checks:

```bash
!ls            # mounted workspace visible
!ls ~/.ssh     # not found — host files invisible
```

Allow-list tuning loop (repeat until the task's hosts are reachable and
nothing else is):

1. In sandbox: attempt to reach a needed host → expect 403.
2. Add the host to the sandbox network config allow-list.
3. Retest → succeeds.
4. Attempt a non-allowed host → still 403.

---

## 3. Isolation-verification audit prompt

Give this to the agent the first time (and after any sandbox config change):

```text
"Can you see any of my host files, no matter how hard you try?
Can you reach a service on my host machine? Can you touch the host
Docker socket / mess with my containers?"
```

Expected result: EVERY probe fails. If any probe succeeds, stop, fix the
leak, and re-audit before real work.

---

## 4. Destructive-op gate examples (deterministic, not conversational)

Pattern: a script/policy makes the decision the same way every time.
A second agent reviewing is NOT a gate — same blind spots as the builder.

Examples:

- Filesystem: run with a read-only mount of the workspace; give write
  access only to an explicitly-scoped temp/build directory.
- Git: sandbox clone has no push credentials; pushing requires a
  separate, human-run step outside the sandbox.
- Database: no production DSN exists inside the sandbox; only a seeded
  disposable database is reachable.
- Dependencies: `npm audit` / `bandit` / `trivy` / SonarQube scan runs as a
  script node AFTER implementation, BEFORE merge — red blocks, green passes,
  and the agent iterates until green. (Sub-dependency CVEs count: a clean
  top-level package can still pull in vulnerable sub-dependencies.)
- Workflow form: `implement → open PR → deterministic scan → agent fixes
  red → re-scan → assert green → ready PR`.

Human checkpoints (never skipped): plan approval before implementation;
done-declaration after green verification. The agent never closes its own
loop on destructive work.

---

## 5. Failure stories to keep you honest

Real reported agent failures these gates exist to prevent:

- `rm -rf` of a home directory during an autonomous run.
- Production database wiped by a "cleanup" migration.
- `git stash` dropped — uncommitted work lost permanently.
- API keys exfiltrated after a prompt-injection payload in a fetched
  page/dependency instructed the agent to curl them out.

If your setup would have allowed any of these, the isolation is not done.

---

## SKILL: run-software-factory


**Skill name:** run-software-factory
description: >-
  Build and run an autonomous software factory ("dark factory"): PRDs or
  issues go in, validated reviewed PRs come out — no human reading the
  code. Covers Dan Shapiro's 5 autonomy levels and when work graduates
  from human-in-loop (level 3, see piv-loop) to human-on-the-loop (level
  4) to full auto (level 5); the PRD→spec→slice→build/validate→PR
  pipeline; builder/validator agent separation with holdout test
  scenarios; the guidance layer (global rules / factory rules /
  mission.md); the 30-minute stateful triage cron loop; headless agent
  auth via device-code flows; blue-green deploys; escalation fail-safes.
  Use when setting up a repo that ships its own code, running a 24/7
  autonomous coding pipeline, hardening agent reliability by removing
  yourself from the loop, or deciding how much autonomy a project
  deserves. Triggers: "software factory", "dark factory", "autonomous
  coding pipeline", "issue to PR", "factory mode", "level 4/5 autonomy",
  "ship code without reviewing it", "24/7 coding agent", "PRD in PR
  out".


# run-software-factory

A software factory is a repo that ships its own code: spec in → validated,
reviewed PR out → merged → deployed, with no human looking at the code.
This is NOT vibe coding. It is heavy engineering up front — guidance layer,
validation harness, builder/validator separation — so the loop survives
without you. The payoff: reliability-by-removal. Taking yourself out of the
loop forces you to harden the harness, which improves even your in-loop
agentic engineering.

## Positioning (read first, don't duplicate)

- **`piv-loop`** = level 3 autonomy. Human plans and validates every ticket.
  That is where most work should live. This skill is the graduation path:
  when your proven PIV loop makes YOU the bottleneck, factory mode removes
  the human gates progressively.
- **`harness-engineering`** = the generic multi-session toolbox (state files,
  handoffs, checkpoints). This skill composes those parts into one specific
  machine: the issue-to-PR factory.

## Step 0 — pick the autonomy level (Dan Shapiro's 5 levels)

| Level | Name | Who does what | Use when |
|---|---|---|---|
| 0 | Autocomplete | Human drives; agent suggests | Exploration |
| 1–2 | Assisted | Human drives; agent executes chunks | Learning the codebase |
| 3 | Pair-programmer, mostly hands-off | **Agent writes most code; human plans and validates every ticket** | Default. Most work stays here (see `piv-loop`) |
| 4 | Human-on-the-loop | Human sets direction, reviews outcomes only; loop runs between check-ins | The loop is PROVEN: validation passes consistently, failure patterns already patched into the guidance layer |
| 5 | Full auto | High-level direction only; agent makes all small decisions | Only after level 4 runs clean for a sustained period |

Rule: **level 3 until the system is proven, then graduate.** You can chain
skills into full autonomy — don't until the system is proven. Most teams
overestimate readiness and lose trust in the "productivity mirage" (code is
written fast, but fixing the agent's mistakes costs more than writing it
yourself). Trust is lost because there's no system, not because the models
are bad.

## Step 1 — decide if a project graduates to factory mode

A project qualifies when ALL are true:

1. **Ticket-shaped work** — a backlog of separable issues/PRDs, not one
   ambiguous goal. Re-architecture starts a NEW loop, not a bigger ticket.
2. **A writable mission** — you can state goals AND non-goals precisely
   enough that an agent can reject bad specs (see mission.md below).
3. **Automatable validation** — tests, lint, type-check, build, and/or E2E
   checks the agent can run and iterate against without you. If validation
   requires your judgment every time, you are the loop — stay at level 3.
4. **Proven loop** — you have already shipped several tickets through the
   manual PIV loop with the same guidance files. The factory hardens what
   already works; it does not invent it.

PoC/spiking product ideas is a legitimate factory use even today: the
output is disposable, so lower reliability is acceptable. Production
services demand the full harness below.

## Step 2 — build the guidance layer (3 files, non-negotiable)

The guidance layer is the difference between an agent with a task and a
factory with a mission. Three files, distinct audiences:

1. **`GLOBAL_RULES.md`** — loaded into EVERY session (builder, validator,
   triage). Coding conventions, repo layout, commands ("never guess a
   path"), git discipline. Keep it small — it is loaded everywhere. Update
   it from failure analysis (see Step 7).
2. **`FACTORY_RULES.md`** — stricter rules loaded ONLY in autonomous
   sessions: never force-push, never skip validation, never merge your own
   PR, never touch secrets/prod config, stop after N failed attempts and
   escalate. This is where autonomy gets its guardrails.
3. **`mission.md`** — goals + non-goals + current priorities. The non-goals
   are the killer feature: they let the agent REJECT your specs when out of
   scope. The agent corrects YOU, not just vice versa. The triage step uses
   mission.md to accept/reject/rank incoming issues.

See `references/factory-blueprint.md` for templates of all three.

## Step 3 — write holdout scenarios BEFORE building anything

Holdout scenarios are success tests written before work starts and hidden
from the builder agent — so it cannot design the app just to pass them.
This is the single highest-leverage reliability feature.

- Write them at mission-definition time, not ticket time.
- Store them where the validator can read them and the builder cannot.
- Each scenario = observable behavior ("user can X and sees Y"), not
  implementation detail.
- If a PR passes the builder's visible tests but fails a holdout, that is a
  builder-bias signal — tighten the hidden set.

## Step 4 — wire the pipeline: PRD → spec → slice → build/validate → PR

1. **Triage (gate).** Every incoming issue/PRD is compared against
   `FACTORY_RULES.md` + `mission.md`: accept / reject (out of scope per
   non-goals) / rank. Rejections post a comment explaining why — the agent
   correcting the human is working as designed.
2. **Spec.** Accepted issues get a structured spec: feature description,
   user story, problem statement, context references, files to create/edit,
   task list, and a validation strategy (unit/integration/e2e, lint,
   typecheck). The spec is a **handoff document** — it must carry everything
   a fresh implementation session needs, because context rot kills long
   sessions. A plan that requires the planning conversation is not a plan.
3. **Slice.** Split the spec into slices small enough for ONE fresh
   agent session each: one slice = one build+validate+PR cycle. Small
   slices beat big plans; one mega-prompt for many tickets fails.
4. **Build (builder agent).** Fresh session per slice. The builder gets the
   spec + slice + `GLOBAL_RULES.md` + `FACTORY_RULES.md`. It does NOT get
   holdout scenarios. It implements, runs the visible validation suite, and
   **iterates until validation passes** — optimize for correctness, not
   speed. Then it commits, opens a PR, and stops.
5. **Validate (validator agent — SEPARATE session).** The validator gets:
   the PR diff + holdout scenarios + `GLOBAL_RULES.md` + the mission. It
   does NOT get the plan, the spec, or the builder's reasoning. Run the
   visible tests AND the holdouts. Zero shared context = zero shared bias.
6. **Merge.** Validator approves → merge. Builder never merges its own PR.
7. **Deploy.** Blue-green (see Step 6).

## Step 5 — run the 30-minute triage cron loop

The factory is stateful between runs via labels/state on issues. Cron every
30 minutes, executing in strict priority order:

1. **Fix PR** — address review comments on open PRs.
2. **Review PR** — run the validator on PRs marked needs-review.
3. **Build next approved issue** — pick the highest-ranked accepted issue
   with no open PR; run Step 4.
4. **Triage new** — classify newly filed issues (accept/reject/rank).

State machine per issue: `accepted → in-progress → needs-review → merged`
(or `rejected` at triage, `blocked` on failure). The label IS the state —
the cron run reads state, acts, writes new state, exits. Stateless runs are
what make 30-minute cycles reliable.

- One job per trigger by default. Parallelism (multiple builders) is
  possible but watch rate limits and lock contention on shared files.
- Set an **escalation fail-safe**: after N failed attempts on the same
  blocker, stop and escalate to a human. Configurable to never escalate —
  that is a level-5 choice, own it explicitly.
- When a loop fails twice with the same blocker: STOP. Autonomy is not
  stubbornness.

## Step 6 — deploy blue-green

A factory that only opens PRs is a PR generator, not a shipper. Blue-green:
run two app versions (blue = live, green = standby). The factory updates
green, validates, flips traffic, and the old blue becomes the new standby.
Zero downtime, instant rollback (flip back), and the deploy itself is
verifiable by the validator agent. Even without full infra, adopt the
principle: deploy to standby, verify, switch.

## Step 7 — headless agent auth (device-code flows)

The factory runs on a server with no browser. Manual auth is the ONLY
manual step, done once:

```bash
gh auth login                # GitHub device-code flow
<agent> login --device-auth  # e.g. codex login --device-auth
<agent> exec "say hi"        # smoke test before trusting the loop
```

Pattern: whatever tool the builder/validator agents use, prefer
`--device-auth` (or equivalent device-code) flows — they are designed for
exactly this headless case. Do the auth on the machine that will run the
loop; tokens live there.

## Step 8 — harden reliability continuously

- **Fresh-factory reps.** Iterate reliability by repeatedly spinning up
  factories from scratch and building real applications with them. Each
  fresh build surfaces stale-assumption bugs in the harness itself.
- **Conversation mining.** Session transcripts (JSONL) are a goldmine.
  Periodically mine them for failure patterns (structured tables/SQL beat
  reading raw JSONL token-by-token), then patch the AI layer — rules,
  factory rules, hooks — so the same mistake can't recur. Example wins:
  "never guess a path" in global rules; a session-start hook injecting the
  live repo tree instead of a stale static layout.
- **System evolution ritual.** After every agent failure, run a sidebar:
  which rule or skill change prevents this next time? Land it as its own
  small PR referencing the ticket. The whole factory improves because the
  guidance layer is in source control.
- **Your existing code review IS the eval.** Optionally add LLM-as-judge
  scoring of rule/skill compliance on PRs.

## Anti-patterns

- Jumping to level 4/5 because the demo looked good. Graduate only on a
  proven level-3 loop.
- Letting the builder see holdout scenarios — that defeats their entire
  purpose.
- Validator sharing the builder's plan/spec context — that re-introduces
  the bias the separation was built to remove.
- One mega-ticket instead of slices — context rot eats it; fresh session
  per slice is the whole point.
- Skipping validation "because it looks right" — unvalidated progress
  doesn't count, ever.
- The agent closing its own tickets — merge/done decisions belong to the
  validator or the human, never the builder.

## Reference

`references/factory-blueprint.md` — a worked factory-setup example
(end-to-end from empty repo to 24/7 loop) plus copy-ready templates for
`GLOBAL_RULES.md`, `FACTORY_RULES.md`, `mission.md`, the issue state
machine, and the cron triage prompt.

### Reference: factory-blueprint.md

# Factory Blueprint — Worked Example + Templates

Grounded in Cole Medin's dark-factory builds (DynaChat, built end-to-end by
a factory without a human reading a line of its code; 24/7 VPS deployment
running Codex/GPT-6 Astra under Archon workflows). Adapt names/commands to
your stack — the structure is the invariant.

---

## Part 1 — Worked setup example: "DynaChat-style" factory from empty repo to 24/7 loop

**Goal:** an AI tutor app grounded in existing content, built and shipped
entirely by the factory.

### Phase A — foundations (human does this once, by hand or with a coding agent)

1. **Empty repo + guidance layer.** Create the repo. Write the three
   guidance files (templates in Part 2). This is the human's main creative
   act — everything downstream is mechanical.
2. **Validation harness.** Standing test suite (`make test` / `npm test` /
   `pytest` — whatever the stack), lint, typecheck, build. The factory
   cannot iterate against validation that doesn't exist. Add the CI
   workflow that runs the suite on every PR.
3. **Holdout scenarios.** Write 5–10 observable-behavior scenarios BEFORE
   any ticket exists ("a learner asks X and receives an answer that cites
   the source video"; "empty question yields a helpful prompt, not a
   crash"). Store in `/holdouts/` — validator sessions mount it, builder
   sessions must not.
4. **Deploy scaffolding.** Blue-green pair (even if just two processes on
   one VPS behind a flip script). The factory will target green only.

### Phase B — first slice through the manual loop (prove the loop at level 3)

5. Write ONE real issue: "Serve a static landing page at /".
6. Run it through the full pipeline by hand: triage → spec → slice →
   builder session → validator session → merge → blue-green flip.
7. Fix what broke — in the guidance files, not just the code. This is the
   system-evolution ritual; do it now, small, before autonomy amplifies
   every flaw.

### Phase C — graduate (human-on-the-loop, level 4)

8. **Headless auth on the host that will run the loop:**
   ```bash
   gh auth login                # GitHub device-code flow
   <agent> login --device-auth  # device flow for the coding agent
   <agent> exec "say hi"        # smoke test — no smoke, no factory
   ```
9. **Install the cron triage loop** (every 30 min), implementing the
   priority order: fix PR → review PR → build next → triage new. The cron
   job reads issue labels as state, acts, writes new labels, exits.
10. **End-to-end test:** file a test issue ("Add a /health endpoint").
    Watch it flow: triage accepts → builder opens PR → validator runs
    visible tests + holdouts → merge → green updated → flip → live.
11. **Go 24/7.** File real issues. Human reviews outcomes at whatever
    cadence the mission demands (daily at first).

### Phase D — level 5, only when earned

12. After sustained clean level-4 runs, widen the mission.md scope, raise
    the escalation threshold (or set "never escalate" explicitly), and let
    small decisions (naming, structure, test coverage, refactors) belong to
    the agent. You now steer with direction only.

---

## Part 2 — Templates

### GLOBAL_RULES.md (loaded in EVERY session — builder, validator, triage)

```markdown
# Global Rules

## Repo layout
- App code: `src/` — tests: `tests/` — docs: `docs/`
- Never guess a path. Search or list before referencing files.

## Commands
- Test: `make test`  Lint: `make lint`  Typecheck: `make typecheck`
- Build: `make build`
- All four must pass before any PR is opened.

## Git discipline
- Branch per issue: `factory/<issue-number>-<slug>`
- Conventional commits. No force-push. No direct pushes to main.

## Style
- Match existing conventions. Smallest change that satisfies the spec.
- Comment WHY, not what. No dead code, no debug prints.
```

### FACTORY_RULES.md (autonomous sessions only — the guardrails)

```markdown
# Factory Rules (autonomous mode)

## Hard stops (escalate to human)
- After 3 failed validation attempts on the same slice.
- Any change to secrets, CI config, deploy scripts, or holdout files.
- Any command that would delete data or force-push.

## Never
- Merge your own PR.
- Skip or weaken a test to make it pass.
- Add dependencies not justified in the spec.
- Touch `main` directly.

## Always
- Run the full visible validation suite; iterate until green.
- Open a PR and stop — do not merge.
- Report blockers as a PR comment and halt.
```

### mission.md (the mission the factory defends — includes NON-goals)

```markdown
# Mission: <product one-liner>

## Goals
- <Goal 1 — the problem being solved>
- <Goal 2 — who it's for>
- <Goal 3 — what "working" means observably>

## Non-goals (the factory may REJECT specs that require these)
- <Explicitly out of scope 1 — e.g. "no multi-tenancy">
- <Out of scope 2 — e.g. "no mobile app; web only">
- <Out of scope 3 — e.g. "no paid billing in v1">

## Current priorities
1. <Priority now>
2. <Next>

## Definition of done (per issue)
- Visible validation suite green; holdouts green; deployed to green and
  flipped without downtime.
```

### Issue state machine (labels = state between 30-min cron runs)

```
rejected          (triage: violates mission non-goals — comment explains why)
accepted          (triage: ranked and ready)
in-progress       (builder session running)
needs-review      (PR open, waiting for validator)
blocked           (failed attempts / waiting on human)
merged            (validator approved, deployed)
```

### Cron triage prompt (runs every 30 minutes, in priority order)

```text
You are the factory triage cron. Read issue labels as state. Execute ONLY
the first applicable step, in this priority order:

1. FIX PR       — an open PR has review comments → builder addresses them.
2. REVIEW PR    — an issue labeled needs-review has an open PR → run the
                  validator (fresh session: diff + holdouts + global rules +
                  mission; NO plan/spec/builder context).
3. BUILD NEXT   — highest-ranked accepted issue with no PR → run the
                  builder (fresh session: spec + slice + global rules +
                  factory rules; NO holdouts).
4. TRIAGE NEW   — unlabeled issues → accept/reject/rank per FACTORY_RULES +
                  mission.md (non-goals ⇒ reject with explanatory comment).

After acting, update labels to the new state and exit. Never do two steps
in one run. Never merge: validator approves, human-or-policy merges per
FACTORY_RULES.
```

### Builder session prompt skeleton

```text
You are the BUILDER. Inputs: this issue's spec + assigned slice +
GLOBAL_RULES.md + FACTORY_RULES.md. You do not have access to holdout
scenarios — do not ask for them. Implement the slice, run the full visible
validation suite, and iterate until it passes. Optimize for correctness,
not speed. Then commit on a factory branch, open a PR describing what
changed and how it was validated, and STOP. Do not merge. Do not alter
tests to pass.
```

### Validator session prompt skeleton

```text
You are the VALIDATOR. Inputs: the PR diff + holdout scenarios +
GLOBAL_RULES.md + mission.md. You receive NO plan, spec, or builder
reasoning — judge only what the diff does. Run the visible suite AND the
holdout scenarios. Approve only if both pass and the change serves the
mission. Post one review comment: verdict + evidence (what you ran, what
passed, what failed).
```

---

## SKILL: enforce-with-hooks


**Skill name:** enforce-with-hooks
description: Design, debug, and deploy hooks that enforce rules deterministically when prompt-based rules fail. Use when the agent ignores instructions or rules, when a guarantee must fire every single time (tests run, secrets protected, style kept, budget capped), when choosing hook event types (PreToolUse, PostToolUse, Stop, SessionStart), when deciding between regex/Jev/LLM classification for hook logic and weighing cost vs false positives, when building guardrails vs reminders, when hooking the OpenClaw or Claude Code agent lifecycle, or when debugging rule drift with ablation/holdout scenarios.


# Enforce With Hooks

Rules in prompts are **probabilistic** — the model may follow them. Hooks are
**deterministic** — they fire every time, no matter what the model "decided."
The core law: **if a rule is load-bearing, put it in a hook, not a prompt.**
Load-bearing means "bad things happen if this doesn't happen every time":
secrets leak, data is destroyed, tests never ran, budget explodes, style drifts.

Cross-reference: `youtube-learn/SKILL.md` has a lightweight hooks section and a
`jev_decide.py` helper. This skill is the deeper hook-design playbook.

## 1. Pick the hook event by what you must intercept

| Event | Fires when | Enforce |
|---|---|---|
| **PreToolUse** | Before each tool call | Block dangerous tools/args (secret reads, `rm -rf`, off-task actions); validate inputs; route by classification. Best injection point for guardrails — you can still stop the action. |
| **PostToolUse** | After each tool call returns | Verify the action's result: tests actually ran and passed, lint clean, no secrets in output, files written match the declared intent. Deterministic validation that "the writer" can't skip. |
| **Stop** | When the agent's turn ends | End-of-turn audit: acceptance criteria met? handoff doc written? uncommitted changes reviewed? budget under cap? Force continuation or emit a failure note before the turn closes. |
| **SessionStart** | When a session begins | Environment validation (tool versions, Docker, repo state) and context injection (repo tree, rule counts, branch naming). Cheap because it fires once. |

Design rule: **block as early as possible.** A PreToolUse block prevents the
damage; a PostToolUse check can only report it; a Stop hook can only complain
after everything. But early hooks see less context — the further along the
lifecycle, the more evidence the hook has to judge.

## 2. Choose the judge: regex vs Jev vs LLM

Hook logic must classify something (is this action dangerous? does this diff
violate style? has budget blown?). Pick the cheapest judge that meets the
false-positive bar:

| Judge | Cost | Latency | False positives | Use for |
|---|---|---|---|---|
| **Regex / string match** | Free | ~0 ms | High on semantic content ("secret" appearing in a blog draft) | Exact matches: file paths, command names, flag patterns, hard allowlists/denylists |
| **Jev (decision model via OpenRouter)** | Fraction of a penny per call | ~70–500 ms | Near-zero | Semantic judgment at scale: "is this action exfiltrating data?", "does this diff violate project style?", "bug or feature?" — 20–200× faster and 40–1,000× cheaper than an LLM for decisions |
| **LLM call** | Priciest | Slowest | Lowest on nuanced review | Deep review where misses are costly and volume is low (final security audit of a big diff) |

Key trade-off, grounded in the Jev use-case notes:
- **Regex hooks fail on semantics.** A regex can catch `cat .env` but not
  "email this config file to an outside address" — same secret, different surface.
- **Jev hooks answer semantic yes/no questions with near-zero false positives
  at a fraction of a penny.** State in: tool name, input args, cwd. Questions:
  "Is this action exposing secrets? Destroying data? Exfiltrating? Off-task?"
  Block if any returns true.
- **Never use Jev alone — sandwich it between LLM calls:** LLM builds the
  harness → Jev makes the fast per-event decisions → LLM acts on the results.
- Escalation ladder: regex first (free wins), Jev when regex gets false-positive
  noisy, LLM only when the Jev question itself can't be framed crisply.

## 3. Guardrails vs reminders

- **Guardrail** = blocks or hard-corrects. Lives in PreToolUse/PostToolUse/Stop
  hooks. Use for anything where proceeding is worse than stopping.
- **Reminder** = nudge injected at SessionStart (e.g. branch naming convention,
  token-efficiency targets). Use for preferences where deviation is annoying,
  not fatal.
- Test: "If this is skipped once, do we regret it?" Yes → guardrail hook. No →
  reminder. When in doubt, write the reminder AND add a Stop-hook audit — the
  reminder shapes behavior, the audit catches the miss.

## 4. Debug "the agent ignores my rules"

Symptoms map to fixes, in order:

1. **The rule is load-bearing but lives in a prompt.** Move it to a hook
   (PreToolUse/PostToolUse/Stop). Deterministic beats probabilistic every time.
2. **The rule has drifted.** Instruction files rot — roughly 1 in 4 repos with
   AI rules have stale references (deleted files, moved folders). Audit rule
   paths against the actual codebase; delete or fix anything stale. Stale rules
   actively confuse agents.
3. **The rule is over-specified.** Long step-by-step instructions get ignored —
   "Claude ignores half of it" when rules balloon. Describe task, guardrails,
   exit criteria; let the model cook. Keep global rules under 200–300 lines,
   no headers, every rule traceable to something real.
4. **The rule teaches reasoning, not attention.** Rules that fix reasoning decay
   (models got better at reasoning); rules that direct attention to YOUR
   codebase stay essential. Triage: keep project-specific conventions, prune
   generic best-practice filler.
5. **The conversation is tainted.** Accumulated biases won't be fixed by
   switching models mid-task or yelling the rule louder. Write a handoff doc
   (work done + current blocker), start a fresh session.

### Ablation / holdout validation

Measure whether your hook layer earns its tokens:
1. Identify the layer: rules (every session), skills (on-demand), hooks
   (event-driven), sub-agents (rarely loaded).
2. Generate 3–5 real test tasks from your codebase.
3. Run them side by side: full layer vs. ablated layer.
4. Grade: project-specific conventions usually break first when hooks/rules
   are removed — those are the ones worth keeping.
5. Frequency: re-test rules every model generation; skills/sub-agents ~yearly.

## 5. The 11 tiny fixes with outsized payoff

1. **Write for agents, not humans** — file paths, exact commands, numbers.
   Agents can't interpret vague guidance.
2. **Audit rules for drift** — stale references confuse; check paths regularly.
3. **Don't trust compaction** — only ~10% of details survive summarization.
   Write handoff docs instead of riding a bloated conversation.
4. **Load-bearing rules go in hooks** — hooks are deterministic, prompts are not.
5. **Less context is more** — global rules under 200–300 lines; generic advice
   hurts more than it helps.
6. **Never let the writer approve its own work** — separate review conversation
   reviews uncommitted changes as a PR.
7. **Never escalate mid-task** — tainted conversation won't be fixed by a
   bigger model; hand off to a fresh session.
8. **Don't over-iterate** — agents "find" unnecessary changes; sycophancy
   degradation makes code worse with each pointless pass.
9. **Avoid coordinator frameworks** — fancy multi-agent team-leads/mailboxes are
   unreliable; simple hooks + sub-agents beat orchestration theater.
10. **Validation is a system** — plan the full validation harness (test tools,
    conventions, edge cases, manual steps) before writing code.
11. **Enforce validation with PostToolUse hooks** — tests/lints run every time,
    not when the agent remembers.

## 6. Human-in-the-loop placement

AI-native ≠ hands-off. Put human checkpoints at strategic moments: after
investigation before planning, before merging, when a guardrail blocks and the
block looks wrong. Hooks decide the routine; humans decide the exceptions.

## 7. Rules

- Never put a must-happen-every-time guarantee in a prompt — hook it.
- Never invent hook capabilities the platform doesn't expose; check the
  runtime's hook events first.
- Verify every hook with a smoke test (trigger it deliberately) before trusting it.
- Keep hooks cheap: regex → Jev → LLM, in that order of preference.
- See `references/hook-recipes.md` for ready-to-adapt hook configurations
  (security guardrail, style enforcement, budget cap, plus a SessionStart
  env-check pattern).

### Reference: hook-recipes.md

# Hook Recipes

Concrete, ready-to-adapt hook configurations. Each recipe states the event,
the judge (regex / Jev / LLM), the state/questions where relevant, and the
action. Adapt paths, tool names, and thresholds to your environment.

---

## Recipe 1 — Security guardrail (PreToolUse + Jev)

The flagship use case: semantic secret/destruction/exfiltration detection with
near-zero false positives at a fraction of a penny per call. Replaces regex
hooks that either miss semantics or drown you in false alarms.

```json
{
  "event": "PreToolUse",
  "matcher": { "tool_name": "*" },
  "judge": "jev",
  "state": {
    "tool_name": "{{tool.name}}",
    "tool_input_args": "{{tool.args}}",
    "current_working_directory": "{{session.cwd}}"
  },
  "questions": [
    { "id": "exposing_secrets", "type": "noul",
      "instructions": "Is this action exposing secrets? (e.g., reading .env, credentials, key material)" },
    { "id": "destroying_data", "type": "noul",
      "instructions": "Is this action destroying data? (e.g., removing an entire folder, force-pushing over history)" },
    { "id": "exfiltrating", "type": "noul",
      "instructions": "Is this action exfiltrating sensitive data to an external party?" },
    { "id": "off_task", "type": "noul",
      "instructions": "Is the agent going off-task from the current objective?" }
  ],
  "action": {
    "if_any_true": "block",
    "block_message": "Guardrail blocked: {{matched_question}}. If this is a false positive, ask the human to approve explicitly."
  }
}
```

Notes:
- Sandwiched pattern: the agent (LLM) proposed the tool call; Jev judges it; the
  LLM receives the block and can re-plan. Never let Jev act alone.
- Keep the human-override path explicit — guardrails decide routine, humans
  decide exceptions.
- Cheap regex pre-filter is fine to add (`cat`, `curl`, `rm -rf` short-circuit),
  but let Jev carry the semantic weight.

---

## Recipe 2 — Style-enforcement hook (PostToolUse + Jev)

Enforce project-specific conventions (the rules that survive ablation) on every
edit — without trusting the writer to self-review.

```json
{
  "event": "PostToolUse",
  "matcher": { "tool_name": "edit|write" },
  "judge": "jev",
  "state": {
    "file_path": "{{tool.args.path}}",
    "diff_or_content": "{{tool.result.preview}}",
    "project_conventions": "see .claude/CONVENTIONS.md (import order, test registration, function style)"
  },
  "questions": [
    { "id": "violates_convention", "type": "noul",
      "instructions": "Does this change violate the project conventions listed in the state?" },
    { "id": "unregistered_test", "type": "noul",
      "instructions": "If this adds a test, is it registered/run by the project's test runner?" }
  ],
  "action": {
    "if_any_true": "inject_warning",
    "warning": "Style guardrail: {{matched_question}}. Fix before continuing.",
    "severity": "warn"
  }
}
```

Notes:
- `severity: warn` nudges; flip to `block` for conventions that have broken
  production before. Match severity to regret-if-skipped.
- Feed the conventions as state (a short excerpt), not as a giant prompt — keep
  per-call cost tiny.

---

## Recipe 3 — Budget cap hook (Stop + regex/accounting)

End-of-turn audit that stops token bleed deterministically. Pure accounting —
no judgment needed, so no LLM/Jev required.

```json
{
  "event": "Stop",
  "matcher": {},
  "judge": "regex",
  "checks": [
    { "id": "budget", "type": "threshold",
      "metric": "session.tokens.total",
      "max": 200000,
      "action": "inject_warning",
      "warning": "Budget cap reached ({{session.tokens.total}}/200000). Wrap up: write the handoff doc now." },
    { "id": "no_output_no_exit", "type": "assert",
      "condition": "session.produced_artifact OR session.wrote_handoff",
      "action": "continue",
      "message": "Turn ended with no deliverable and no handoff doc. Resume or document the blocker." },
    { "id": "uncommitted_review", "type": "assert",
      "condition": "git.status.clean OR session.review_passed",
      "action": "inject_warning",
      "warning": "Uncommitted changes exist. Open a separate review session — never let the writer approve its own work." }
  ]
}
```

Notes:
- Budget numbers are per-session; scale to your plan. The point is the number
  lives in a hook, not in a hopeful prompt line.
- `/usage`-style analytics (weekly %, parallel sub-agent spend) inform where to
  set the cap. Check before tuning.

---

## Recipe 4 — SessionStart environment check (SessionStart + regex)

Fires once per session: validate the environment and inject live context so the
agent starts from facts, not assumptions.

```json
{
  "event": "SessionStart",
  "matcher": {},
  "judge": "regex",
  "checks": [
    { "id": "tools_present", "type": "assert",
      "condition": "which git docker node", "action": "inject_warning",
      "warning": "Missing expected tool: {{missing}}." },
    { "id": "branch_convention", "type": "regex",
      "source": "git branch --show-current",
      "pattern": "^(feature|bug)/",
      "action": "inject_warning",
      "warning": "Branch '{{branch}}' does not match feature/ or bug/ convention." }
  ],
  "inject": [
    { "id": "repo_tree", "command": "git ls-tree -r --name-only HEAD | head -200" },
    { "id": "rule_count", "command": "wc -l AGENTS.md CLAUDE.md 2>/dev/null" }
  ]
}
```

Notes:
- Injection gives the agent real, current context (repo tree, rule counts)
  instead of relying on stale memory of the codebase.
- One-time per session = cheap. Reminders that shape the whole session belong
  here, not repeated in every prompt.

---

## Tuning checklist (applies to all recipes)

1. Smoke-test each hook: trigger the blocked case deliberately.
2. Log every block/warn for a week; count false positives.
3. If false positives climb on a regex rule, reframe it as a Jev question.
4. If a Jev question can't be framed crisply, escalate to an LLM review hook —
  and expect to pay for it.
5. Re-test the whole layer against real tasks every model generation; ablate
  line by line when in doubt.

---

## SKILL: route-interrupts


**Skill name:** route-interrupts
description: >-
  Handle mid-task user interruptions without losing the active task. USE when a
  user message arrives while long work is in flight (subagents running, batches
  processing, multi-step builds) and the message is NOT a stop order: classify
  it as (1) steering addition — folds into the current task, (2) side question
  — answer tersely then resume, (3) new task — queue behind current work and
  report position, or (4) urgent redirect — halt safely at the next checkpoint
  and pivot. Trigger phrases: "also do X" mid-run, "while you're at it",
  "quick question —", user changes requirements during a long operation, "add
  this to what you're doing", "queue this for after", "don't lose track of X".
  ALSO USE when several queued asks compete: keep one visible task stack,
  finish the current item, then pull the next automatically. DO NOT USE for
  genuine stop/abort messages ("stop", "forget it", "halt") — those execute
  immediately, safely.


# Route Interrupts

One rule above all: **an interruption adds to the work or queues behind it — it never silently kills the work already in flight.**

## The four-way classification

On ANY user message that arrives while a task is active, classify before answering:

| Class | Signal | Action |
|---|---|---|
| **Steering** | Refines/extends the current task ("also…", "make sure it…", "change X to Y") | Acknowledge in ≤1 line, fold into the plan, **continue without restarting** unless scope changed materially |
| **Side question** | Unrelated quick ask ("by the way, what's…") | Answer in ≤3 lines, then explicitly resume: "Back to `<task>` —" |
| **New task** | A full new ask ("next I need…", "after this do…") | Append to the task stack, reply with its queue position, start only when current completes — unless the user escalates |
| **Urgent redirect** | "Stop", "forget that", "actually, drop everything" | Halt at the next safe checkpoint (never mid-write), confirm what was preserved, then pivot |

Default assumption when unclear: **steering > new task.** A short message during active work usually means "fold this in," not "abandon ship."

## Protocol

1. **Extract the class first, answer second.** Never let a quick reply derail in-flight subagents or half-written files.
2. **Steering:** state the fold-in in one line ("Got it — adding Y to the current run"). Update the running plan/memory note. Do NOT restart completed work for cosmetic steering.
3. **Side question:** answer terse and completely, then one resume line naming the active task so the thread is never lost.
4. **New task:** maintain the stack visibly — "Queued: (1) current `<task>` → (2) `<new>`". When the current item finishes, pull the next automatically and announce it.
5. **Redirect:** pause at a checkpoint, snapshot state (what's done, what's preserved, what's killed), confirm with the user if anything valuable is in flight, then switch.
6. **Subagent hygiene:** in-flight subagent work is only killed deliberately — check what it already wrote to disk before deciding; partial output often counts as progress.
7. **Completion handoff:** when a task completes and the stack is non-empty, announce the next item in the same message. Silence about the queue reads as "done forever" and wastes the user's momentum.

## Anti-patterns

- Answering a side question and *never* resuming the original task.
- Treating every mid-task message as a full context switch.
- Letting a steering message trigger a full redo of finished steps.
- Killing background work without checking its on-disk output first.
- Queueing silently — the user should always know the stack's shape.
