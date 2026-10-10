# Legacy ChatGPT bundle filename

This legacy six-skill snapshot is retired.

Use the canonical runtime router and generated full bundle instead:

- `bundle.md`
- `chatgpt-bundle/PROJECT-INSTRUCTIONS.md`
- generate the current full bundle with:
  `python3 scripts/build-runtime-bundles.py --output-dir /tmp/coden607-chatgpt`

The generator reads every current top-level `*/SKILL.md` plus text support files, so it stays aligned with the canonical repository instead of freezing an old subset.
