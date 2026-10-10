#!/usr/bin/env python3
"""Build a portable ChatGPT knowledge bundle from the canonical skills tree."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

TEXT_EXTS = {
    ".md", ".txt", ".py", ".sh", ".json", ".yaml", ".yml", ".toml",
    ".js", ".jsx", ".ts", ".tsx", ".html", ".css", ".sql", ".csv",
}


def frontmatter(text: str) -> str:
    match = re.match(r"^---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    return match.group(1) if match else ""


def description(text: str) -> str:
    lines = frontmatter(text).splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"^description:\s*(.*)$", line)
        if not match:
            continue
        value = match.group(1).strip()
        if value and not re.fullmatch(r"[>|][+-]?", value):
            return value.strip("'").strip('"')
        parts: list[str] = []
        for nxt in lines[i + 1:]:
            if re.match(r"^[A-Za-z0-9_-]+:\s*", nxt):
                break
            if nxt[:1].isspace():
                parts.append(nxt.strip())
            elif nxt.strip():
                break
        return re.sub(r"\s+", " ", " ".join(parts)).strip()
    return ""


def skill_name(text: str, fallback: str) -> str:
    match = re.search(r"^name:\s*(.+?)\s*$", frontmatter(text), re.M)
    return match.group(1).strip().strip("'").strip('"') if match else fallback


def text_files(skill_dir: Path) -> list[Path]:
    result: list[Path] = []
    for path in sorted(skill_dir.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in TEXT_EXTS:
            continue
        try:
            path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        result.append(path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    skills = sorted(
        [d for d in root.iterdir() if d.is_dir() and (d / "SKILL.md").is_file()],
        key=lambda d: d.name,
    )
    if not skills:
        raise SystemExit("no top-level skills found")

    sections = [
        "# Coden607 Skills — ChatGPT Knowledge Bundle",
        "",
        "Canonical source: https://github.com/coden607/skills",
        "",
        f"Skill count: **{len(skills)}**",
        "",
        "Use bundle.md as the router. Select the smallest relevant skill set; do not execute all skills automatically.",
        "",
    ]
    manifest = {"skill_count": len(skills), "skills": []}

    for directory in skills:
        raw = (directory / "SKILL.md").read_text(encoding="utf-8")
        name = skill_name(raw, directory.name)
        desc = description(raw)
        rel = directory.relative_to(root).as_posix()
        files = text_files(directory)
        manifest["skills"].append({
            "name": name,
            "path": f"{rel}/SKILL.md",
            "files": len(files),
        })

        sections.extend([
            "---",
            "",
            f"## SKILL: {name}",
            "",
            f"**Use when:** {desc or '(see SKILL.md frontmatter)'}",
            "",
        ])
        for path in files:
            file_rel = path.relative_to(root).as_posix()
            sections.extend([
                f"### FILE: {file_rel}",
                "",
                "~~~~~~text",
                path.read_text(encoding="utf-8").rstrip(),
                "~~~~~~",
                "",
            ])

    (output_dir / "coden607-skills-bundle.md").write_text(
        "\n".join(sections).rstrip() + "\n",
        encoding="utf-8",
    )
    (output_dir / "bundle.md").write_text(
        (root / "bundle.md").read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    project = root / "chatgpt-bundle" / "PROJECT-INSTRUCTIONS.md"
    if project.exists():
        (output_dir / "PROJECT-INSTRUCTIONS.md").write_text(
            project.read_text(encoding="utf-8"),
            encoding="utf-8",
        )

    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"built ChatGPT bundle: {len(skills)} skills -> {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
