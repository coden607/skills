#!/usr/bin/env python3
"""Install SKILL.md folders with compact frontmatter descriptions.

Copies every top-level skill directory from SOURCE to DESTINATION, preserving
all files and the full SKILL.md body. Only the top-level YAML `description`
field is shortened so runtimes that preload skill descriptions spend fewer
tokens before a skill is selected.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import tempfile
import textwrap
from pathlib import Path

DEFAULT_MAX_CHARS = 200
KEY_RE = re.compile(r"^[A-Za-z0-9_-]+:\s*")
USE_RE = re.compile(r"\buse\s+when\b\s*:?\s*", re.IGNORECASE)
TRIGGER_RE = re.compile(r"\btrigger\s+phrases?\b\s*:?\s*", re.IGNORECASE)
AVOID_RE = re.compile(r"\b(?:do\s+not\s+use|don't\s+use|avoid)\b\s*:?\s*", re.IGNORECASE)


def shorten_words(text: str, limit: int) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text.rstrip(" ,;:-")
    cut = textwrap.shorten(text, width=max(limit, 16), placeholder="")
    return cut.rstrip(" ,;:-")


def compact_description(raw: str, limit: int = DEFAULT_MAX_CHARS) -> str:
    text = " ".join(raw.replace("\n", " ").split()).strip(" \"'")
    if len(text) <= limit:
        return text

    use_match = USE_RE.search(text)
    avoid_match = AVOID_RE.search(text)

    first_boundary = min(
        [m.start() for m in (use_match, avoid_match) if m] or [len(text)]
    )
    summary_src = text[:first_boundary].strip(" .;:-")
    if not summary_src:
        summary_src = text

    sentence = re.split(r"(?<=[.!?])\s+", summary_src, maxsplit=1)[0]
    summary = shorten_words(sentence, min(88, limit))

    pieces = [summary]

    if use_match:
        use_start = use_match.end()
        stops = []
        for rx in (TRIGGER_RE, AVOID_RE):
            m = rx.search(text, use_start)
            if m:
                stops.append(m.start())
        use_end = min(stops) if stops else len(text)
        use_text = text[use_start:use_end].strip(" .;:-")
        budget = max(48, min(96, limit - len(" ".join(pieces)) - 12))
        if use_text:
            pieces.append("Use when: " + shorten_words(use_text, budget))

    if avoid_match:
        avoid_start = avoid_match.end()
        avoid_text = text[avoid_start:].strip(" .;:-")
        remaining = limit - len(" ".join(pieces)) - 8
        if avoid_text and remaining >= 32:
            pieces.append("Avoid: " + shorten_words(avoid_text, remaining - 7))

    result = " ".join(pieces)
    if len(result) > limit:
        result = shorten_words(result, limit)
    return result


def split_frontmatter(text: str) -> tuple[list[str], str]:
    if not text.startswith("---"):
        raise ValueError("SKILL.md has no YAML frontmatter")
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        raise ValueError("SKILL.md must start with ---")
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        raise ValueError("SKILL.md frontmatter is not closed")
    return lines[1:end], "".join(lines[end + 1 :])


def extract_description(front: list[str]) -> tuple[str, int, int]:
    for i, line in enumerate(front):
        if not line.startswith("description:"):
            continue
        tail = line.split(":", 1)[1].strip()
        if tail and not tail.startswith((">", "|")):
            return tail.strip(" \"'"), i, i + 1

        j = i + 1
        chunks: list[str] = []
        while j < len(front):
            nxt = front[j]
            if nxt and not nxt[0].isspace() and KEY_RE.match(nxt):
                break
            chunks.append(nxt.strip())
            j += 1
        return " ".join(chunks).strip(), i, j
    raise ValueError("SKILL.md frontmatter has no top-level description")


def rewrite_description(text: str, limit: int) -> tuple[str, int, int]:
    front, body = split_frontmatter(text)
    raw, start, end = extract_description(front)
    compact = compact_description(raw, limit)

    width = max(40, min(96, limit))
    wrapped = textwrap.wrap(
        compact,
        width=width,
        break_long_words=False,
        break_on_hyphens=False,
    )
    replacement = ["description: >-\n"] + [f"  {line}\n" for line in wrapped]
    new_front = front[:start] + replacement + front[end:]
    output = "---\n" + "".join(new_front) + "---\n" + body
    return output, len(raw), len(compact)


def install_skill(source: Path, destination: Path, limit: int) -> tuple[int, int]:
    target = destination / source.name
    temp_parent = Path(tempfile.mkdtemp(prefix=f".{source.name}.", dir=destination))
    staged = temp_parent / source.name
    backup: Path | None = None
    try:
        shutil.copytree(source, staged, symlinks=True)
        skill_file = staged / "SKILL.md"
        original = skill_file.read_text(encoding="utf-8")
        rewritten, before, after = rewrite_description(original, limit)
        skill_file.write_text(rewritten, encoding="utf-8")

        if target.exists() or target.is_symlink():
            backup = destination / f".{source.name}.old-{os.getpid()}"
            if backup.exists() or backup.is_symlink():
                if backup.is_dir() and not backup.is_symlink():
                    shutil.rmtree(backup)
                else:
                    backup.unlink()
            target.rename(backup)

        staged.rename(target)
        if backup:
            if backup.is_dir() and not backup.is_symlink():
                shutil.rmtree(backup)
            else:
                backup.unlink()
        return before, after
    except BaseException:
        if backup and backup.exists() and not target.exists():
            backup.rename(target)
        raise
    finally:
        shutil.rmtree(temp_parent, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Copy all top-level skills while compressing only SKILL.md descriptions."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--max-chars", type=int, default=DEFAULT_MAX_CHARS)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    destination = args.destination.expanduser().resolve()
    if args.max_chars < 80:
        parser.error("--max-chars must be at least 80")
    if not source.is_dir():
        parser.error(f"source is not a directory: {source}")
    if source == destination:
        parser.error("source and destination must be different")

    destination.mkdir(parents=True, exist_ok=True)
    skills = sorted(
        p for p in source.iterdir()
        if p.is_dir() and (p / "SKILL.md").is_file()
    )
    if not skills:
        parser.error(f"no top-level SKILL.md folders found in {source}")

    total_before = total_after = 0
    for skill in skills:
        before, after = install_skill(skill, destination, args.max_chars)
        total_before += before
        total_after += after
        if args.verbose:
            print(f"{skill.name}: {before} -> {after} chars")

    saved = total_before - total_after
    pct = (saved / total_before * 100.0) if total_before else 0.0
    print(
        f"Installed {len(skills)} skills into {destination} | "
        f"descriptions {total_before} -> {total_after} chars "
        f"({pct:.1f}% smaller)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
