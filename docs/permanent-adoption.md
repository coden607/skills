# Permanent adoption

Stephen's canonical shared library is this repository. It contains 44 SKILL.md skills as of 2026-10-07.

Persistent AGENTS.md, CLAUDE.md, GEMINI.md and .github/copilot-instructions.md guidance has been added or verified across all 35 coden607 repositories visible to the connected account, plus the authorized restaurant project. Existing project instructions are retained. This guidance selects relevant skills; it does not execute every skill or broaden authorization.

## New projects

Copy project-template/ into the new repository root, including its .github directory, and retain the project's own rules. Commit those instruction files so every checkout gets the shared-library policy.

## CLI machines

On each machine, clone or update this library and use the existing installer with --all-skills (-A) and an explicit runtime skill directory. Example from the library root:

```sh
bash scripts/install-skills-everywhere.sh -A -s . -t /path/to/your/runtime/skills
```

Use a runtime's actual supported skill directory. Restart or refresh its session and verify discovery. Do not run setup scripts that configure keys or unrestricted launchers just to install skills.

## Hosted agents

Use the hosted service's instruction or knowledge import facility. Agents that do not automatically discover repository instruction files must explicitly load AGENTS.md and the relevant SKILL.md files. There is no verified universal setting that installs skills into every AI service.

## Current limits

The ChatGPT personal-skills installation did not save successfully on 2026-10-07. The 44 prepared copies passed local metadata validation, but the save operation failed, so they must not be described as permanently installed. Machines and hosted agents outside this workspace have not been installed or verified. The committed project guidance and new-project templates remain available independently.
